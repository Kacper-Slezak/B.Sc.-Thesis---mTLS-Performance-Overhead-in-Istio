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
# Automated screenshot export via Grafana's render API. This REQUIRES the
# grafana-image-renderer plugin to be installed on your Grafana instance --
# without it, the /render endpoint doesn't exist and these calls will just
# fail quietly (non-blocking, same as the other "|| echo Warning" steps below).
#
# To enable: set GRAFANA_API_KEY (a Grafana API key/service account token
# with Viewer role) and GRAFANA_DASHBOARD_UID (find it in the dashboard URL:
# .../d/<UID>/some-slug), and list the panel IDs you want exported below
# (hover a panel title -> "More" -> "Panel JSON", the "id" field).
export GRAFANA_API_KEY="${GRAFANA_API_KEY:-}"
export GRAFANA_DASHBOARD_UID="${GRAFANA_DASHBOARD_UID:-}"
GRAFANA_PANEL_IDS=(2 4 6)   # <-- adjust to your dashboard's real panel IDs

# Function to capture what Envoy ACTUALLY negotiated, straight from the live
# sidecar's own stats endpoint. This is the real proof-of-cipher, unlike
# `kubectl get envoyfilter -o yaml`, which only shows the CR was accepted by
# the API server -- not that the sidecar used it on live connections.
# Also captures ssl.session_reused: if this counter climbs a lot during the
# "-nokeepalive" runs, TLS session resumption is skipping the full asymmetric
# handshake even on fresh connections, which would flatten out any difference
# vs. the keep-alive scenario regardless of the DestinationRule being applied.
# Envoy admin stat names/prefixes can vary by version; if the grep below comes
# back empty, run the curl manually once and adjust the pattern.
capture_cipher_stats() {
  local SETUP_NAME=$1
  local SUFFIX=$2  # "before" or "after"
  local HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")
  
  echo "Capturing cipher stats for ${SETUP_NAME} (${SUFFIX})..."
  
  # Pobieramy statystyki i używamy "|| true", aby skrypt nie wywalił się, gdy grep nic nie znajdzie (np. faza "before")
  kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats \
    | grep -i "ssl.ciphers" \
    > "./04_results/Summary/cipher_stats_${SETUP_NAME}_${SUFFIX}_${TIMESTAMP}.txt" || true

  # Wyświetl na ekranie to, co znalazł skrypt (dla podglądu na żywo)
  echo "--- Found ciphers for ${SETUP_NAME} ---"
  cat "./04_results/Summary/cipher_stats_${SETUP_NAME}_${SUFFIX}_${TIMESTAMP}.txt" || echo "No ciphers recorded yet."
  echo "---------------------------------------"
}

# Function to export Grafana panels as PNGs for a given test window.
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
  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    echo "Keep-Alive: OFF (Connection: close)"
  else
    echo "Keep-Alive: ON (Keep-Alive)"
  fi
  echo "Setup: [${SETUP_NAME}]"
  echo "========================================================================"
  
  # Capture START_TIME in UTC
  local START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # dr_nokeepalive.yaml forces the CLIENT-side (source) Envoy to close the
  # upstream connection after every single request (maxRequestsPerConnection: 1)
  # and blocks HTTP/2 upgrade. Without this, k6's "Connection: close" header
  # only affects k6 <-> its OWN sidecar -- the sidecar-to-sidecar mTLS tunnel to
  # httpbin can still get pooled and reused by Envoy regardless, so the
  # "nokeepalive" scenario ends up silently identical to the keep-alive one.
  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    echo "Applying DestinationRule to force real connection-per-request (no pooling)..."
    kubectl apply -f ./02_manifests/dr_nokeepalive.yaml
    echo "Waiting 10s for propagation to the client-side sidecar..."
    sleep 10
  fi

  cat ./03_test_scripts/main_k6_scenarios.js | kubectl exec -i $K6_POD -c k6 -- k6 run -e TEST_TYPE=${TEST_TYPE} -e DISABLE_KEEP_ALIVE=${DISABLE_KEEP_ALIVE} --out json=/tmp/raw.json -

  # Capture END_TIME in UTC
  local END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    echo "Removing force-nokeepalive DestinationRule so it doesn't leak into the next (keep-alive) run..."
    kubectl delete -f ./02_manifests/dr_nokeepalive.yaml || true
  fi
  
  echo "Downloading results for ${FILE_PREFIX}..."
  local DL_START=$(date +%s)
  # Use gzip streaming via kubectl exec instead of kubectl cp.
  # This avoids EOF / timeout errors on large files and speeds up downloads dramatically.
  kubectl exec $K6_POD -c k6 -- gzip -c /tmp/raw.json > ./04_results/RawLogs/raw_${FILE_PREFIX}.json.gz
  gzip -d ./04_results/RawLogs/raw_${FILE_PREFIX}.json.gz
  
  # Stream summary.json to avoid kubectl cp issues
  kubectl exec $K6_POD -c k6 -- cat /tmp/summary.json > ./04_results/Summary/summary_${FILE_PREFIX}.json
  local DL_END=$(date +%s)
  echo "Download step took $((DL_END - DL_START))s. Raw log size: $(du -h ./04_results/RawLogs/raw_${FILE_PREFIX}.json 2>/dev/null | cut -f1)"
  
  echo "Fetching metrics from Prometheus and generating plots..."
  local ANALYTICS_START=$(date +%s)
  python3 ./05_analitics/fetch_and_plot.py --start "$START_TIME" --end "$END_TIME" --setup "$SETUP_NAME" --test-type "$TEST_TYPE" --prefix "$FILE_PREFIX" || echo "Warning: Failed to fetch metrics or plot them."
  local ANALYTICS_END=$(date +%s)
  echo "Analytics step took $((ANALYTICS_END - ANALYTICS_START))s."

  echo "Exporting Grafana panel snapshots (if configured)..."
  export_grafana_panels "$FILE_PREFIX" "$START_TIME" "$END_TIME"
  
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
capture_cipher_stats "mtls1.3-default" "before"

# Test with Keep-Alive ON
run_test_profile "mtls1.3-default" "baseline" "false"
run_test_profile "mtls1.3-default" "payload" "false"
run_test_profile "mtls1.3-default" "stress" "false"

# Test with Keep-Alive OFF (forces TLS handshake on every request to see 1-RTT vs 2-RTT difference)
run_test_profile "mtls1.3-default" "baseline" "true"
run_test_profile "mtls1.3-default" "payload" "true"
capture_cipher_stats "mtls1.3-default" "after"


# ==========================================
# SETUP 2: mTLS 1.2 with AES-GCM
# ==========================================
echo "=== BEGIN SETUP 2: mTLS 1.2 (AES-GCM) ==="
kubectl delete envoyfilter --all -n default || true
kubectl apply -f ./02_manifests/envoyfilter_gcm.yaml

echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
sleep 15
kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-gcm_${TIMESTAMP}.yaml
capture_cipher_stats "mtls1.2-gcm" "before"

# Test with Keep-Alive ON
run_test_profile "mtls1.2-gcm" "baseline" "false"
run_test_profile "mtls1.2-gcm" "payload" "false"
run_test_profile "mtls1.2-gcm" "stress" "false"

# Test with Keep-Alive OFF
run_test_profile "mtls1.2-gcm" "baseline" "true"
run_test_profile "mtls1.2-gcm" "payload" "true"
capture_cipher_stats "mtls1.2-gcm" "after"


# ==========================================
# SETUP 3: mTLS 1.2 with ChaCha20
# ==========================================
echo "=== BEGIN SETUP 3: mTLS 1.2 (ChaCha20) ==="
kubectl delete envoyfilter --all -n default || true
kubectl apply -f ./02_manifests/envoyfilter_chacha.yaml

echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
sleep 15
kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-chacha_${TIMESTAMP}.yaml
capture_cipher_stats "mtls1.2-chacha" "before"

# Test with Keep-Alive ON
run_test_profile "mtls1.2-chacha" "baseline" "false"
run_test_profile "mtls1.2-chacha" "payload" "false"
run_test_profile "mtls1.2-chacha" "stress" "false"

# Test with Keep-Alive OFF
run_test_profile "mtls1.2-chacha" "baseline" "true"
run_test_profile "mtls1.2-chacha" "payload" "true"
capture_cipher_stats "mtls1.2-chacha" "after"


# ==========================================
# SETUP 4: mTLS 1.2 with AES-CBC
# ==========================================
echo "=== BEGIN SETUP 4: mTLS 1.2 (AES-CBC) ==="
kubectl delete envoyfilter --all -n default || true
kubectl apply -f ./02_manifests/envoyfilter_cbc.yaml

echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
sleep 15
kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-cbc_${TIMESTAMP}.yaml
capture_cipher_stats "mtls1.2-cbc" "before"

# Test with Keep-Alive ON
run_test_profile "mtls1.2-cbc" "baseline" "false"
run_test_profile "mtls1.2-cbc" "payload" "false"
run_test_profile "mtls1.2-cbc" "stress" "false"

# Test with Keep-Alive OFF
run_test_profile "mtls1.2-cbc" "baseline" "true"
run_test_profile "mtls1.2-cbc" "payload" "true"
capture_cipher_stats "mtls1.2-cbc" "after"


# ==========================================
# CLEANUP
# ==========================================
echo "Cleaning up port-forwards..."
kill $PROM_PF_PID || true
kill $GRAFANA_PF_PID || true

echo "=== ALL TESTS COMPLETED SUCCESSFULLY ==="