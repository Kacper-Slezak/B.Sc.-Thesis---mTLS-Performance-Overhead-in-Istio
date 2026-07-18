#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Starting cluster configuration..."
./01_scripts/setup_cluster.sh

mkdir -p ./04_results/Archive

# ==========================================
# WAITING FOR ENVIRONMENT TO BE READY
# ==========================================
echo "--- Waiting for pods (k6 and httpbin) to be ready ---"
kubectl wait --for=condition=ready pod -l app=httpbin --timeout=120s
kubectl wait --for=condition=ready pod -l app=k6 --timeout=120s

# Retrieve the K6 pod name
K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
echo "Detected K6 pod: $K6_POD"

# ==========================================
# RUN ALL BENCHMARKS
# ==========================================
echo "--- Running all benchmarking scenarios (mTLS 1.3 vs 1.2 with different ciphers) ---"
./run_all_test.sh

echo "--- Generating performance comparison report ---"
python3 ./05_analitics/compare_results.py

# ==========================================
# GRAFANA VISUALIZATION
# ==========================================
echo "--- Launching Grafana ---"

pkill -f "port-forward svc/grafana" || true
kubectl port-forward svc/grafana 3000:3000 -n istio-system &

sleep 3

echo "Opening dashboard..."
if which xdg-open > /dev/null
then
  xdg-open "http://localhost:3000"
elif which open > /dev/null
then
  open "http://localhost:3000"
elif which start > /dev/null
then
  start "http://localhost:3000"
else
  echo "Please navigate manually to: http://localhost:3000"
fi

echo "Tests completed successfully! Clean up any EnvoyFilters to leave cluster in default state."
kubectl delete envoyfilter --all -n default || true