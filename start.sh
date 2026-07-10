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
# SCENARIO 1: mTLS 1.3 (Istio Default)
# ==========================================
echo "--- Running advanced scenario: mTLS 1.3 (Default) ---"

# Pass the script to the pod and save the result inside the container
cat ./03_test_scripts/main_k6_scenarios.js | kubectl exec -i $K6_POD -c k6 -- k6 run --out json=raw_result_main_mtls1_3.json -

# Copy the result from the pod to the local disk
echo "Downloading results to local disk..."
kubectl cp $K6_POD:raw_result_main_mtls1_3.json ./04_results/Archive/raw_result_main_mtls1_3.json -c k6

echo "Results for mTLS 1.3 saved."
sleep 5

# ==========================================
# SCENARIO 2: Force mTLS 1.2
# ==========================================
echo "--- Applying downgrade to mTLS 1.2 and selected Cipher Suite ---"

# Apply ONLY the correct Envoy configuration file
kubectl apply -f ./02_manifests/envoyfilter_downgrade_mtls_1_2.yaml

echo "Waiting for configuration propagation in Envoy proxy (15 seconds)..."
sleep 15

# ------------------------------------------
# mTLS 1.2 CONFIGURATION PROOF
# ------------------------------------------
echo "--- CONFIGURATION VERIFICATION (TEST PROOF) ---"
echo "Active EnvoyFilter forcing TLS 1.2:"
kubectl get envoyfilter -n istio-system -o yaml | grep -A 10 "tls_maximum_protocol_version" || echo "Warning: Explicit TLS version entry not found in configuration!"
echo "--------------------------------------------------"

echo "--- Running advanced scenario for mTLS 1.2 ---"
# Pass the script to the pod and save the result inside the container
cat ./03_test_scripts/main_k6_scenarios.js | kubectl exec -i $K6_POD -c k6 -- k6 run --out json=raw_result_main_mtls1_2_cipher.json -

# Copy the result from the pod to the local disk
echo "Downloading results to local disk..."
kubectl cp $K6_POD:raw_result_main_mtls1_2_cipher.json ./04_results/Archive/raw_result_main_mtls1_2_cipher.json -c k6

echo "Results for mTLS 1.2 saved."

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

echo "Tests completed successfully! Gather the generated JSON files for analysis."

echo "--- Saving configuration proof to file ---"
kubectl get envoyfilter force-downgrade-httpbin-server -n default -o yaml > ./04_results/Archive/envoy_filter_proof.yaml