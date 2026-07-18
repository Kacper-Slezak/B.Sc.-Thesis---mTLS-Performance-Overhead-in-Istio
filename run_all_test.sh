#!/bin/bash
set -e

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "Archiving previous test results if they exist..."
python3 ./05_analitics/archive_results.py || echo "Warning: Archiving failed, proceeding anyway."

echo "Creating result directories..."
mkdir -p ./04_results/Summary
mkdir -p ./04_results/RawLogs
mkdir -p ./04_results/Plots
mkdir -p ./04_results/Metrics
mkdir -p ./04_results/Archive

K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
echo "Detected K6 pod: $K6_POD"

# ==========================================
# PORT-FORWARDING PORT SETUP
# ==========================================
echo "Starting port-forward to Prometheus in the background (localhost:9090)..."
pkill -f "port-forward svc/prometheus" || true
kubectl port-forward -n istio-system svc/prometheus 9090:9090 > /dev/null 2>&1 &
PROM_PF_PID=$!

echo "Starting port-forward to Grafana in the background (localhost:3000)..."
pkill -f "port-forward svc/grafana" || true
kubectl port-forward -n istio-system svc/grafana 3000:3000 > /dev/null 2>&1 &
GRAFANA_PF_PID=$!

echo "Waiting 5 seconds for port-forwards to stabilize..."
sleep 5

# Function to run a specific test profile
run_test_profile() {
  local SETUP_NAME=$1
  local TEST_TYPE=$2
  local DISABLE_KEEP_ALIVE=${3:-"false"}
  
  local FILE_SUFFIX=""
  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    FILE_SUFFIX="-nokeepalive"
  fi
  local FILE_PREFIX="${SETUP_NAME}_${TEST_TYPE}${FILE_SUFFIX}_${TIMESTAMP}"

  echo "========================================================================"
  echo "Starting test profile: [${TEST_TYPE}]"
  echo "Keep-Alive: $(( [ "$DISABLE_KEEP_ALIVE" = "true" ] && echo "OFF (Connection: close)" ) || echo "ON (Keep-Alive)" )"
  echo "Setup: [${SETUP_NAME}]"
  echo "========================================================================"
  
  # Capture START_TIME in UTC
  local START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  cat ./03_test_scripts/main_k6_scenarios.js | kubectl exec -i $K6_POD -c k6 -- k6 run -e TEST_TYPE=${TEST_TYPE} -e DISABLE_KEEP_ALIVE=${DISABLE_KEEP_ALIVE} --out json=/tmp/raw.json -
  
  # Capture END_TIME in UTC
  local END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  echo "Downloading results for ${FILE_PREFIX}..."
  # Use gzip streaming via kubectl exec instead of kubectl cp.
  # This avoids EOF / timeout errors on large files and speeds up downloads dramatically.
  kubectl exec $K6_POD -c k6 -- gzip -c /tmp/raw.json > ./04_results/RawLogs/raw_${FILE_PREFIX}.json.gz
  gzip -d ./04_results/RawLogs/raw_${FILE_PREFIX}.json.gz
  
  # Stream summary.json to avoid kubectl cp issues
  kubectl exec $K6_POD -c k6 -- cat /tmp/summary.json > ./04_results/Summary/summary_${FILE_PREFIX}.json
  
  echo "Fetching metrics from Prometheus and generating plots..."
  python3 ./05_analitics/fetch_and_plot.py --start "$START_TIME" --end "$END_TIME" --setup "$SETUP_NAME" --test-type "$TEST_TYPE" --prefix "$FILE_PREFIX" || echo "Warning: Failed to fetch metrics or plot them."
  
  echo "Completed: ${FILE_PREFIX}"
  echo "----------------------------------------"
  sleep 5
}

# ==========================================
# SETUP 1: mTLS 1.3 (Istio Default)
# ==========================================
echo "=== BEGIN SETUP 1: mTLS 1.3 (Default) ==="
# Remove any existing EnvoyFilters to ensure default Istio behavior
kubectl delete envoyfilter --all -n default || true
echo "Waiting 10s for default configuration propagation..."
sleep 10

# Test with Keep-Alive ON
run_test_profile "mtls1.3-default" "baseline" "false"
run_test_profile "mtls1.3-default" "payload" "false"
run_test_profile "mtls1.3-default" "stress" "false"

# Test with Keep-Alive OFF (forces TLS handshake on every request to see 1-RTT vs 2-RTT difference)
run_test_profile "mtls1.3-default" "baseline" "true"
run_test_profile "mtls1.3-default" "payload" "true"


# ==========================================
# SETUP 2: mTLS 1.2 with AES-GCM
# ==========================================
echo "=== BEGIN SETUP 2: mTLS 1.2 (AES-GCM) ==="
kubectl delete envoyfilter --all -n default || true
kubectl apply -f ./02_manifests/envoyfilter_gcm.yaml

echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
sleep 15
kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-gcm_${TIMESTAMP}.yaml

# Test with Keep-Alive ON
run_test_profile "mtls1.2-gcm" "baseline" "false"
run_test_profile "mtls1.2-gcm" "payload" "false"
run_test_profile "mtls1.2-gcm" "stress" "false"

# Test with Keep-Alive OFF
run_test_profile "mtls1.2-gcm" "baseline" "true"
run_test_profile "mtls1.2-gcm" "payload" "true"


# ==========================================
# SETUP 3: mTLS 1.2 with ChaCha20
# ==========================================
echo "=== BEGIN SETUP 3: mTLS 1.2 (ChaCha20) ==="
kubectl delete envoyfilter --all -n default || true
kubectl apply -f ./02_manifests/envoyfilter_chacha.yaml

echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
sleep 15
kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-chacha_${TIMESTAMP}.yaml

# Test with Keep-Alive ON
run_test_profile "mtls1.2-chacha" "baseline" "false"
run_test_profile "mtls1.2-chacha" "payload" "false"
run_test_profile "mtls1.2-chacha" "stress" "false"

# Test with Keep-Alive OFF
run_test_profile "mtls1.2-chacha" "baseline" "true"
run_test_profile "mtls1.2-chacha" "payload" "true"


# ==========================================
# SETUP 4: mTLS 1.2 with AES-CBC
# ==========================================
echo "=== BEGIN SETUP 4: mTLS 1.2 (AES-CBC) ==="
kubectl delete envoyfilter --all -n default || true
kubectl apply -f ./02_manifests/envoyfilter_cbc.yaml

echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
sleep 15
kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-cbc_${TIMESTAMP}.yaml

# Test with Keep-Alive ON
run_test_profile "mtls1.2-cbc" "baseline" "false"
run_test_profile "mtls1.2-cbc" "payload" "false"
run_test_profile "mtls1.2-cbc" "stress" "false"

# Test with Keep-Alive OFF
run_test_profile "mtls1.2-cbc" "baseline" "true"
run_test_profile "mtls1.2-cbc" "payload" "true"


# ==========================================
# CLEANUP
# ==========================================
echo "Cleaning up port-forwards..."
kill $PROM_PF_PID || true
kill $GRAFANA_PF_PID || true

echo "=== ALL TESTS COMPLETED SUCCESSFULLY ==="