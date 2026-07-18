import os
import glob
import json
import re

SUMMARY_DIR = './04_results/Summary'
METRICS_DIR = './04_results/Metrics'
OUTPUT_REPORT = './04_results/comparison_report.md'

SETUPS = ['mtls1.3-default', 'mtls1.2-gcm', 'mtls1.2-chacha', 'mtls1.2-cbc']
SCENARIOS = ['baseline', 'baseline-nokeepalive', 'payload', 'payload-nokeepalive', 'stress']

def get_latest_timestamp():
    files = glob.glob(os.path.join(SUMMARY_DIR, 'summary_*.json'))
    if not files:
        return None
    
    timestamps = []
    for f in files:
        # Match timestamp format: YYYYMMDD_HHMMSS
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

def calculate_avg_metric(filepath, metric_type, container_name):
    if not os.path.exists(filepath):
        return 0.0
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = json.load(f)
        points = data.get(metric_type, [])
        vals = [p['value'] for p in points if p.get('container') == container_name]
        if vals:
            return sum(vals) / len(vals)
    except Exception as e:
        pass
    return 0.0

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
    report.append("- **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)")
    report.append("- **mTLS 1.2 (AES-GCM)**: ECDHE-ECDSA-AES128-GCM-SHA256")
    report.append("- **mTLS 1.2 (ChaCha20)**: ECDHE-ECDSA-CHACHA20-POLY1305-SHA256")
    report.append("- **mTLS 1.2 (AES-CBC)**: ECDHE-ECDSA-AES128-SHA256 (CBC mode)\n")
    
    for scenario in SCENARIOS:
        report.append(f"## Scenario: {scenario.upper()}")
        
        # Build headers
        headers = [
            "Setup", "RPS", "RPS Diff", 
            "Latency Avg (ms)", "Latency Diff", 
            "Latency P95 (ms)", "Handshake Avg (ms)", 
            "Proxy CPU (m)", "App CPU (m)", "Proxy Mem (MB)"
        ]
        
        rows = []
        baseline_data = {}
        
        # Gather data
        for setup in SETUPS:
            summary_path = os.path.join(SUMMARY_DIR, f"summary_{setup}_{scenario}_{timestamp}.json")
            metrics_path = os.path.join(METRICS_DIR, f"metrics_{setup}_{scenario}_{timestamp}.json")
            
            if not os.path.exists(summary_path):
                continue
                
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
            handshake = safe_get(metrics, 'http_req_tls_handshaking.values.avg', 0.0)
            
            proxy_cpu = calculate_avg_metric(metrics_path, 'cpu', 'httpbin-proxy')
            app_cpu = calculate_avg_metric(metrics_path, 'cpu', 'httpbin-app')
            proxy_mem = calculate_avg_metric(metrics_path, 'memory', 'httpbin-proxy')
            
            data = {
                'setup': setup,
                'rps': rps,
                'lat_avg': lat_avg,
                'lat_p95': lat_p95,
                'handshake': handshake,
                'proxy_cpu': proxy_cpu,
                'app_cpu': app_cpu,
                'proxy_mem': proxy_mem
            }
            
            if setup == 'mtls1.3-default':
                baseline_data = data
                
            rows.append(data)
            
        if not rows:
            continue
            
        # Format table
        table_header = "| " + " | ".join(headers) + " |"
        table_separator = "| " + " | ".join(["---"] * len(headers)) + " |"
        report.append(table_header)
        report.append(table_separator)
        
        for row in rows:
            setup = row['setup']
            
            # Calculations compared to baseline
            rps_diff_str = "-"
            lat_diff_str = "-"
            
            if baseline_data and setup != 'mtls1.3-default':
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
                f"{row['handshake']:.3f}",
                f"{row['proxy_cpu']:.1f}",
                f"{row['app_cpu']:.1f}",
                f"{row['proxy_mem']:.1f}"
            ]
            report.append("| " + " | ".join(cells) + " |")
            
        report.append("\n")
        
    with open(OUTPUT_REPORT, 'w', encoding='utf-8') as f:
        f.write("\n".join(report))
    
    print(f"Report written to {OUTPUT_REPORT}")
    # Print the report to console
    print("\n".join(report))

if __name__ == '__main__':
    generate_report()
