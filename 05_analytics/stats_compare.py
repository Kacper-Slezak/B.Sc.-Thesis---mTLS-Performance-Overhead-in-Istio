#!/usr/bin/env python3
"""
stats_compare.py
================
Generates a statistical comparison report evaluating mTLS configuration
performance (RPS, latency, proxy CPU, RAM) against a baseline setup,
and verifies cipher/curve telemetry counter increments from Envoy admin stats.

Implemented using only standard library modules to keep all calculations
transparent and reproducible.
"""

import argparse
import json
import random
import re
import statistics
from collections import defaultdict
from itertools import combinations
from math import comb, erf, sqrt
from pathlib import Path


# Summary file name regex: summary_{setup}_{scenario}[-nokeepalive]_run{N}_{TIMESTAMP}.json
FNAME_RE = re.compile(
    r"^summary_(?P<setup>.+?)_(?P<scenario>baseline|payload|stress|handshake)"
    r"(?P<suffix>-nokeepalive)?_run(?P<run>\d+)_(?P<timestamp>\d{8}_\d{6})\.json$"
)

PROXY_CONTAINER = "httpbin-proxy"
APP_CONTAINER = "httpbin-app"

# Expected substrings in Envoy stats cipher/curve counters for each setup
CIPHER_EXPECTATIONS = {
    "mtls1.2-gcm":         {"cipher_contains": "AES128-GCM"},
    "mtls1.2-gcm256":      {"cipher_contains": "AES256-GCM"},
    "mtls1.2-chacha":      {"cipher_contains": "CHACHA20"},
    "mtls1.2-cbc":         {"cipher_contains": "AES128-SHA256"},
    "mtls1.2-ccm":         {"cipher_contains": "CCM"},
    "mtls1.3-postquantum": {"curve_contains": "MLKEM"},
}


# ==============================================================================
# Statistical utility functions
# ==============================================================================

def bootstrap_ci(values, n_boot=5000, ci=0.95, seed=42):
    """Computes a 95% bootstrap confidence interval for the sample mean."""
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


def _rank_array(values):
    """Assigns ranks with average ranks on ties."""
    order = sorted(range(len(values)), key=lambda i: values[i])
    ranks = [0.0] * len(values)
    i = 0
    n = len(values)
    while i < n:
        j = i
        while j < n and values[order[j]] == values[order[i]]:
            j += 1
        avg_rank = (i + 1 + j) / 2
        for k in range(i, j):
            ranks[order[k]] = avg_rank
        i = j
    return ranks


def mann_whitney_u(a, b, exact_limit=100_000):
    """Two-sided Mann-Whitney U test with exact permutation p-value for small n."""
    n1, n2 = len(a), len(b)
    n = n1 + n2
    combined = list(a) + list(b)
    ranks = _rank_array(combined)
    rank_sum_a = sum(ranks[:n1])

    u1 = rank_sum_a - n1 * (n1 + 1) / 2
    u2 = n1 * n2 - u1
    u = min(u1, u2)

    total_combos = comb(n, n1)

    if total_combos <= exact_limit:
        mu = n1 * (n + 1) / 2
        observed_extremity = abs(rank_sum_a - mu)
        extreme_count = 0
        for combo_idx in combinations(range(n), n1):
            s = sum(ranks[i] for i in combo_idx)
            if abs(s - mu) >= observed_extremity - 1e-9:
                extreme_count += 1
        p = extreme_count / total_combos
        return u, min(p, 1.0)

    # Asymptotic normal approximation fallback for large n
    mu = n1 * n2 / 2
    sigma = ((n1 * n2 * (n1 + n2 + 1)) / 12) ** 0.5
    if sigma == 0:
        return u, 1.0
    z = (u - mu) / sigma
    p = 2 * (1 - 0.5 * (1 + erf(abs(z) / sqrt(2))))
    return u, min(p, 1.0)


def detect_outliers(values, z_thresh=2.0):
    """Detects sample indices exceeding z_thresh standard deviations."""
    if len(values) < 3:
        return []
    mean = statistics.fmean(values)
    sd = statistics.pstdev(values)
    if sd == 0:
        return []
    return [i for i, v in enumerate(values) if abs(v - mean) / sd > z_thresh]


# ==============================================================================
# Loading and parsing benchmark summaries
# ==============================================================================

def _parse_ts(ts: str):
    """Parses timestamp string to datetime object."""
    ts = ts.strip()
    if ts.endswith("Z"):
        ts = ts[:-1]
    ts = ts.replace("T", " ")
    from datetime import datetime
    return datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")


def read_container_metric(metrics_path: Path, metric_type: str, container: str):
    """Calculates mean metric value for container within test window."""
    if not metrics_path.exists():
        return None
    try:
        data = json.loads(metrics_path.read_text(encoding="utf-8"))
    except Exception:
        return None

    points = data.get(metric_type, [])
    window = data.get("window", {})
    w_start_raw = window.get("start")
    w_end_raw = window.get("end")
    w_start = _parse_ts(w_start_raw) if w_start_raw else None
    w_end = _parse_ts(w_end_raw) if w_end_raw else None

    vals = []
    for p in points:
        if p.get("container") != container:
            continue
        ts_raw = p.get("timestamp")
        if w_start is not None and w_end is not None and ts_raw:
            try:
                ts = _parse_ts(ts_raw)
            except ValueError:
                continue
            if not (w_start <= ts <= w_end):
                continue
        vals.append(p["value"])

    if not vals:
        return None
    return statistics.fmean(vals)


def load_runs(results_dir: Path, metrics_dir: Path):
    """Loads all summary_*.json files grouped by (setup, scenario)."""
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
            print(f"# Warning: failed to load {f.name}: {e}")
            continue

        metrics = data.get("metrics", {})
        rps = metrics.get("http_reqs", {}).get("values", {}).get("rate")
        avg = metrics.get("http_req_duration", {}).get("values", {}).get("avg")
        p95 = metrics.get("http_req_duration", {}).get("values", {}).get("p(95)")
        success = metrics.get("success_rate", {}).get("values", {}).get("rate")

        if rps is None or avg is None:
            print(f"# Warning: {f.name} missing http_reqs/http_req_duration - skipping")
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
        print(f"# Info: skipped {len(skipped)} files not matching naming pattern (e.g. {skipped[0]!r})\n")

    return groups


# ==============================================================================
# Cipher and Curve Verification
# ==============================================================================

def parse_cipher_stats_file(path: Path):
    """Parses cipher stats file into a dictionary of counter values."""
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
    """Verifies counter delta between latest before/after cipher stats."""
    before_files = sorted(summary_dir.glob(f"cipher_stats_{setup}_before_*.txt"))
    if not before_files:
        return {"status": "no_data", "detail": "before file not found"}

    latest_before = before_files[-1]
    ts_match = re.search(r"_before_(.+)\.txt$", latest_before.name)
    ts = ts_match.group(1) if ts_match else None
    latest_after = summary_dir / f"cipher_stats_{setup}_after_{ts}.txt" if ts else None

    before = parse_cipher_stats_file(latest_before)
    after = parse_cipher_stats_file(latest_after) if latest_after and latest_after.exists() else {}

    if not after:
        return {"status": "no_data", "detail": f"after file missing for timestamp {ts}"}

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
    print("## TLS Negotiation Verification (Before/After Telemetry Evidence)\n")
    print("Verified from Envoy stats counters `ssl.ciphers.*` and `ssl.curves.*` "
          "captured via localhost:15000/stats. Counter increments confirm active negotiation.\n")
    print("| Setup | Expected | Increment Detected? | Status |")
    print("|---|---|---|---|")

    any_problem = False
    for setup, expectation in CIPHER_EXPECTATIONS.items():
        result = verify_cipher_setup(summary_dir, setup, expectation)

        if result["status"] == "no_data":
            print(f"| **{setup}** | - | - | [NO DATA] {result['detail']} |")
            any_problem = True
            continue

        checks = []
        ok = True
        if "cipher_ok" in result:
            checks.append(f"cipher contains `{result['cipher_expected']}`")
            ok = ok and result["cipher_ok"]
        if "curve_ok" in result:
            checks.append(f"curve contains `{result['curve_expected']}`")
            ok = ok and result["curve_ok"]

        status = "OK" if ok else "MISMATCH"
        if not ok:
            any_problem = True
        print(f"| **{setup}** | {', '.join(checks)} | "
              f"{'YES' if ok else 'NO'} | {status} |")

    if any_problem:
        print("\n> [WARN] At least one setup did not confirm expected TLS configuration "
              "in the most recent run. Check EnvoyFilter manifests and proxy logs.")
    print()


# ==============================================================================
# Performance Comparison Tables
# ==============================================================================

def comparison_metric_for(scenario: str):
    """Uses latency for fixed-rate handshake scenarios, RPS for throughput tests."""
    if scenario.startswith("handshake"):
        return "avg_ms"
    return "rps"


def fmt(value, decimals=2):
    if value is None or value != value:
        return "n/a"
    return f"{value:.{decimals}f}"


def print_scenario_table(groups, baseline_setup, scenario, sig_test_counter):
    print(f"### SCENARIO: `{scenario}`\n")

    metric_key = comparison_metric_for(scenario)
    metric_label = "avg_ms" if metric_key == "avg_ms" else "RPS"
    reason = ("Fixed arrival rate limits RPS, primary cost metric is latency (lower is better)."
              if metric_key == "avg_ms" else
              "Measures maximum sustained throughput (higher RPS is better).")
    print(f"*Comparison metric for this scenario: **{metric_label}** ({reason})*\n")

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
            ci_str = "n/a (n=1)"

        if setup == baseline_setup:
            cmp_str = "**-- (baseline) --**"
        elif len(baseline_vals) >= 2 and len(compare_vals) >= 2:
            _, p = mann_whitney_u(baseline_vals, compare_vals)
            base_mean = statistics.fmean(baseline_vals)
            pct = (mean_compare - base_mean) / base_mean * 100 if base_mean else float("nan")
            sig = "**SIGNIFICANT**" if p < 0.05 else "statistical noise"
            sig_test_counter[0] += 1
            cmp_str = f"{metric_label} {pct:+.2f}% (p={p:.3f}) [{sig}]"
        else:
            cmp_str = f"insufficient samples (need >=2 in both groups, got {len(compare_vals)})"

        print(f"| **{setup}** | {n} | {fmt(mean_rps, 1)} | {fmt(mean_avg)} | "
              f"{fmt(mean_p95)} | {ci_str} | {cv:.1f}% | {fmt(mean_cpu, 1)} | "
              f"{fmt(mean_mem, 1)} | {cmp_str} |")

    # Diagnostics and warnings
    for setup in setups:
        runs = groups.get((setup, scenario), [])
        if not runs:
            continue

        if len(timestamps_seen[setup]) > 1:
            print(f"\n> [WARN] Setup `{setup}` in scenario `{scenario}` combines "
                  f"data across {len(timestamps_seen[setup])} different test run timestamps: "
                  f"{', '.join(sorted(timestamps_seen[setup]))}.")

        metric_key_local = comparison_metric_for(scenario)
        vals_for_outliers = [r[metric_key_local] for r in runs if r[metric_key_local] is not None]
        outliers = detect_outliers(vals_for_outliers)
        for oi in outliers:
            r = runs[oi]
            print(f"\n> [WARN] Outlier detected: setup `{setup}` run `{r['run']}` "
                  f"{metric_key_local}={r[metric_key_local]:.2f} (>2.0 sigma deviation).")

        if len(runs) < 3:
            print(f"\n> [WARN] Setup `{setup}` has n={len(runs)} < 3 repetitions.")

    print("\n---\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--results-dir", default="./04_results/Summary")
    ap.add_argument("--metrics-dir", default="./04_results/Metrics")
    ap.add_argument("--baseline", default="plaintext")
    args = ap.parse_args()

    results_dir = Path(args.results_dir)
    metrics_dir = Path(args.metrics_dir)

    print("# Statistical Comparison Report of mTLS Performance\n")
    print(f"**Results directory:** `{results_dir}`  ")
    print(f"**CPU/RAM metrics directory:** `{metrics_dir}`  ")
    print(f"**Baseline:** `{args.baseline}`\n")

    print_tls_verification_section(results_dir)

    groups = load_runs(results_dir, metrics_dir)
    if not groups:
        print("No results found to analyze in specified directory.")
        return

    scenarios = sorted({sc for (_, sc) in groups})
    sig_test_counter = [0]
    for scenario in scenarios:
        print_scenario_table(groups, args.baseline, scenario, sig_test_counter)

    n_tests = sig_test_counter[0]
    if n_tests:
        print(f"\n*Evaluated {n_tests} Mann-Whitney U hypothesis tests across scenarios "
              f"at significance threshold alpha=0.05.*")


if __name__ == "__main__":
    main()