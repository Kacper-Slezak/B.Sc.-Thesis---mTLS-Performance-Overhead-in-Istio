import os
import glob
import json
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Configuration
RAW_LOGS_DIR = './04_results/RawLogs'
PLOTS_DIR = './04_results/Plots'

os.makedirs(PLOTS_DIR, exist_ok=True)

# Find all JSON files
log_files = glob.glob(os.path.join(RAW_LOGS_DIR, '*.json'))

if not log_files:
    print(f"No raw log files found in {RAW_LOGS_DIR}")
    exit()

sns.set_theme(style="whitegrid")

for filepath in log_files:
    filename = os.path.basename(filepath)
    print(f"Processing {filename}...")
    
    # Extract metadata from filename (Format: raw_SETUP_TESTTYPE_TIMESTAMP.json)
    # Removing extension and splitting by underscore
    name_parts = filename.replace('.json', '').split('_')
    
    # Fallback placeholders in case of unexpected filename structures
    setup_name = "Unknown_Setup"
    test_type = "Unknown_Test"
    
    if len(name_parts) >= 4:
        setup_name = name_parts[1]  # e.g., mtls1.2-chacha
        test_type = name_parts[2]   # e.g., payload
    
    data_points = []
    
    # Parse K6 raw JSON lines
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip(): 
                continue
            try:
                record = json.loads(line)
                if record.get('type') == 'Point' and record.get('metric') == 'http_req_duration':
                    data_points.append({
                        'timestamp': pd.to_datetime(record['data']['time']),
                        'duration_ms': record['data']['value']
                    })
            except json.JSONDecodeError:
                continue
    
    if not data_points:
        print(f"No http_req_duration data found in {filename}. Skipping.")
        continue

    df = pd.DataFrame(data_points)
    
    # Create side-by-side plots
    fig, axes = plt.subplots(1, 2, figsize=(16, 6))
    
    # Dynamically inject the cipher setup and test type into the chart title
    main_title = f"Cipher Setup: {setup_name.upper()} | Test Type: {test_type.upper()}"
    fig.suptitle(main_title, fontsize=16, fontweight='bold')

    # Scatter plot (Latency over time)
    sns.scatterplot(data=df, x='timestamp', y='duration_ms', alpha=0.4, ax=axes[0], color='#1f77b4')
    axes[0].set_title('Latency Over Time')
    axes[0].set_xlabel('Timestamp')
    axes[0].set_ylabel('Request Duration (ms)')
    axes[0].tick_params(axis='x', rotation=45)

    # Boxplot (Distribution of latency)
    sns.boxplot(y=df['duration_ms'], ax=axes[1], color='#42b9f5', showfliers=True)
    axes[1].set_title('Latency Distribution')
    axes[1].set_ylabel('Duration (ms)')

    plt.tight_layout()
    
    # Save the output file
    plot_filename = filename.replace('.json', '.png')
    plot_path = os.path.join(PLOTS_DIR, plot_filename)
    
    plt.savefig(plot_path, dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"Saved plot: {plot_path}")

print("All plots generated successfully.")