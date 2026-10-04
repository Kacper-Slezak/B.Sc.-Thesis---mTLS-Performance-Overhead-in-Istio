import os
import glob
import json
import re
import argparse
import numpy as np
from scipy import stats
import pandas as pd

SUMMARY_DIR = './04_results/Summary'
METRICS_DIR = './04_results/Metrics'

SETUPS = ['mtls1.3-default', 'mtls1.2-gcm', 'mtls1.2-chacha', 'mtls1.2-cbc', 'mtls1.3-postquantum']
SCENARIOS = ['baseline', 'baseline-nokeepalive', 'payload', 'payload-nokeepalive', 'stress']

def _to_naive_utc(ts):
    t = pd.to_datetime(ts)
    if t.tzinfo is not None:
        t = t.tz_convert('UTC').tz_localize(None)
    return t

def calculate_avg_metric(filepath, metric_type, container_name):
    if not os.path.exists(filepath): return np.nan
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = json.load(f)
        points = data.get(metric_type, [])
        window = data.get('window', {})
        w_start = _to_naive_utc(window['start']) if window.get('start') else None
        w_end = _to_naive_utc(window['end']) if window.get('end') else None

        vals = []
        for p in points:
            if p.get('container') != container_name: continue
            if w_start and w_end and 'timestamp' in p:
                ts = _to_naive_utc(p['timestamp'])
                if not (w_start <= ts <= w_end): continue
            vals.append(p['value'])
        return np.mean(vals) if vals else np.nan
    except:
        return np.nan

def get_latest_timestamp():
    files = glob.glob(os.path.join(SUMMARY_DIR, 'summary_*.json'))
    timestamps = [re.search(r'_(\d{8}_\d{6})\.json$', f).group(1) for f in files if re.search(r'_(\d{8}_\d{6})\.json$', f)]
    return sorted(timestamps)[-1] if timestamps else None

def get_run_data(setup, scenario, timestamp):
    search_pattern = os.path.join(SUMMARY_DIR, f"summary_{setup}_{scenario}_run*_{timestamp}.json")
    files = glob.glob(search_pattern)
    
    rps_list, lat_list, cpu_list = [], [], []
    for summary_path in files:
        metrics_path = os.path.join(METRICS_DIR, os.path.basename(summary_path).replace('summary_', 'metrics_'))
        try:
            with open(summary_path, 'r', encoding='utf-8') as f:
                summary = json.load(f)
            
            metrics = summary.get('metrics', {})
            
            # Poprawne parsowanie zagniezdzonego JSONa z k6
            rps = metrics.get('http_reqs', {}).get('values', {}).get('rate', 0.0)
            lat = metrics.get('http_req_duration', {}).get('values', {}).get('avg', 0.0)
                
            cpu = calculate_avg_metric(metrics_path, 'cpu', 'httpbin-proxy')
            
            if rps > 0: rps_list.append(rps)
            if lat > 0: lat_list.append(lat)
            if not np.isnan(cpu) and cpu > 0: cpu_list.append(cpu)
        except Exception as e:
            continue
            
    return rps_list, lat_list, cpu_list

def stat_compare(base_vals, test_vals):
    if len(base_vals) < 2 or len(test_vals) < 2:
        return "N/A"
    
    base_mean = np.mean(base_vals)
    test_mean = np.mean(test_vals)
    diff_pct = ((test_mean - base_mean) / base_mean) * 100
    
    # Test T-Studenta dla dwóch prób niezależnych
    _, p_val = stats.ttest_ind(base_vals, test_vals, equal_var=False)
    
    sig = "**ISTOTNE**" if p_val < 0.05 else "szum"
    return f"{diff_pct:+.1f}% ({sig})"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--results-dir', default=SUMMARY_DIR)
    parser.add_argument('--baseline', default='plaintext')
    args = parser.parse_args()

    timestamp = get_latest_timestamp()
    if not timestamp:
        print("Brak wyników do analizy.")
        return

    print(f"# Pełny Raport Statystyczny (RPS, CPU, Latency)\n**Timestamp:** `{timestamp}`\n**Baseline:** `{args.baseline}`\n")
    
    for scenario in SCENARIOS:
        print(f"### SCENARIUSZ: `{scenario}`\n")
        print("| Setup | n | RPS mean | Proxy CPU (m) | Latency Avg (ms) | Δ RPS | Δ CPU | Δ Latency |")
        print("|---|---|---|---|---|---|---|---|")
        
        base_rps, base_lat, base_cpu = get_run_data(args.baseline, scenario, timestamp)
        
        for setup in SETUPS:
            rps, lat, cpu = get_run_data(setup, scenario, timestamp)
            n_runs = len(rps)
            
            if n_runs == 0:
                continue
                
            rps_mean = np.mean(rps)
            lat_mean = np.mean(lat)
            cpu_mean = np.mean(cpu) if cpu else 0.0
            
            if setup == args.baseline:
                print(f"| **{setup}** | {n_runs} | {rps_mean:.1f} | {cpu_mean:.1f} | {lat_mean:.2f} | - (baza) | - (baza) | - (baza) |")
            else:
                rps_cmp = stat_compare(base_rps, rps)
                lat_cmp = stat_compare(base_lat, lat)
                cpu_cmp = stat_compare(base_cpu, cpu)
                print(f"| **{setup}** | {n_runs} | {rps_mean:.1f} | {cpu_mean:.1f} | {lat_mean:.2f} | {rps_cmp} | {cpu_cmp} | {lat_cmp} |")
        print("\n---\n")

if __name__ == '__main__':
    main()