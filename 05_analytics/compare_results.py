import os
import glob
import json
import re
import pandas as pd

SUMMARY_DIR = './04_results/Summary'
METRICS_DIR = './04_results/Metrics'
OUTPUT_REPORT = './04_results/comparison_report.md'

# Dodano 'plaintext' do listy sprawdzanych konfiguracji
SETUPS = ['plaintext', 'mtls1.3-default', 'mtls1.2-gcm', 'mtls1.2-chacha', 'mtls1.2-cbc', 'mtls1.3-postquantum']
SCENARIOS = ['baseline', 'baseline-nokeepalive', 'payload', 'payload-nokeepalive', 'stress']

def get_latest_timestamp():
    files = glob.glob(os.path.join(SUMMARY_DIR, 'summary_*.json'))
    if not files:
        return None
    
    timestamps = []
    for f in files:
        m = re.search(r'_(\d{8}_\d{6})\.json$', f)
        if m:
            timestamps.append(m.group(1))
            
    if not timestamps:
        return None
    return sorted(timestamps)[-1]

def safe_get(d, path, default=0.0):
    keys = path.split('.')
    curr = d
    for k in keys:
        if isinstance(curr, dict) and k in curr:
            curr = curr[k]
        else:
            return default
    return curr

def _to_naive_utc(ts):
    t = pd.to_datetime(ts)
    if t.tzinfo is not None:
        t = t.tz_convert('UTC').tz_localize(None)
    return t


def calculate_avg_metric(filepath, metric_type, container_name):
    if not os.path.exists(filepath):
        return 0.0
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = json.load(f)
        points = data.get(metric_type, [])

        window = data.get('window', {})
        w_start = _to_naive_utc(window['start']) if window.get('start') else None
        w_end = _to_naive_utc(window['end']) if window.get('end') else None

        vals = []
        for p in points:
            if p.get('container') != container_name:
                continue
            if w_start is not None and w_end is not None and 'timestamp' in p:
                ts = _to_naive_utc(p['timestamp'])
                if not (w_start <= ts <= w_end):
                    continue
            vals.append(p['value'])

        if vals:
            return sum(vals) / len(vals)
    except Exception as e:
        pass
    return 0.0


def load_cipher_delta(setup, timestamp):
    before_path = os.path.join(SUMMARY_DIR, f"cipher_stats_{setup}_before_{timestamp}.txt")
    after_path = os.path.join(SUMMARY_DIR, f"cipher_stats_{setup}_after_{timestamp}.txt")

    def parse(path):
        counts = {}
        if not os.path.exists(path):
            return counts
        with open(path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line or ':' not in line:
                    continue
                key, _, val = line.rpartition(':')
                try:
                    counts[key.strip()] = int(val.strip())
                except ValueError:
                    continue
        return counts

    before = parse(before_path)
    after = parse(after_path)
    delta = {}
    for k, v in after.items():
        d = v - before.get(k, 0)
        if d > 0:
            delta[k] = d
    return delta

def generate_report():
    timestamp = get_latest_timestamp()
    if not timestamp:
        print("No test results found in Summary directory.")
        return

    print(f"Generating comparison report for timestamp: {timestamp}")
    
    report = []
    report.append(f"# Performance Comparison Report")
    report.append(f"Generated for test run: `{timestamp}`\n")
    report.append("This report compares the performance of different mutual TLS configurations in Istio:\n")
    report.append("- **Plaintext**: Zwykly ruch HTTP (brak mTLS)")
    report.append("- **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)")
    report.append("- **mTLS 1.2 (AES-GCM)**: ECDHE-ECDSA-AES128-GCM-SHA256")
    report.append("- **mTLS 1.2 (ChaCha20)**: ECDHE-ECDSA-CHACHA20-POLY1305-SHA256")
    report.append("- **mTLS 1.2 (AES-CBC)**: ECDHE-ECDSA-AES128-SHA256 (CBC mode)\n")
    report.append("- **mTLS 1.3 (Post-Quantum)**: X25519MLKEM768 (Hybrid Kyber Key Exchange)\n")

    report.append("## TLS Verification (live sidecar stats)\n")
    any_proof_found = False
    for setup in SETUPS:
        if setup == "plaintext":
            continue
        delta = load_cipher_delta(setup, timestamp)
        if not delta:
            report.append(f"- **{setup}**: Brak nowych handshake'ów lub brakuje zrzutu /stats (test mógł zostać przerwany skrótem ^C).")
            continue
        any_proof_found = True
        parts = ", ".join(f"`{k.split('.')[-1] if '.' in k else k}`={v}" for k, v in sorted(delta.items()))
        report.append(f"- **{setup}**: {parts}")
    if not any_proof_found:
        report.append("\n*No cipher verification data found at all.*")
    report.append("\n")

    for scenario in SCENARIOS:
        report.append(f"## Scenario: {scenario.upper()}")
        
        headers = [
            "Setup", "RPS", "RPS Diff", 
            "Latency Avg (ms)", "Latency Diff", 
            "Latency P95 (ms)", "TLS Handshakes (rate/s)", 
            "Proxy CPU (m)", "App CPU (m)", "Proxy Mem (MB)"
        ]
        
        rows = []
        baseline_data = {}
        
        for setup in SETUPS:
            # Rozwiązywanie plików z patternem _run*_ obsługującym strukturę z run_all_test.sh
            search_pattern = os.path.join(SUMMARY_DIR, f"summary_{setup}_{scenario}_run*_{timestamp}.json")
            matching_files = glob.glob(search_pattern)
            
            if not matching_files:
                continue
                
            # Pobieramy pierwszy run do tabeli z podsumowaniem ogólnym
            summary_path = sorted(matching_files)[0]
            filename = os.path.basename(summary_path)
            metrics_filename = filename.replace('summary_', 'metrics_')
            metrics_path = os.path.join(METRICS_DIR, metrics_filename)
                
            try:
                with open(summary_path, 'r', encoding='utf-8') as f:
                    summary = json.load(f)
            except Exception as e:
                print(f"Error reading {summary_path}: {e}")
                continue
                
            metrics = summary.get('metrics', {})
            
            rps = safe_get(metrics, 'http_reqs.values.rate', 0.0)
            lat_avg = safe_get(metrics, 'http_req_duration.values.avg', 0.0)
            lat_p95 = safe_get(metrics, 'http_req_duration.values.p(95)', 0.0)
            handshake_rate = calculate_avg_metric(metrics_path, 'tls_handshake_rate', 'httpbin-proxy')
            
            proxy_cpu = calculate_avg_metric(metrics_path, 'cpu', 'httpbin-proxy')
            app_cpu = calculate_avg_metric(metrics_path, 'cpu', 'httpbin-app')
            proxy_mem = calculate_avg_metric(metrics_path, 'memory', 'httpbin-proxy')
            
            data = {
                'setup': setup,
                'rps': rps,
                'lat_avg': lat_avg,
                'lat_p95': lat_p95,
                'handshake_rate': handshake_rate,
                'proxy_cpu': proxy_cpu,
                'app_cpu': app_cpu,
                'proxy_mem': proxy_mem
            }
            
            if setup == 'plaintext':
                baseline_data = data
                
            rows.append(data)
            
        if not rows:
            report.append("*Brak danych dla tego scenariusza.*\n")
            continue
            
        table_header = "| " + " | ".join(headers) + " |"
        table_separator = "| " + " | ".join(["---"] * len(headers)) + " |"
        report.append(table_header)
        report.append(table_separator)
        
        for row in rows:
            setup = row['setup']
            
            rps_diff_str = "-"
            lat_diff_str = "-"
            
            if baseline_data and setup != 'plaintext':
                b_rps = baseline_data.get('rps', 0.0)
                b_lat = baseline_data.get('lat_avg', 0.0)
                
                if b_rps > 0:
                    diff = ((row['rps'] - b_rps) / b_rps) * 100
                    rps_diff_str = f"{diff:+.2f}%"
                if b_lat > 0:
                    diff = ((row['lat_avg'] - b_lat) / b_lat) * 100
                    lat_diff_str = f"{diff:+.2f}%"
            
            cells = [
                f"**{setup}**",
                f"{row['rps']:.2f}",
                rps_diff_str,
                f"{row['lat_avg']:.3f}",
                lat_diff_str,
                f"{row['lat_p95']:.3f}",
                f"{row['handshake_rate']:.2f}",
                f"{row['proxy_cpu']:.1f}",
                f"{row['app_cpu']:.1f}",
                f"{row['proxy_mem']:.1f}"
            ]
            report.append("| " + " | ".join(cells) + " |")
            
        report.append("\n")
        
    with open(OUTPUT_REPORT, 'w', encoding='utf-8') as f:
        f.write("\n".join(report))
    
    print(f"Report written to {OUTPUT_REPORT}")
    print("\n".join(report))

if __name__ == '__main__':
    generate_report()