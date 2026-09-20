#!/usr/bin/env python3
"""
stats_compare_v2.py
====================

Generuje raport statystyczny porownujacy wydajnosc roznych konfiguracji
mTLS (RPS, latency, CPU, RAM) wzgledem baseline'u, ORAZ osobno weryfikuje
na podstawie plikow cipher_stats_*_before/after, czy w kazdym setupie
faktycznie zanotowano wzrost licznika oczekiwanego szyfru/krzywej
(ten sam pomysl co w verify_ciphers.sh, tylko automatycznie i dla kazdego
pelnego przebiegu z osobna).

DLACZEGO NOWA WERSJA, A NIE LATKA STAREJ:
------------------------------------------
1. Stara kolumna "TLS_hs mean(ms)" byla ZAWSZE n/a, bo liczyla sie z
   licznika Envoya "ssl_handshake". Ten licznik jest typu COUNTER
   (liczba zdarzen w czasie), a nie HISTOGRAM (rozklad czasu trwania) -
   nie ma wiec z czego policzyc sredniego czasu w milisekundach.
   Ten skrypt w ogole nie probuje juz tego robic z Envoy stats.

2. Dla scenariuszy typu "handshake" najbardziej sensowna miara narzutu
   TLS to LATENCY (avg_ms / p95_ms), a nie RPS - bo te scenariusze uzywaja
   stalego tempa zapytan (constant-arrival-rate / HANDSHAKE_RATE), wiec
   RPS jest z gory ograniczone i nie mowi nic o narzucie kryptograficznym.
   Dlatego ten skrypt automatycznie przelacza metryke porownawcza w
   zaleznosci od typu scenariusza - patrz funkcja comparison_metric_for().

3. Doszlo CPU/RAM proxy z plikow metrics_*.json (ta sama logika co w
   compare_results.py), zeby nie trzeba bylo patrzec w dwa oddzielne
   raporty.

4. Doszlo ostrzezenie, jesli w jednej grupie (setup, scenariusz) trafily
   sie pliki z wiecej niz jednym znacznikiem czasu (TIMESTAMP) - to sygnal,
   ze archiwizacja starych wynikow (archive_results.py) mogla sie kiedys
   nie udac i w jednym "n" mieszamy wyniki z dwoch roznych przebiegow
   (mozliwe, ze nawet z rozna wersja kodu/konfiguracji).

Skrypt celowo NIE uzywa numpy/scipy - tylko biblioteki standardowej
Pythona - zeby dalo sie latwo przejsc przez kazda linijke krok po kroku
(np. na obronie pracy) bez odwolywania sie do "czarnej skrzynki".

UWAGA - RZECZY DO RECZNEGO SPRAWDZENIA PRZED UZYCIEM:
- Slownik CIPHER_EXPECTATIONS nizej zawiera nazwy szyfrow/krzywych
  dopasowane do tego, co widac w logach verify_ciphers.sh - ale to
  MUSISZ zweryfikowac wzgledem realnej tresci swoich plikow
  envoyfilter_*.yaml, bo to nie jest odczytywane automatycznie z YAML-i.
- read_container_metric() zaklada, ze znaczniki czasu w metrics_*.json
  sa w formacie ISO-8601 UTC (jak START_TIME/END_TIME w
  run_all_test_v2.sh, generowane przez `date -u`). Jesli fetch_and_plot.py
  zapisuje je w innym formacie (np. epoch ms albo z offsetem strefy),
  trzeba to ujednolicic - patrz komentarz przy tej funkcji.
"""

import argparse
import json
import random
import re
import statistics
from collections import defaultdict
from math import erf, sqrt
from pathlib import Path


# ---------------------------------------------------------------------------
# KONFIGURACJA - te rzeczy trzeba dopasowac do wlasnego projektu
# ---------------------------------------------------------------------------

# Wzorzec nazwy pliku podsumowania k6, zgodny z run_all_test_v2.sh:
#   summary_{setup}_{scenario}[-nokeepalive]_run{N}_{TIMESTAMP}.json
FNAME_RE = re.compile(
    r"^summary_(?P<setup>.+?)_(?P<scenario>baseline|payload|stress|handshake)"
    r"(?P<suffix>-nokeepalive)?_run(?P<run>\d+)_(?P<timestamp>\d{8}_\d{6})\.json$"
)

# Nazwy kontenerow tak, jak sa zapisywane w metrics_*.json przez
# fetch_and_plot.py. Jesli tam uzywacie innych etykiet - zmienic tutaj.
PROXY_CONTAINER = "httpbin-proxy"
APP_CONTAINER = "httpbin-app"

# Czego oczekujemy w plikach cipher_stats_{setup}_before/after_*.txt dla
# kazdego setupu. Klucz to nazwa setupu (taka jak w nazwach plikow),
# wartosc to fragment nazwy licznika Envoya, ktory MUSI zanotowac wzrost.
# UWAGA: dopasuj to do realnych nazw szyfrow/krzywych negocjowanych przez
# Waszego Envoya (sprawdzone np. przez verify_ciphers.sh) - ponizej sa
# wartosci widoczne w logach z tamtego skryptu.
CIPHER_EXPECTATIONS = {
    "mtls1.2-gcm":         {"cipher_contains": "AES128-GCM"},
    "mtls1.2-gcm256":      {"cipher_contains": "AES256-GCM"},
    "mtls1.2-chacha":      {"cipher_contains": "CHACHA20"},
    "mtls1.2-cbc":         {"cipher_contains": "AES128-SHA256"},
    "mtls1.2-ccm":         {"cipher_contains": "CCM"},
    "mtls1.3-postquantum": {"curve_contains": "MLKEM"},
    # "mtls1.3-default" i "plaintext" celowo pominiete: nic tu nie jest
    # wymuszane przez EnvoyFilter, wiec nie ma jednoznacznego "oczekiwanego"
    # wyniku do sprawdzenia - Envoy sam wybiera domyslny zestaw.
}


# ---------------------------------------------------------------------------
# STATYSTYKA - male, samodzielne implementacje (bez numpy/scipy)
# ---------------------------------------------------------------------------

def bootstrap_ci(values, n_boot=5000, ci=0.95, seed=42):
    """95% przedzial ufnosci dla sredniej metoda bootstrap (losowanie ze
    zwracaniem z posiadanych probek). Dla n<2 nie da sie tego policzyc."""
    rng = random.Random(seed)
    n = len(values)
    if n < 2:
        return (values[0], values[0]) if values else (float("nan"), float("nan"))
    means = []
    for _ in range(n_boot):
        sample = [values[rng.randrange(n)] for _ in range(n)]
        means.append(statistics.fmean(sample))
    means.sort()
    lo_idx = int((1 - ci) / 2 * n_boot)
    hi_idx = int((1 + ci) / 2 * n_boot) - 1
    return means[lo_idx], means[hi_idx]


def mann_whitney_u(a, b):
    """Test U Manna-Whitneya (dwustronny, przyblizenie normalne dla p-value).
    Nieparametryczny odpowiednik testu t - nie zaklada rozkladu normalnego,
    co ma sens przy n=3-5 probek na grupe, jak w tym projekcie."""
    combined = sorted([(v, "a") for v in a] + [(v, "b") for v in b])
    ranks = {}
    i = 0
    n = len(combined)
    while i < n:
        j = i
        while j < n and combined[j][0] == combined[i][0]:
            j += 1
        avg_rank = (i + 1 + j) / 2
        for k in range(i, j):
            ranks[k] = avg_rank
        i = j
    rank_a = sum(ranks[idx] for idx, (v, g) in enumerate(combined) if g == "a")
    n1, n2 = len(a), len(b)
    u1 = rank_a - n1 * (n1 + 1) / 2
    u2 = n1 * n2 - u1
    u = min(u1, u2)
    mu = n1 * n2 / 2
    sigma = ((n1 * n2 * (n1 + n2 + 1)) / 12) ** 0.5
    if sigma == 0:
        return u, 1.0
    z = (u - mu) / sigma
    p = 2 * (1 - 0.5 * (1 + erf(abs(z) / sqrt(2))))
    return u, min(p, 1.0)


def detect_outliers(values, z_thresh=2.0):
    """Zwraca indeksy wartosci odstajacych o wiecej niz z_thresh odchylenia
    standardowego od sredniej. Wymaga minimum 3 probek, zeby mialo to sens."""
    if len(values) < 3:
        return []
    mean = statistics.fmean(values)
    sd = statistics.pstdev(values)
    if sd == 0:
        return []
    return [i for i, v in enumerate(values) if abs(v - mean) / sd > z_thresh]


# ---------------------------------------------------------------------------
# WCZYTYWANIE WYNIKOW WYDAJNOSCIOWYCH (summary_*.json + metrics_*.json)
# ---------------------------------------------------------------------------

def read_container_metric(metrics_path: Path, metric_type: str, container: str):
    """Czyta metrics_*.json i zwraca srednia wartosc danej metryki
    (np. 'cpu' albo 'memory') dla wskazanego kontenera, tylko z probek
    miesczacych sie w oknie czasowym testu ('window.start'..'window.end').
    Zwraca None, jesli plik nie istnieje albo nie ma pasujacych danych.

    Porownanie znacznikow czasu jest tu CZYSTO TEKSTOWE (string <= string).
    Dziala to poprawnie TYLKO jesli wszystkie znaczniki (window.start/end
    ORAZ timestamp kazdej probki) sa zapisane w tym samym, spojnym formacie
    ISO-8601 UTC, np. "2026-09-20T10:15:00Z" - tak jak START_TIME/END_TIME
    w run_all_test_v2.sh (generowane przez `date -u`). Jesli fetch_and_plot.py
    zapisuje znaczniki inaczej, ta funkcja da bledne wyniki bez ostrzezenia -
    warto to zweryfikowac jednym przykladowym plikiem metrics_*.json."""
    if not metrics_path.exists():
        return None
    try:
        data = json.loads(metrics_path.read_text(encoding="utf-8"))
    except Exception:
        return None

    points = data.get(metric_type, [])
    window = data.get("window", {})
    w_start = window.get("start")
    w_end = window.get("end")

    vals = []
    for p in points:
        if p.get("container") != container:
            continue
        ts = p.get("timestamp")
        if w_start and w_end and ts:
            if not (w_start <= ts <= w_end):
                continue
        vals.append(p["value"])

    if not vals:
        return None
    return statistics.fmean(vals)


def load_runs(results_dir: Path, metrics_dir: Path):
    """Wczytuje wszystkie summary_*.json z folderu wynikow i grupuje je
    po (setup, scenariusz). Dla kazdego przebiegu dokleja tez CPU/RAM
    z odpowiadajacego metrics_*.json (jesli istnieje)."""
    groups = defaultdict(list)
    skipped = []

    for f in sorted(results_dir.glob("summary_*.json")):
        m = FNAME_RE.match(f.name)
        if not m:
            skipped.append(f.name)
            continue

        setup = m.group("setup")
        scenario_full = m.group("scenario") + (m.group("suffix") or "")
        run = int(m.group("run"))
        timestamp = m.group("timestamp")

        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"# UWAGA: nie udalo sie wczytac {f.name}: {e}")
            continue

        metrics = data.get("metrics", {})
        rps = metrics.get("http_reqs", {}).get("values", {}).get("rate")
        avg = metrics.get("http_req_duration", {}).get("values", {}).get("avg")
        p95 = metrics.get("http_req_duration", {}).get("values", {}).get("p(95)")
        success = metrics.get("success_rate", {}).get("values", {}).get("rate")

        if rps is None or avg is None:
            # Brak podstawowych metryk k6 - plik jest bezuzyteczny, ale nie
            # przerywamy z tego powodu calego raportu.
            print(f"# UWAGA: {f.name} nie ma http_reqs/http_req_duration - pomijam")
            continue

        metrics_path = metrics_dir / f.name.replace("summary_", "metrics_", 1)
        proxy_cpu = read_container_metric(metrics_path, "cpu", PROXY_CONTAINER)
        app_cpu = read_container_metric(metrics_path, "cpu", APP_CONTAINER)
        proxy_mem = read_container_metric(metrics_path, "memory", PROXY_CONTAINER)

        groups[(setup, scenario_full)].append({
            "run": run,
            "file": f.name,
            "timestamp": timestamp,
            "rps": rps,
            "avg_ms": avg,
            "p95_ms": p95,
            "success_rate": success,
            "proxy_cpu": proxy_cpu,
            "app_cpu": app_cpu,
            "proxy_mem": proxy_mem,
        })

    if skipped:
        print(f"# Info: pominieto {len(skipped)} plikow niepasujacych do wzorca "
              f"nazwy (np. {skipped[0]!r})\n")

    return groups


# ---------------------------------------------------------------------------
# WERYFIKACJA CIPHER/CURVE (cipher_stats_{setup}_before/after_*.txt)
# ---------------------------------------------------------------------------

def parse_cipher_stats_file(path: Path):
    """Parsuje plik w formacie:
        listener.0.0.0.0_15006.ssl.ciphers.ECDHE-RSA-AES128-GCM-SHA256: 5
    do slownika {pelna_nazwa_licznika: wartosc}."""
    counts = {}
    if not path.exists():
        return counts
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or ":" not in line:
            continue
        key, _, val = line.rpartition(":")
        try:
            counts[key.strip()] = int(val.strip())
        except ValueError:
            continue
    return counts


def verify_cipher_setup(summary_dir: Path, setup: str, expectation: dict):
    """Dla jednego setupu znajduje NAJNOWSZA pare plikow
    cipher_stats_{setup}_before/after_{timestamp}.txt, liczy delte
    licznikow i sprawdza, czy oczekiwany szyfr/krzywa faktycznie
    zanotowaly przyrost w tym oknie - dokladnie to, co robi recznie
    verify_ciphers.sh, tylko automatycznie."""
    before_files = sorted(summary_dir.glob(f"cipher_stats_{setup}_before_*.txt"))
    if not before_files:
        return {"status": "brak_danych", "detail": "nie znaleziono pliku 'before'"}

    latest_before = before_files[-1]
    ts_match = re.search(r"_before_(.+)\.txt$", latest_before.name)
    ts = ts_match.group(1) if ts_match else None
    latest_after = summary_dir / f"cipher_stats_{setup}_after_{ts}.txt" if ts else None

    before = parse_cipher_stats_file(latest_before)
    after = parse_cipher_stats_file(latest_after) if latest_after and latest_after.exists() else {}

    if not after:
        return {"status": "brak_danych", "detail": f"brak pliku 'after' dla timestamp {ts}"}

    delta = {k: v - before.get(k, 0) for k, v in after.items()}
    delta = {k: v for k, v in delta.items() if v != 0}

    result = {"status": "ok", "timestamp": ts, "delta": delta}

    if "cipher_contains" in expectation:
        needle = expectation["cipher_contains"]
        result["cipher_ok"] = any(needle in k and v > 0 for k, v in delta.items())
        result["cipher_expected"] = needle
    if "curve_contains" in expectation:
        needle = expectation["curve_contains"]
        result["curve_ok"] = any(needle in k and v > 0 for k, v in delta.items())
        result["curve_expected"] = needle

    return result


def print_tls_verification_section(summary_dir: Path):
    print("## Weryfikacja realnie wynegocjowanego TLS (dowody before/after)\n")
    print("Sprawdzane na podstawie liczników Envoya `ssl.ciphers.*` / "
          "`ssl.curves.*` z portu admina 15000 - przyrost licznika w oknie "
          "testu oznacza, ze ten szyfr/krzywa zostaly faktycznie uzyte w "
          "negocjacji, a nie tylko poprawnie skonfigurowane w YAML-u.\n")
    print("| Setup | Oczekiwano | Wykryto przyrost? | Status |")
    print("|---|---|---|---|")

    any_problem = False
    for setup, expectation in CIPHER_EXPECTATIONS.items():
        result = verify_cipher_setup(summary_dir, setup, expectation)

        if result["status"] == "brak_danych":
            print(f"| **{setup}** | - | - | ⚠️ {result['detail']} |")
            any_problem = True
            continue

        checks = []
        ok = True
        if "cipher_ok" in result:
            checks.append(f"cipher zawiera `{result['cipher_expected']}`")
            ok = ok and result["cipher_ok"]
        if "curve_ok" in result:
            checks.append(f"krzywa zawiera `{result['curve_expected']}`")
            ok = ok and result["curve_ok"]

        status = "✅ OK" if ok else "❌ NIEZGODNE"
        if not ok:
            any_problem = True
        print(f"| **{setup}** | {', '.join(checks)} | "
              f"{'TAK' if ok else 'NIE'} | {status} |")

    if any_problem:
        print("\n> ⚠️ Co najmniej jeden setup nie potwierdzil oczekiwanej "
              "konfiguracji TLS w ostatnim przebiegu. Wyniki wydajnosciowe "
              "dla tego setupu NIE powinny trafic do pracy, dopoki sie to "
              "nie wyjasni (podejrzane manifesty EnvoyFilter warto sprawdzic "
              "recznie przez `istioctl proxy-config` albo ponownie przez "
              "verify_ciphers.sh).")
    print()


# ---------------------------------------------------------------------------
# RAPORT WYDAJNOSCIOWY (per scenariusz)
# ---------------------------------------------------------------------------

def comparison_metric_for(scenario: str):
    """Dla scenariuszy typu 'handshake*' metryka porownawcza to latency
    (avg_ms), bo RPS jest tam sztucznie ograniczone stalym tempem
    (constant-arrival-rate / HANDSHAKE_RATE). Dla reszty scenariuszy - RPS."""
    if scenario.startswith("handshake"):
        return "avg_ms"
    return "rps"


def fmt(value, decimals=2):
    if value is None or value != value:  # None albo NaN
        return "n/d"
    return f"{value:.{decimals}f}"


def print_scenario_table(groups, baseline_setup, scenario, sig_test_counter):
    print(f"### SCENARIUSZ: `{scenario}`\n")

    metric_key = comparison_metric_for(scenario)
    metric_label = "avg_ms" if metric_key == "avg_ms" else "RPS"
    reason = ("RPS jest tu ograniczone stalym tempem zapytan (constant-arrival-rate), "
              "wiec liczy sie latency. Wiecej avg_ms = gorzej (wolniej)."
              if metric_key == "avg_ms" else
              "mierzymy maksymalny throughput. Wiecej RPS = lepiej.")
    print(f"*Metryka porownawcza dla tego scenariusza: **{metric_label}** ({reason})*\n")

    baseline_runs = groups.get((baseline_setup, scenario), [])
    baseline_vals = [r[metric_key] for r in baseline_runs if r[metric_key] is not None]

    timestamps_seen = defaultdict(set)

    print("| Setup | n | RPS mean | avg_ms mean | p95_ms mean | CI95* | CV%* | "
          "Proxy CPU(m) | Proxy Mem(MB) | vs baseline |")
    print("|---|---|---|---|---|---|---|---|---|---|")

    setups = sorted({s for (s, sc) in groups if sc == scenario})
    for setup in setups:
        runs = groups.get((setup, scenario), [])
        if not runs:
            continue

        for r in runs:
            timestamps_seen[setup].add(r["timestamp"])

        n = len(runs)
        rps_vals = [r["rps"] for r in runs]
        avg_vals = [r["avg_ms"] for r in runs]
        p95_vals = [r["p95_ms"] for r in runs if r["p95_ms"] is not None]
        cpu_vals = [r["proxy_cpu"] for r in runs if r["proxy_cpu"] is not None]
        mem_vals = [r["proxy_mem"] for r in runs if r["proxy_mem"] is not None]
        compare_vals = [r[metric_key] for r in runs if r[metric_key] is not None]

        mean_rps = statistics.fmean(rps_vals)
        mean_avg = statistics.fmean(avg_vals)
        mean_p95 = statistics.fmean(p95_vals) if p95_vals else None
        mean_cpu = statistics.fmean(cpu_vals) if cpu_vals else None
        mean_mem = statistics.fmean(mem_vals) if mem_vals else None

        mean_compare = statistics.fmean(compare_vals) if compare_vals else None
        sd_compare = statistics.pstdev(compare_vals) if len(compare_vals) > 1 else 0.0
        cv = (sd_compare / mean_compare * 100) if mean_compare else 0.0

        if len(compare_vals) >= 2:
            lo, hi = bootstrap_ci(compare_vals)
            ci_str = f"[{lo:.1f}, {hi:.1f}]"
        else:
            ci_str = "n/d (n=1)"

        if setup == baseline_setup:
            cmp_str = "**-- (baseline) --**"
        elif len(baseline_vals) >= 2 and len(compare_vals) >= 2:
            _, p = mann_whitney_u(baseline_vals, compare_vals)
            base_mean = statistics.fmean(baseline_vals)
            pct = (mean_compare - base_mean) / base_mean * 100 if base_mean else float("nan")
            sig = "**ISTOTNE**" if p < 0.05 else "szum statystyczny"
            sig_test_counter[0] += 1
            cmp_str = f"{metric_label} {pct:+.2f}% (p={p:.3f}) [{sig}]"
        else:
            cmp_str = (f"za malo probek do testu (potrzeba >=2 w obu grupach, "
                       f"jest {len(compare_vals)})")

        print(f"| **{setup}** | {n} | {fmt(mean_rps, 1)} | {fmt(mean_avg)} | "
              f"{fmt(mean_p95)} | {ci_str} | {cv:.1f}% | {fmt(mean_cpu, 1)} | "
              f"{fmt(mean_mem, 1)} | {cmp_str} |")

    # Ostrzezenia: za malo powtorzen, outliery, wymieszane znaczniki czasu
    for setup in setups:
        runs = groups.get((setup, scenario), [])
        if not runs:
            continue

        if len(timestamps_seen[setup]) > 1:
            print(f"\n> 🚨 **MIESZANE DANE:** Setup `{setup}` w tym scenariuszu laczy "
                  f"pliki z {len(timestamps_seen[setup])} roznych przebiegow testow "
                  f"({', '.join(sorted(timestamps_seen[setup]))}). Prawdopodobnie "
                  f"archiwizacja starych wynikow (archive_results.py) w ktoryms "
                  f"momencie sie nie powiodla i n={len(runs)} miesza wyniki z roznych "
                  f"przebiegow (mozliwe, ze z rozna wersja kodu/konfiguracji). "
                  f"Sprawdz to przed uzyciem tych liczb w pracy.")

        metric_key_local = comparison_metric_for(scenario)
        vals_for_outliers = [r[metric_key_local] for r in runs if r[metric_key_local] is not None]
        outliers = detect_outliers(vals_for_outliers)
        for oi in outliers:
            r = runs[oi]
            print(f"\n> 🚨 **OUTLIER:** Setup `{setup}` run=`{r['run']}` "
                  f"{metric_key_local}=`{r[metric_key_local]:.2f}` "
                  f"(odstaje >2.0σ od reszty przebiegow tego samego setupu)")

        if len(runs) < 3:
            print(f"\n> ⚠️ **UWAGA:** Setup `{setup}` ma n={len(runs)} < 3. "
                  f"Za malo powtorzen do wiarygodnej oceny statystycznej.")

    print("\n---\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--results-dir", default="./04_results/Summary")
    ap.add_argument("--metrics-dir", default="./04_results/Metrics")
    ap.add_argument("--baseline", default="plaintext")
    args = ap.parse_args()

    results_dir = Path(args.results_dir)
    metrics_dir = Path(args.metrics_dir)

    print("# Raport Statystyczny Porownania Wydajnosci mTLS\n")
    print(f"**Katalog wynikow:** `{results_dir}`  ")
    print(f"**Katalog metryk CPU/RAM:** `{metrics_dir}`  ")
    print(f"**Baseline:** `{args.baseline}`\n")

    print_tls_verification_section(results_dir)

    groups = load_runs(results_dir, metrics_dir)
    if not groups:
        print("Brak wynikow do przeanalizowania w podanym katalogu.")
        return

    scenarios = sorted({sc for (_, sc) in groups})
    sig_test_counter = [0]  # jednoelementowa lista jako "wskaznik" mutowalny w funkcjach
    for scenario in scenarios:
        print_scenario_table(groups, args.baseline, scenario, sig_test_counter)

    n_tests = sig_test_counter[0]
    if n_tests:
        print(f"\n*Wykonano lacznie {n_tests} testow istotnosci (Mann-Whitney U) w "
              f"tym raporcie, kazdy przy progu α=0.05 bez korekty na wielokrotne "
              f"porownania. Przy tylu testach nalezy statystycznie spodziewac sie "
              f"ok. {n_tests * 0.05:.1f} falszywie pozytywnego wyniku 'ISTOTNE' "
              f"czysto z przypadku - warto o tym wspomniec w ograniczeniach "
              f"metodologii pracy, albo zastosowac korekte Bonferroniego "
              f"(α_skorygowane = 0.05 / {n_tests} = {0.05 / n_tests:.4f}).*")


if __name__ == "__main__":
    main()