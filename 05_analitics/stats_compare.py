#!/usr/bin/env python3
"""
stats_compare.py

CEL: Zamiast golego "RPS diff: -0.90%" (ktory nic nie mowi bez powtorzen),
ten skrypt:
  1. Grupuje wyniki po (setup, scenariusz) na podstawie WIELU przebiegow
     (patrz patched_run_all_test.sh - dodaje run{N} do nazwy pliku).
  2. Liczy srednia, odchylenie std, wspolczynnik zmiennosci (CV) i 95% CI
     (bootstrap) dla RPS oraz latency avg/p95.
  3. Wykrywa outliery w obrebie danego (setup, scenariusz) - np. ten
     podejrzany przebieg mtls1.2-gcm/PAYLOAD z Proxy Mem=54.7MB kiedy
     reszta ma ~85-93MB - przez z-score > 2.0.
  4. Robi test istotnosci (Mann-Whitney U, bo malo probek i brak zalozenia
     normalnosci) kazdego setupu vs baseline (domyslnie mtls1.3-default)
     per scenariusz i mowi WPROST "brak podstaw by mowic o roznicy"
     zamiast pokazywac % ktory wyglada jak sygnal, a jest szumem.

WYMAGA min. 3 powtorzen na (setup, scenariusz) zeby cokolwiek policzyc
sensownie - z 1 przebiegiem i tak nie masz podstaw do wniosku, ten skrypt
tylko to nazwie zamiast pozwolic Ci przeoczyc.

UZYCIE:
  python3 stats_compare.py --results-dir ./04_results/Summary \
      --baseline mtls1.3-default

Oczekiwany format nazw plikow (patrz patched run_all_test.sh):
  summary_<setup>_<scenario>[-nokeepalive]_run<N>_<timestamp>.json

Kazdy plik to standardowy output k6 handleSummary() (cale `data` z API k6),
z ktorego biezemy data['metrics']['http_reqs']['values']['rate'] jako RPS
oraz data['metrics']['http_req_duration']['values']['avg'/'p(95)'].
"""
import argparse
import json
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

FNAME_RE = re.compile(
    r"^summary_(?P<setup>.+?)_(?P<scenario>baseline|payload|stress|handshake)"
    r"(?P<suffix>-nokeepalive)?_run(?P<run>\d+)_(?P<timestamp>\d{8}_\d{6})\.json$"
)

HANDSHAKE_CSV_RE = re.compile(
    r"^(?P<setup>.+?)_(?P<scenario>baseline|payload|stress|handshake)"
    r"(?P<suffix>-nokeepalive)?_run(?P<run>\d+)_(?P<timestamp>\d{8}_\d{6})$"
)


def load_handshake_csv(results_dir: Path):
    """Wczytuje handshake_latency.csv (generowany teraz przez
    run_all_test_patched.sh na podstawie histogramu ssl.handshake z Envoy,
    nie z k6 - k6 nigdy nie widzi TLS w architekturze sidecara, wiec
    metryka tls_handshake_ms z samego k6 jest zawsze 0 i nie ma sensu jej
    uzywac). Zwraca dict: (setup, scenario_full, run) -> mean_ms."""
    csv_path = results_dir / "handshake_latency.csv"
    out = {}
    if not csv_path.exists():
        return out
    import csv as csv_mod
    with open(csv_path, newline="") as fh:
        for row in csv_mod.DictReader(fh):
            try:
                setup = row["setup"]
                scenario_full = row["scenario"] + (row["suffix"] or "")
                run = int(row["run"])
                mean_ms = float(row["handshake_mean_ms"]) if row["handshake_mean_ms"] not in ("", "n/a") else None
                out[(setup, scenario_full, run)] = mean_ms
            except (KeyError, ValueError):
                continue
    return out


def load_runs(results_dir: Path):
    """Zwraca dict: (setup, scenario_full) -> list of metric dicts (jeden per run)."""
    groups = defaultdict(list)
    skipped = []
    handshake_lookup = load_handshake_csv(results_dir)

    for f in sorted(results_dir.glob("summary_*.json")):
        m = FNAME_RE.match(f.name)
        if not m:
            skipped.append(f.name)
            continue
        setup = m.group("setup")
        scenario_full = m.group("scenario") + (m.group("suffix") or "")
        run = int(m.group("run"))
        try:
            data = json.loads(f.read_text())
        except Exception as e:
            print(f"UWAGA: nie mozna sparsowac {f.name}: {e}", file=sys.stderr)
            continue

        metrics = data.get("metrics", {})
        rps = metrics.get("http_reqs", {}).get("values", {}).get("rate")
        avg = metrics.get("http_req_duration", {}).get("values", {}).get("avg")
        p95 = metrics.get("http_req_duration", {}).get("values", {}).get("p(95)")
        success = metrics.get("success_rate", {}).get("values", {}).get("rate")

        if rps is None or avg is None:
            print(f"UWAGA: brak http_reqs/http_req_duration w {f.name}, pomijam", file=sys.stderr)
            continue

        # Realny sredni czas TLS handshake z histogramu Envoy (delta sum/count
        # w oknie tego runu), NIE z k6 - k6 nie widzi TLS w architekturze
        # sidecara (patrz komentarz przy load_handshake_csv). Brak wpisu w
        # CSV (np. dla starych wynikow albo gdy count_delta=0) -> None.
        tls_hs = handshake_lookup.get((setup, scenario_full, run))

        groups[(setup, scenario_full)].append({
            "run": run,
            "file": f.name,
            "rps": rps,
            "avg_ms": avg,
            "p95_ms": p95,
            "success_rate": success,
            "tls_hs_ms": tls_hs,
            "tls_hs_p95_ms": None,
        })

    if skipped:
        print(f"Info: {len(skipped)} plikow nie pasowalo do wzorca nazwy "
              f"(pewnie stare wyniki bez run{{N}}) - pomijam je: {skipped[:5]}"
              f"{' ...' if len(skipped) > 5 else ''}", file=sys.stderr)

    return groups


def bootstrap_ci(values, n_boot=5000, ci=0.95, seed=42):
    import random
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


def detect_outliers(values, z_thresh=2.0):
    if len(values) < 3:
        return []
    mean = statistics.fmean(values)
    sd = statistics.pstdev(values)
    if sd == 0:
        return []
    return [i for i, v in enumerate(values) if abs(v - mean) / sd > z_thresh]


def mann_whitney_u(a, b):
    """Prosta implementacja Mann-Whitney U (dwustronna, bez korekty ciaglosci),
    bez zaleznosci od scipy. Zwraca (U, przyblizone p przez normalna aproksymacje).
    Dla n<8 na grupe wynik traktuj jako orientacyjny, nie twardy."""
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
    U1 = rank_a - n1 * (n1 + 1) / 2
    U2 = n1 * n2 - U1
    U = min(U1, U2)
    mu = n1 * n2 / 2
    sigma = ((n1 * n2 * (n1 + n2 + 1)) / 12) ** 0.5
    if sigma == 0:
        return U, 1.0
    z = (U - mu) / sigma
    # przyblizenie dwustronnej wartosci p przez dystrybuante normalna
    from math import erf, sqrt
    p = 2 * (1 - 0.5 * (1 + erf(abs(z) / sqrt(2))))
    return U, min(p, 1.0)


def summarize(groups, baseline_setup):
    scenarios = sorted({sc for (_, sc) in groups})
    setups = sorted({s for (s, _) in groups})

    for scenario in scenarios:
        print("=" * 100)
        print(f"SCENARIUSZ: {scenario}")
        print("=" * 100)

        baseline_key = (baseline_setup, scenario)
        baseline_runs = groups.get(baseline_key, [])
        baseline_rps = [r["rps"] for r in baseline_runs]

        header = f"{'setup':<24}{'n':>3}{'RPS mean':>12}{'RPS CI95':>22}{'CV%':>7}{'avg_ms mean':>14}{'p95_ms mean':>14}{'TLS_hs mean(ms)':>18}{'vs baseline':>28}"
        print(header)
        print("-" * len(header))

        is_handshake_scenario = scenario.startswith("handshake")
        baseline_metric_vals = (
            [r["tls_hs_ms"] for r in baseline_runs if r["tls_hs_ms"] is not None]
            if is_handshake_scenario else baseline_rps
        )

        for setup in setups:
            key = (setup, scenario)
            runs = groups.get(key, [])
            if not runs:
                continue
            rps_vals = [r["rps"] for r in runs]
            avg_vals = [r["avg_ms"] for r in runs]
            p95_vals = [r["p95_ms"] for r in runs if r["p95_ms"] is not None]
            tls_hs_vals = [r["tls_hs_ms"] for r in runs if r["tls_hs_ms"] is not None]
            n = len(runs)

            mean_rps = statistics.fmean(rps_vals)
            mean_avg = statistics.fmean(avg_vals)
            mean_p95 = statistics.fmean(p95_vals) if p95_vals else float("nan")
            mean_tls_hs = statistics.fmean(tls_hs_vals) if tls_hs_vals else float("nan")
            sd_rps = statistics.pstdev(rps_vals) if n > 1 else 0.0
            cv = (sd_rps / mean_rps * 100) if mean_rps else 0.0

            if n >= 2:
                lo, hi = bootstrap_ci(rps_vals)
                ci_str = f"[{lo:.1f}, {hi:.1f}]"
            else:
                ci_str = "n/a (n=1!)"

            # Dla scenariusza handshake porownujemy TLS_hs_ms (bo RPS jest
            # sztucznie ograniczony przez constant-arrival-rate i nie mowi
            # nic o koszcie handshake'u), dla reszty scenariuszy - RPS.
            compare_vals = tls_hs_vals if is_handshake_scenario else rps_vals
            compare_mean = mean_tls_hs if is_handshake_scenario else mean_rps

            if setup == baseline_setup:
                cmp_str = "-- (baseline) --"
            elif len(baseline_metric_vals) >= 2 and len(compare_vals) >= 2:
                _, p = mann_whitney_u(baseline_metric_vals, compare_vals)
                base_mean = statistics.fmean(baseline_metric_vals)
                pct = (compare_mean - base_mean) / base_mean * 100 if base_mean else float("nan")
                sig = "ISTOTNE" if p < 0.05 else "brak podstaw (szum)"
                metric_name = "TLS_hs" if is_handshake_scenario else "RPS"
                cmp_str = f"{metric_name} {pct:+.2f}% p={p:.3f} [{sig}]"
            else:
                cmp_str = "za malo probek (n<2)"

            cv_str = f"{cv:.1f}%"
            tls_hs_str = f"{mean_tls_hs:.3f}" if mean_tls_hs == mean_tls_hs else "n/a"  # NaN check
            print(f"{setup:<24}{n:>3}{mean_rps:>12.1f}{ci_str:>22}{cv_str:>7}{mean_avg:>14.2f}{mean_p95:>14.2f}{tls_hs_str:>18}  {cmp_str}")

            outliers = detect_outliers(rps_vals)
            if outliers:
                for oi in outliers:
                    r = runs[oi]
                    print(f"    !! OUTLIER: run={r['run']} plik={r['file']} RPS={r['rps']:.1f} "
                          f"(odstaje >{2.0}sigma od reszty tego setupu w tym scenariuszu)")

            if n < 3:
                print(f"    UWAGA: n={n} < 3 - za malo powtorzen zeby cokolwiek sensownie wnioskowac o tym setupie/scenariuszu.")

        print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results-dir", default="./04_results/Summary")
    ap.add_argument("--baseline", default="mtls1.3-default",
                     help="Nazwa setupu traktowanego jako punkt odniesienia do porownan")
    args = ap.parse_args()

    results_dir = Path(args.results_dir)
    if not results_dir.exists():
        print(f"BLAD: katalog {results_dir} nie istnieje", file=sys.stderr)
        sys.exit(1)

    groups = load_runs(results_dir)
    if not groups:
        print("BLAD: nie znaleziono ani jednego pasujacego pliku summary_*_run<N>_*.json.\n"
              "Ten skrypt wymaga wynikow z patched_run_all_test.sh (z wieloma powtorzeniami "
              "oznaczonymi 'runN' w nazwie pliku). Jesli masz stare wyniki bez powtorzen, "
              "ten skrypt nie ma z czego liczyc statystyki.", file=sys.stderr)
        sys.exit(1)

    summarize(groups, args.baseline)


if __name__ == "__main__":
    main()