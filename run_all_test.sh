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

# ==========================================
# GRAFANA PANEL EXPORT (OPTIONAL)
# ==========================================
export GRAFANA_API_KEY="${GRAFANA_API_KEY:-}"
export GRAFANA_DASHBOARD_UID="${GRAFANA_DASHBOARD_UID:-}"
GRAFANA_PANEL_IDS=(2 4 6) 

capture_cipher_stats() {
  local SETUP_NAME=$1
  local SUFFIX=$2 
  local HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")
  
  echo "Capturing cipher stats for ${SETUP_NAME} (${SUFFIX})..."
  
  kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats \
    | grep -i "ssl.ciphers" \
    > "./04_results/Summary/cipher_stats_${SETUP_NAME}_${SUFFIX}_${TIMESTAMP}.txt" || true

  echo "--- Found ciphers for ${SETUP_NAME} ---"
  cat "./04_results/Summary/cipher_stats_${SETUP_NAME}_${SUFFIX}_${TIMESTAMP}.txt" || echo "No ciphers recorded yet."
  echo "---------------------------------------"
}

export_grafana_panels() {
  local FILE_PREFIX=$1
  local START_TIME_LOCAL=$2
  local END_TIME_LOCAL=$3

  if [ -z "$GRAFANA_API_KEY" ] || [ -z "$GRAFANA_DASHBOARD_UID" ]; then
    return
  fi

  local START_MS=$(( $(date -d "$START_TIME_LOCAL" +%s) * 1000 ))
  local END_MS=$(( $(date -d "$END_TIME_LOCAL" +%s) * 1000 ))

  for PANEL_ID in "${GRAFANA_PANEL_IDS[@]}"; do
    curl -s -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
      "http://localhost:3000/render/d-solo/${GRAFANA_DASHBOARD_UID}/dashboard?orgId=1&panelId=${PANEL_ID}&width=1000&height=500&from=${START_MS}&to=${END_MS}&tz=UTC" \
      -o "./04_results/Plots/grafana_${FILE_PREFIX}_panel${PANEL_ID}.png" \
      || echo "Warning: Grafana panel ${PANEL_ID} export failed for ${FILE_PREFIX}."
  done
}

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
  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    echo "Keep-Alive: OFF (Connection: close)"
  else
    echo "Keep-Alive: ON (Keep-Alive)"
  fi
  echo "Setup: [${SETUP_NAME}]"
  echo "========================================================================"
  
  local START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    echo "Applying DestinationRule to force real connection-per-request (no pooling)..."
    kubectl apply -f ./02_manifests/dr_nokeepalive.yaml
    echo "Waiting 10s for propagation to the client-side sidecar..."
    sleep 10
  fi

  cat ./03_test_scripts/main_k6_scenarios.js | kubectl exec -i $K6_POD -c k6 -- k6 run -e TEST_TYPE=${TEST_TYPE} -e DISABLE_KEEP_ALIVE=${DISABLE_KEEP_ALIVE} --out json=/tmp/raw.json -

  local END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    echo "Removing force-nokeepalive DestinationRule..."
    kubectl delete -f ./02_manifests/dr_nokeepalive.yaml || true
  fi
  
  echo "Downloading results for ${FILE_PREFIX}..."
  local DL_START=$(date +%s)
  kubectl exec $K6_POD -c k6 -- gzip -c /tmp/raw.json > ./04_results/RawLogs/raw_${FILE_PREFIX}.json.gz
  gzip -d ./04_results/RawLogs/raw_${FILE_PREFIX}.json.gz
  
  kubectl exec $K6_POD -c k6 -- cat /tmp/summary.json > ./04_results/Summary/summary_${FILE_PREFIX}.json
  local DL_END=$(date +%s)
  echo "Download step took $((DL_END - DL_START))s. Raw log size: $(du -h ./04_results/RawLogs/raw_${FILE_PREFIX}.json 2>/dev/null | cut -f1)"
  
  echo "Fetching metrics from Prometheus and generating plots..."
  local ANALYTICS_START=$(date +%s)
  python3 ./05_analitics/fetch_and_plot.py --start "$START_TIME" --end "$END_TIME" --setup "$SETUP_NAME" --test-type "$TEST_TYPE" --prefix "$FILE_PREFIX" || echo "Warning: Failed to fetch metrics or plot them."
  local ANALYTICS_END=$(date +%s)
  echo "Analytics step took $((ANALYTICS_END - ANALYTICS_START))s."

  export_grafana_panels "$FILE_PREFIX" "$START_TIME" "$END_TIME"
  
  echo "Completed: ${FILE_PREFIX}"
  echo "----------------------------------------"
  sleep 5
}

# Nowa funkcja rozgrzewająca środowisko i usuwająca efekt "Zimnego Startu"
run_warmup() {
  echo "--- WARM-UP RUN (15s) to fill caches and stabilize CPU ---"
  echo 'import http from "k6/http"; export default function() { http.get("http://httpbin:8000/get"); }' | \
  kubectl exec -i $K6_POD -c k6 -- k6 run --vus 10 --duration 15s - > /dev/null 2>&1 || true
  echo "Warm-up complete. Sleeping 10s before real tests..."
  sleep 10
}

# ==========================================
# SETUP FUNCTIONS
# ==========================================

setup_mtls1_3() {
  echo "=== BEGIN SETUP 1: mTLS 1.3 (Default) ==="
  kubectl delete envoyfilter --all -n default || true
  echo "Waiting 10s for default configuration propagation..."
  sleep 10
  
  run_warmup
  capture_cipher_stats "mtls1.3-default" "before"

  run_test_profile "mtls1.3-default" "baseline" "false"
  run_test_profile "mtls1.3-default" "payload" "false"
  run_test_profile "mtls1.3-default" "stress" "false"
  run_test_profile "mtls1.3-default" "baseline" "true"
  run_test_profile "mtls1.3-default" "payload" "true"
  
  capture_cipher_stats "mtls1.3-default" "after"
}

setup_mtls1_2_gcm() {
  echo "=== BEGIN SETUP 2: mTLS 1.2 (AES-GCM) ==="
  kubectl delete envoyfilter --all -n default || true
  kubectl apply -f ./02_manifests/envoyfilter_gcm.yaml

  echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
  sleep 15
  kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-gcm_${TIMESTAMP}.yaml
  
  run_warmup
  capture_cipher_stats "mtls1.2-gcm" "before"

  run_test_profile "mtls1.2-gcm" "baseline" "false"
  run_test_profile "mtls1.2-gcm" "payload" "false"
  run_test_profile "mtls1.2-gcm" "stress" "false"
  run_test_profile "mtls1.2-gcm" "baseline" "true"
  run_test_profile "mtls1.2-gcm" "payload" "true"
  
  capture_cipher_stats "mtls1.2-gcm" "after"
}

setup_mtls1_2_chacha() {
  echo "=== BEGIN SETUP 3: mTLS 1.2 (ChaCha20) ==="
  kubectl delete envoyfilter --all -n default || true
  kubectl apply -f ./02_manifests/envoyfilter_chacha.yaml

  echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
  sleep 15
  kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-chacha_${TIMESTAMP}.yaml
  
  run_warmup
  capture_cipher_stats "mtls1.2-chacha" "before"

  run_test_profile "mtls1.2-chacha" "baseline" "false"
  run_test_profile "mtls1.2-chacha" "payload" "false"
  run_test_profile "mtls1.2-chacha" "stress" "false"
  run_test_profile "mtls1.2-chacha" "baseline" "true"
  run_test_profile "mtls1.2-chacha" "payload" "true"
  
  capture_cipher_stats "mtls1.2-chacha" "after"
}

setup_mtls1_2_cbc() {
  echo "=== BEGIN SETUP 4: mTLS 1.2 (AES-CBC) ==="
  kubectl delete envoyfilter --all -n default || true
  kubectl apply -f ./02_manifests/envoyfilter_cbc.yaml

  echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
  sleep 15
  kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-cbc_${TIMESTAMP}.yaml
  
  run_warmup
  capture_cipher_stats "mtls1.2-cbc" "before"

  run_test_profile "mtls1.2-cbc" "baseline" "false"
  run_test_profile "mtls1.2-cbc" "payload" "false"
  run_test_profile "mtls1.2-cbc" "stress" "false"
  run_test_profile "mtls1.2-cbc" "baseline" "true"
  run_test_profile "mtls1.2-cbc" "payload" "true"
  
  capture_cipher_stats "mtls1.2-cbc" "after"
}

# ==========================================
# RANDOMIZED EXECUTION ENGINE
# ==========================================
SETUPS=("mtls1.3-default" "mtls1.2-gcm" "mtls1.2-chacha" "mtls1.2-cbc")

# Losowe tasowanie elementów tablicy przy użyciu shuf (lub awk/sort jeśli shuf zawiedzie)
SHUFFLED_SETUPS=($(printf "%s\n" "${SETUPS[@]}" | shuf))

echo "========================================================================"
echo "🎯 EXECUTION PLAN (Randomized to avoid systematic/thermal bias):"
for i in "${!SHUFFLED_SETUPS[@]}"; do
  echo "  $((i+1)). ${SHUFFLED_SETUPS[$i]}"
done
echo "========================================================================"
sleep 3

for SETUP in "${SHUFFLED_SETUPS[@]}"; do
  case $SETUP in
    "mtls1.3-default") setup_mtls1_3 ;;
    "mtls1.2-gcm")     setup_mtls1_2_gcm ;;
    "mtls1.2-chacha")  setup_mtls1_2_chacha ;;
    "mtls1.2-cbc")     setup_mtls1_2_cbc ;;
  esac
  
  echo "Cooling down for 60 seconds before the next setup to prevent thermal throttling..."
  sleep 60
done

# ==========================================
# CLEANUP
# ==========================================
echo "Cleaning up port-forwards..."
kill $PROM_PF_PID || true
kill $GRAFANA_PF_PID || true

echo "=== ALL TESTS COMPLETED SUCCESSFULLY ==="