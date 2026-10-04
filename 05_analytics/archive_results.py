import os
import re
import shutil

# Directories
RESULTS_DIR = './04_results'
CATEGORIES = ['Summary', 'RawLogs', 'Plots', 'Metrics']
ARCHIVE_DIR = os.path.join(RESULTS_DIR, 'Archive')

# Regex to match the timestamp format YYYYMMDD_HHMMSS
TIMESTAMP_REGEX = re.compile(r'(\d{8}_\d{6})')

def archive_old_results():
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    
    # Dictionary to group files by timestamp: {timestamp: [(category, filename, src_path)]}
    groups = {}
    
    for category in CATEGORIES:
        category_dir = os.path.join(RESULTS_DIR, category)
        if not os.path.exists(category_dir):
            continue
            
        for filename in os.listdir(category_dir):
            filepath = os.path.join(category_dir, filename)
            
            # Skip if it is a directory
            if os.path.isdir(filepath):
                continue
                
            match = TIMESTAMP_REGEX.search(filename)
            if match:
                timestamp = match.group(1)
                if timestamp not in groups:
                    groups[timestamp] = []
                groups[timestamp].append((category, filename, filepath))
                
    if not groups:
        print("No old result files found to archive.")
        return

    print(f"Found {len(groups)} historical run(s) to archive.")

    for timestamp, files in groups.items():
        run_archive_dir = os.path.join(ARCHIVE_DIR, f"run_{timestamp}")
        print(f"Archiving run {timestamp} into {run_archive_dir}...")
        
        for category, filename, src_path in files:
            # Create category folder within this run's archive
            dest_category_dir = os.path.join(run_archive_dir, category)
            os.makedirs(dest_category_dir, exist_ok=True)
            
            dest_path = os.path.join(dest_category_dir, filename)
            
            try:
                shutil.move(src_path, dest_path)
                # If there are empty parent directories, we leave them
            except Exception as e:
                print(f"Error moving {filename}: {e}")
                
    print("Archiving completed successfully.")

if __name__ == '__main__':
    archive_old_results()
