#!/usr/bin/env python3
"""
stats_compare.py
(Wersja zoptymalizowana do natywnego formatu Markdown)
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

def load_handshake_csv(results_dir: Path):
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
            continue

        metrics = data.get("metrics", {})
        rps = metrics.get("http_reqs", {}).get("values", {}).get("rate")
        avg = metrics.get("http_req_duration", {}).get("values", {}).get("avg")
        p95 = metrics.get("http_req_duration", {}).get("values", {}).get("p(95)")
        success = metrics.get("success_rate", {}).get("values", {}).get("rate")

        if rps is None or avg is None:
            continue

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
    from math import erf, sqrt
    p = 2 * (1 - 0.5 * (1 + erf(abs(z) / sqrt(2))))
    return U, min(p, 1.0)

def summarize(groups, baseline_setup):
    scenarios = sorted({sc for (_, sc) in groups})
    setups = sorted({s for (s, _) in groups})

    for scenario in scenarios:
        print(f"\n### SCENARIUSZ: `{scenario}`\n")
        
        baseline_key = (baseline_setup, scenario)
        baseline_runs = groups.get(baseline_key, [])
        baseline_rps = [r["rps"] for r in baseline_runs]

        print("| Setup | n | RPS mean | RPS CI95 | CV% | avg_ms mean | p95_ms mean | TLS_hs mean(ms) | vs baseline |")
        print("|---|---|---|---|---|---|---|---|---|")

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

            compare_vals = tls_hs_vals if is_handshake_scenario else rps_vals
            compare_mean = mean_tls_hs if is_handshake_scenario else mean_rps

            if setup == baseline_setup:
                cmp_str = "**-- (baseline) --**"
            elif len(baseline_metric_vals) >= 2 and len(compare_vals) >= 2:
                _, p = mann_whitney_u(baseline_metric_vals, compare_vals)
                base_mean = statistics.fmean(baseline_metric_vals)
                pct = (compare_mean - base_mean) / base_mean * 100 if base_mean else float("nan")
                sig = "**ISTOTNE**" if p < 0.05 else "szum statystyczny"
                metric_name = "TLS_hs" if is_handshake_scenario else "RPS"
                cmp_str = f"{metric_name} {pct:+.2f}% (p={p:.3f}) [{sig}]"
            else:
                cmp_str = "za malo probek (n<2)"

            cv_str = f"{cv:.1f}%"
            tls_hs_str = f"{mean_tls_hs:.3f}" if mean_tls_hs == mean_tls_hs else "n/a"
            
            print(f"| **{setup}** | {n} | {mean_rps:.1f} | {ci_str} | {cv_str} | {mean_avg:.2f} | {mean_p95:.2f} | {tls_hs_str} | {cmp_str} |")

        outliers_found = False
        for setup in setups:
            key = (setup, scenario)
            runs = groups.get(key, [])
            if not runs: continue
            rps_vals = [r["rps"] for r in runs]
            outliers = detect_outliers(rps_vals)
            if outliers:
                if not outliers_found:
                    print("\n")
                    outliers_found = True
                for oi in outliers:
                    r = runs[oi]
                    print(f"> 🚨 **OUTLIER:** Setup `{setup}` run=`{r['run']}` RPS=`{r['rps']:.1f}` (odstaje >2.0σ od reszty)")
            if len(runs) < 3:
                if not outliers_found:
                    print("\n")
                    outliers_found = True
                print(f"> ⚠️ **UWAGA:** Setup `{setup}` ma n={len(runs)} < 3. Za mało powtórzeń do poprawnej oceny statystycznej.")
        print("\n---")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results-dir", default="./04_results/Summary")
    ap.add_argument("--baseline", default="mtls1.3-default")
    args = ap.parse_args()

    results_dir = Path(args.results_dir)
    groups = load_runs(results_dir)
    
    print(f"# Raport Statystyczny Porównania Wydajności mTLS\n")
    print(f"**Katalog wyników:** `{results_dir}`\n**Baseline:** `{args.baseline}`\n")
    
    summarize(groups, args.baseline)

if __name__ == "__main__":
    main()