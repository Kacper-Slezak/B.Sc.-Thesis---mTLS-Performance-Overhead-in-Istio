import os
import argparse
import glob
import json
import urllib.request
import urllib.parse
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Query Prometheus API for range data
def query_prometheus_range(query, start_time, end_time, step='2s'):
    params = {
        'query': query,
        'start': start_time,
        'end': end_time,
        'step': step
    }
    url = f"http://localhost:9090/api/v1/query_range?{urllib.parse.urlencode(params)}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode('utf-8'))
            if data['status'] == 'success':
                return data['data']['result']
            else:
                print(f"Prometheus error: {data.get('error')}")
                return []
    except Exception as e:
        print(f"Could not reach Prometheus at {url}: {e}. Make sure port-forward is running.")
        return []

def result_to_df(result, label):
    rows = []
    for r in result:
        container = r['metric'].get('container', label)
        pod = r['metric'].get('pod', 'unknown')
        for val in r['values']:
            timestamp = pd.to_datetime(val[0], unit='s')
            value = float(val[1])
            rows.append({
                'timestamp': timestamp,
                'value': value,
                'container': container,
                'pod': pod,
                'label': f"{container} ({label})"
            })
    return pd.DataFrame(rows) if rows else pd.DataFrame(columns=['timestamp', 'value', 'container', 'pod', 'label'])

def main():
    parser = argparse.ArgumentParser(description="Fetch Prometheus metrics and plot them alongside K6 results.")
    parser.add_argument('--start', required=True, help="Start time in RFC3339 format (UTC)")
    parser.add_argument('--end', required=True, help="End time in RFC3339 format (UTC)")
    parser.add_argument('--setup', required=True, help="Setup name (e.g., mtls1.3-default)")
    parser.add_argument('--test-type', required=True, help="Test type (e.g., baseline, payload, stress)")
    parser.add_argument('--prefix', required=True, help="File prefix for saving results")
    args = parser.parse_args()

    # Create directories
    os.makedirs('./04_results/Plots', exist_ok=True)
    os.makedirs('./04_results/Metrics', exist_ok=True)

    print(f"Processing metrics for {args.prefix}...")
    print(f"Time Window (UTC): {args.start} to {args.end}")

    # Add a buffer of 15 seconds before and after the test to see base resource usage
    start_dt = (pd.to_datetime(args.start) - pd.Timedelta(seconds=15)).strftime("%Y-%m-%dT%H:%M:%SZ")
    end_dt = (pd.to_datetime(args.end) + pd.Timedelta(seconds=15)).strftime("%Y-%m-%dT%H:%M:%SZ")

    # 1. Fetch CPU Usage (millicores)
    # httpbin CPU queries
    q_httpbin_app_cpu = 'sum(rate(container_cpu_usage_seconds_total{namespace="default", container="httpbin", pod=~"httpbin-.*"}[15s])) * 1000'
    q_httpbin_proxy_cpu = 'sum(rate(container_cpu_usage_seconds_total{namespace="default", container="istio-proxy", pod=~"httpbin-.*"}[15s])) * 1000'
    # k6 CPU queries
    q_k6_app_cpu = 'sum(rate(container_cpu_usage_seconds_total{namespace="default", container="k6", pod=~"k6-deploy-.*"}[15s])) * 1000'
    q_k6_proxy_cpu = 'sum(rate(container_cpu_usage_seconds_total{namespace="default", container="istio-proxy", pod=~"k6-deploy-.*"}[15s])) * 1000'

    res_hb_app_cpu = query_prometheus_range(q_httpbin_app_cpu, start_dt, end_dt)
    res_hb_proxy_cpu = query_prometheus_range(q_httpbin_proxy_cpu, start_dt, end_dt)
    res_k6_app_cpu = query_prometheus_range(q_k6_app_cpu, start_dt, end_dt)
    res_k6_proxy_cpu = query_prometheus_range(q_k6_proxy_cpu, start_dt, end_dt)

    df_hb_app_cpu = result_to_df(res_hb_app_cpu, 'httpbin-app')
    df_hb_proxy_cpu = result_to_df(res_hb_proxy_cpu, 'httpbin-proxy')
    df_k6_app_cpu = result_to_df(res_k6_app_cpu, 'k6-app')
    df_k6_proxy_cpu = result_to_df(res_k6_proxy_cpu, 'k6-proxy')

    dfs_cpu = [df for df in [df_hb_app_cpu, df_hb_proxy_cpu, df_k6_app_cpu, df_k6_proxy_cpu] if not df.empty]
    df_cpu = pd.concat(dfs_cpu, ignore_index=True) if dfs_cpu else pd.DataFrame(columns=['timestamp', 'value', 'container', 'pod', 'label'])

    # 2. Fetch Memory Usage (MB)
    # httpbin Memory queries
    q_httpbin_app_mem = 'sum(container_memory_working_set_bytes{namespace="default", container="httpbin", pod=~"httpbin-.*"}) / 1024 / 1024'
    q_httpbin_proxy_mem = 'sum(container_memory_working_set_bytes{namespace="default", container="istio-proxy", pod=~"httpbin-.*"}) / 1024 / 1024'
    # k6 Memory queries
    q_k6_app_mem = 'sum(container_memory_working_set_bytes{namespace="default", container="k6", pod=~"k6-deploy-.*"}) / 1024 / 1024'
    q_k6_proxy_mem = 'sum(container_memory_working_set_bytes{namespace="default", container="istio-proxy", pod=~"k6-deploy-.*"}) / 1024 / 1024'

    res_hb_app_mem = query_prometheus_range(q_httpbin_app_mem, start_dt, end_dt)
    res_hb_proxy_mem = query_prometheus_range(q_httpbin_proxy_mem, start_dt, end_dt)
    res_k6_app_mem = query_prometheus_range(q_k6_app_mem, start_dt, end_dt)
    res_k6_proxy_mem = query_prometheus_range(q_k6_proxy_mem, start_dt, end_dt)

    df_hb_app_mem = result_to_df(res_hb_app_mem, 'httpbin-app')
    df_hb_proxy_mem = result_to_df(res_hb_proxy_mem, 'httpbin-proxy')
    df_k6_app_mem = result_to_df(res_k6_app_mem, 'k6-app')
    df_k6_proxy_mem = result_to_df(res_k6_proxy_mem, 'k6-proxy')

    dfs_mem = [df for df in [df_hb_app_mem, df_hb_proxy_mem, df_k6_app_mem, df_k6_proxy_mem] if not df.empty]
    df_mem = pd.concat(dfs_mem, ignore_index=True) if dfs_mem else pd.DataFrame(columns=['timestamp', 'value', 'container', 'pod', 'label'])

    # Save fetched metrics to file
    metrics_log_path = f"./04_results/Metrics/metrics_{args.prefix}.json"
    metrics_data = {
        'cpu': df_cpu.to_dict(orient='records') if not df_cpu.empty else [],
        'memory': df_mem.to_dict(orient='records') if not df_mem.empty else []
    }
    with open(metrics_log_path, 'w', encoding='utf-8') as f:
        json.dump(metrics_data, f, indent=2, default=str)
    print(f"Saved raw prometheus metrics to {metrics_log_path}")

    # 3. Read K6 Latency points
    k6_raw_path = f"./04_results/RawLogs/raw_{args.prefix}.json"
    k6_data_points = []
    if os.path.exists(k6_raw_path):
        with open(k6_raw_path, 'r', encoding='utf-8') as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                    if record.get('type') == 'Point' and record.get('metric') == 'http_req_duration':
                        k6_data_points.append({
                            'timestamp': pd.to_datetime(record['data']['time']),
                            'duration_ms': record['data']['value']
                        })
                except json.JSONDecodeError:
                    continue

    df_k6 = pd.DataFrame(k6_data_points) if k6_data_points else pd.DataFrame()

    # 4. Generate Plot
    sns.set_theme(style="whitegrid")
    
    # 2x2 grid
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    main_title = f"Profile: {args.setup.upper()} | Test: {args.test_type.upper()}\nTime Window: {args.start} to {args.end}"
    fig.suptitle(main_title, fontsize=16, fontweight='bold')

    # Panel 1: Latency Over Time
    if not df_k6.empty:
        sns.scatterplot(data=df_k6, x='timestamp', y='duration_ms', alpha=0.3, ax=axes[0, 0], color='#1f77b4', edgecolor=None)
        # Add rolling mean to show trends
        df_k6_sorted = df_k6.sort_values('timestamp')
        df_k6_sorted['rolling_mean'] = df_k6_sorted['duration_ms'].rolling(window=100, min_periods=10).mean()
        sns.lineplot(data=df_k6_sorted, x='timestamp', y='rolling_mean', color='darkblue', linewidth=2, label='Rolling Mean (100 req)', ax=axes[0, 0])
        axes[0, 0].set_title('Latency Over Time (K6)')
        axes[0, 0].set_xlabel('Time')
        axes[0, 0].set_ylabel('Duration (ms)')
        axes[0, 0].tick_params(axis='x', rotation=30)
    else:
        axes[0, 0].text(0.5, 0.5, "K6 Latency Data Not Found", ha='center', va='center', fontsize=12)
        axes[0, 0].set_title('Latency Over Time (K6)')

    # Panel 2: Latency Distribution
    if not df_k6.empty:
        sns.boxplot(y=df_k6['duration_ms'], ax=axes[0, 1], color='#42b9f5', showfliers=True)
        # Print metrics in the plot
        avg_lat = df_k6['duration_ms'].mean()
        p90_lat = df_k6['duration_ms'].quantile(0.90)
        p95_lat = df_k6['duration_ms'].quantile(0.95)
        textstr = '\n'.join((
            f'Avg: {avg_lat:.2f} ms',
            f'p90: {p90_lat:.2f} ms',
            f'p95: {p95_lat:.2f} ms'
        ))
        props = dict(boxstyle='round', facecolor='wheat', alpha=0.5)
        axes[0, 1].text(0.05, 0.95, textstr, transform=axes[0, 1].transAxes, fontsize=12,
                        verticalalignment='top', bbox=props)
        axes[0, 1].set_title('Latency Distribution (K6)')
        axes[0, 1].set_ylabel('Duration (ms)')
    else:
        axes[0, 1].text(0.5, 0.5, "K6 Latency Data Not Found", ha='center', va='center', fontsize=12)
        axes[0, 1].set_title('Latency Distribution (K6)')

    # Panel 3: CPU Usage Over Time
    if not df_cpu.empty:
        sns.lineplot(data=df_cpu, x='timestamp', y='value', hue='label', linewidth=2.5, ax=axes[1, 0])
        axes[1, 0].set_title('Container CPU Utilization (Prometheus)')
        axes[1, 0].set_xlabel('Time')
        axes[1, 0].set_ylabel('CPU Usage (millicores / m)')
        axes[1, 0].tick_params(axis='x', rotation=30)
        axes[1, 0].legend(title='Container')
    else:
        axes[1, 0].text(0.5, 0.5, "Prometheus CPU Metrics Not Found\n(Is Prometheus port-forward active?)", ha='center', va='center', fontsize=12)
        axes[1, 0].set_title('Container CPU Utilization (Prometheus)')

    # Panel 4: Memory Usage Over Time
    if not df_mem.empty:
        sns.lineplot(data=df_mem, x='timestamp', y='value', hue='label', linewidth=2.5, ax=axes[1, 1])
        axes[1, 1].set_title('Container Memory (Prometheus)')
        axes[1, 1].set_xlabel('Time')
        axes[1, 1].set_ylabel('Memory (MB)')
        axes[1, 1].tick_params(axis='x', rotation=30)
        axes[1, 1].legend(title='Container')
    else:
        axes[1, 1].text(0.5, 0.5, "Prometheus Memory Metrics Not Found\n(Is Prometheus port-forward active?)", ha='center', va='center', fontsize=12)
        axes[1, 1].set_title('Container Memory (Prometheus)')

    plt.tight_layout()
    
    plot_path = f"./04_results/Plots/plot_{args.prefix}.png"
    plt.savefig(plot_path, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Saved combined plot to {plot_path}")

if __name__ == '__main__':
    main()
