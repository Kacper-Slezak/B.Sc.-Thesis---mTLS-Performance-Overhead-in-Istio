#!/bin/bash
set -e

# ==========================================
# GŁÓWNA BATERIA TESTÓW DO PRACY DYPLOMOWEJ
# ==========================================
N_RUNS="${N_RUNS:-5}"
if [ "$N_RUNS" -lt 3 ]; then
  echo "UWAGA: N_RUNS=$N_RUNS < 3. Ponizej 3 powtorzen stats_compare.py"
  echo "i tak nie policzy niczego sensownego (brak CI, brak testu istotnosci)."
fi

export PAYLOAD_SIZE_KB="${PAYLOAD_SIZE_KB:-5000}"
export HANDSHAKE_RATE="${HANDSHAKE_RATE:-50}"

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
HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")
echo "Detected K6 pod: $K6_POD"
echo "Detected HTTPBin pod: $HTTPBIN_POD"

# ==========================================
# PORT-FORWARDING SETUP & CLEANUP TRAP
# ==========================================
echo "Starting port-forward to Prometheus in the background (localhost:9090)..."
pkill -f "port-forward svc/prometheus" || true
kubectl port-forward -n istio-system svc/prometheus 9090:9090 > /dev/null 2>&1 &
PROM_PF_PID=$!

echo "Starting port-forward to Grafana in the background (localhost:3000)..."
pkill -f "port-forward svc/grafana" || true
kubectl port-forward -n istio-system svc/grafana 3000:3000 > /dev/null 2>&1 &
GRAFANA_PF_PID=$!

cleanup() {
  echo "Cleaning up port-forwards and temporary resources..."
  kill $PROM_PF_PID 2>/dev/null || true
  kill $GRAFANA_PF_PID 2>/dev/null || true
  kubectl delete -f ./02_manifests/dr_nokeepalive.yaml 2>/dev/null || true
}
trap cleanup EXIT INT TERM

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
  local CURRENT_HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")

  if [ "$SETUP_NAME" = "plaintext" ]; then
    return # Dla Plaintext nie ma szyfrów do przechwycenia
  fi

  echo "Capturing cipher & curve stats for ${SETUP_NAME} (${SUFFIX})..."
  kubectl exec "$CURRENT_HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats \
    | grep -i -E "ssl\.(ciphers|curves)" \
    > "./04_results/Summary/cipher_stats_${SETUP_NAME}_${SUFFIX}_${TIMESTAMP}.txt" || true
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

# ==========================================
# POMIAR CZASU TLS HANDSHAKE Z ENVOY
# ==========================================
get_ssl_handshake_sum_count() {
  local pod="$1"
  local prom_text
  prom_text=$(kubectl exec "$pod" -c istio-proxy -- curl -s localhost:15000/stats/prometheus 2>/dev/null)
  local sum count
  sum=$(echo "$prom_text" | grep -E '^envoy_.*_ssl_handshake_sum' | awk '{s+=$NF} END{printf "%f", s+0}')
  count=$(echo "$prom_text" | grep -E '^envoy_.*_ssl_handshake_count' | awk '{s+=$NF} END{printf "%f", s+0}')
  echo "${sum:-0} ${count:-0}"
}

CSV_PATH="./04_results/Summary/handshake_latency.csv"
if [ ! -f "$CSV_PATH" ]; then
  echo "setup,scenario,suffix,run,timestamp,handshake_mean_ms,count_delta,file_prefix" > "$CSV_PATH"
fi

run_test_profile() {
  local SETUP_NAME=$1
  local TEST_TYPE=$2
  local DISABLE_KEEP_ALIVE=${3:-"false"}
  local RUN_IDX=${4:-1}
  local FILE_SUFFIX=""
  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    FILE_SUFFIX="-nokeepalive"
  fi
  local FILE_PREFIX="${SETUP_NAME}_${TEST_TYPE}${FILE_SUFFIX}_run${RUN_IDX}_${TIMESTAMP}"

  echo "========================================================================"
  echo "Starting test profile: [${TEST_TYPE}]"
  echo "Setup: [${SETUP_NAME}] | Keep-Alive: [${DISABLE_KEEP_ALIVE}] | Powtorzenie: [${RUN_IDX}/${N_RUNS}]"
  echo "========================================================================"

  local START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$DISABLE_KEEP_ALIVE" = "true" ] && [ "$SETUP_NAME" != "plaintext" ]; then
    kubectl apply -f ./02_manifests/dr_nokeepalive.yaml > /dev/null
    sleep 10
  fi

  local CURRENT_HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")
  read -r HS_SUM_BEFORE HS_COUNT_BEFORE <<< "$(get_ssl_handshake_sum_count "$CURRENT_HTTPBIN_POD")"

  kubectl exec $K6_POD -c k6 -- rm -f /tmp/raw.json /tmp/summary.json || true
  cat ./03_test_scripts/main_k6_scenarios_3.js | kubectl exec -i $K6_POD -c k6 -- k6 run \
    -e TEST_TYPE=${TEST_TYPE} \
    -e DISABLE_KEEP_ALIVE=${DISABLE_KEEP_ALIVE} \
    -e PAYLOAD_SIZE_KB=${PAYLOAD_SIZE_KB:-5000} \
    -e HANDSHAKE_RATE=${HANDSHAKE_RATE:-50} \
    --out json=/tmp/raw.json -

  read -r HS_SUM_AFTER HS_COUNT_AFTER <<< "$(get_ssl_handshake_sum_count "$CURRENT_HTTPBIN_POD")"
  
  if [ "$SETUP_NAME" != "plaintext" ]; then
    local HS_COUNT_DELTA=$(awk -v a="$HS_COUNT_AFTER" -v b="$HS_COUNT_BEFORE" 'BEGIN{printf "%f", a-b}')
    local HS_SUM_DELTA=$(awk -v a="$HS_SUM_AFTER" -v b="$HS_SUM_BEFORE" 'BEGIN{printf "%f", a-b}')
    local HS_MEAN_MS="n/a"
    if awk -v c="$HS_COUNT_DELTA" 'BEGIN{exit !(c>0)}'; then
      HS_MEAN_MS=$(awk -v s="$HS_SUM_DELTA" -v c="$HS_COUNT_DELTA" 'BEGIN{printf "%.4f", s/c}')
    fi
    echo "TLS handshake w tym oknie: count_delta=${HS_COUNT_DELTA} mean_ms=${HS_MEAN_MS}"
    echo "${SETUP_NAME},${TEST_TYPE},${FILE_SUFFIX},${RUN_IDX},${TIMESTAMP},${HS_MEAN_MS},${HS_COUNT_DELTA},${FILE_PREFIX}" >> "$CSV_PATH"
  fi

  local END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$DISABLE_KEEP_ALIVE" = "true" ] && [ "$SETUP_NAME" != "plaintext" ]; then
    kubectl delete -f ./02_manifests/dr_nokeepalive.yaml > /dev/null || true
  fi

  echo "Downloading results..."
  kubectl exec $K6_POD -c k6 -- gzip -c /tmp/raw.json > ./04_results/RawLogs/raw_${FILE_PREFIX}.json.gz
  gzip -d -f ./04_results/RawLogs/raw_${FILE_PREFIX}.json.gz
  kubectl exec $K6_POD -c k6 -- cat /tmp/summary.json > ./04_results/Summary/summary_${FILE_PREFIX}.json

  echo "Fetching metrics from Prometheus and generating plots..."
  python3 ./05_analitics/fetch_and_plot.py --start "$START_TIME" --end "$END_TIME" --setup "$SETUP_NAME" --test-type "$TEST_TYPE" --prefix "$FILE_PREFIX" || echo "Warning: Fetch failed."
  export_grafana_panels "$FILE_PREFIX" "$START_TIME" "$END_TIME"
  
  sleep 5
}

run_full_battery() {
  local SETUP_NAME=$1
  local SCENARIOS=("baseline:false" "payload:false" "stress:false" "baseline:true" "payload:true" "handshake:true")

  for RUN_IDX in $(seq 1 "$N_RUNS"); do
    local SHUFFLED=($(printf "%s\n" "${SCENARIOS[@]}" | shuf))
    echo ">>> [$SETUP_NAME] Powtorzenie $RUN_IDX/$N_RUNS"
    for ENTRY in "${SHUFFLED[@]}"; do
      local TEST_TYPE="${ENTRY%%:*}"
      local DISABLE_KA="${ENTRY##*:}"
      run_test_profile "$SETUP_NAME" "$TEST_TYPE" "$DISABLE_KA" "$RUN_IDX"
    done
  done
}

run_warmup() {
  echo "--- WARM-UP RUN (15s) to fill caches and stabilize CPU ---"
  echo 'import http from "k6/http"; export default function() { http.get("http://httpbin:8000/get"); }' | \
  kubectl exec -i $K6_POD -c k6 -- k6 run --vus 10 --duration 15s - > /dev/null 2>&1 || true
  sleep 10
}

# ==========================================
# SETUP FUNCTIONS
# ==========================================
setup_plaintext() {
  echo "=== BEGIN SETUP 0: Plaintext (NO mTLS) ==="
  kubectl delete envoyfilter --all -n default 2>/dev/null || true
  
  cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: disable-mtls
  namespace: default
spec:
  mtls:
    mode: DISABLE
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: disable-mtls-client
  namespace: default
spec:
  host: httpbin.default.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
EOF
  sleep 15
  run_warmup
  run_full_battery "plaintext"
  kubectl delete peerauthentication disable-mtls -n default 2>/dev/null || true
  kubectl delete destinationrule disable-mtls-client -n default 2>/dev/null || true
}

setup_mtls1_3() {
  echo "=== BEGIN SETUP 1: mTLS 1.3 (Default) ==="
  kubectl delete envoyfilter --all -n default 2>/dev/null || true
  sleep 10
  run_warmup
  capture_cipher_stats "mtls1.3-default" "before"
  run_full_battery "mtls1.3-default"
  capture_cipher_stats "mtls1.3-default" "after"
}

setup_mtls1_2_gcm() {
  echo "=== BEGIN SETUP 2: mTLS 1.2 (AES-GCM) ==="
  kubectl delete envoyfilter --all -n default 2>/dev/null || true
  kubectl apply -f ./02_manifests/envoyfilter_gcm.yaml
  sleep 15
  run_warmup
  capture_cipher_stats "mtls1.2-gcm" "before"
  run_full_battery "mtls1.2-gcm"
  capture_cipher_stats "mtls1.2-gcm" "after"
}

setup_mtls1_2_chacha() {
  echo "=== BEGIN SETUP 3: mTLS 1.2 (ChaCha20) ==="
  kubectl delete envoyfilter --all -n default 2>/dev/null || true
  kubectl apply -f ./02_manifests/envoyfilter_chacha.yaml
  sleep 15
  run_warmup
  capture_cipher_stats "mtls1.2-chacha" "before"
  run_full_battery "mtls1.2-chacha"
  capture_cipher_stats "mtls1.2-chacha" "after"
}

setup_mtls1_2_cbc() {
  echo "=== BEGIN SETUP 4: mTLS 1.2 (AES-CBC) ==="
  kubectl delete envoyfilter --all -n default 2>/dev/null || true
  kubectl apply -f ./02_manifests/envoyfilter_cbc.yaml
  sleep 15
  run_warmup
  capture_cipher_stats "mtls1.2-cbc" "before"
  run_full_battery "mtls1.2-cbc"
  capture_cipher_stats "mtls1.2-cbc" "after"
}

setup_mtls1_3_pqc() {
  echo "=== BEGIN SETUP 5: mTLS 1.3 Post-Quantum (ML-KEM) ==="
  kubectl delete envoyfilter --all -n default 2>/dev/null || true

  echo "Applying Quantum EnvoyFilters (Client & Server) with 32KB buffers..."
  cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: force-pqc-client
  namespace: default
spec:
  workloadSelector:
    labels:
      app: k6
  configPatches:
  - applyTo: CLUSTER
    match:
      context: SIDECAR_OUTBOUND
      cluster:
        name: "outbound|8000||httpbin.default.svc.cluster.local"
    patch:
      operation: MERGE
      value:
        per_connection_buffer_limit_bytes: 32768
        transport_socket:
          name: envoy.transport_sockets.tls
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
            common_tls_context:
              tls_params:
                tls_maximum_protocol_version: TLSv1_3
                tls_minimum_protocol_version: TLSv1_3
                ecdh_curves:
                  - "X25519MLKEM768"
                  - "X25519Kyber768Draft00"
                  - "X25519"
---
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: force-pqc-server
  namespace: default
spec:
  workloadSelector:
    labels:
      app: httpbin
  configPatches:
  - applyTo: FILTER_CHAIN
    match:
      context: SIDECAR_INBOUND
      listener:
        portNumber: 15006
        filterChain:
          transportProtocol: tls
    patch:
      operation: MERGE
      value:
        per_connection_buffer_limit_bytes: 32768
        transport_socket:
          name: envoy.transport_sockets.tls
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext
            common_tls_context:
              tls_params:
                tls_maximum_protocol_version: TLSv1_3
                tls_minimum_protocol_version: TLSv1_3
                ecdh_curves:
                  - "X25519MLKEM768"
                  - "X25519Kyber768Draft00"
                  - "X25519"
EOF

  sleep 15
  run_warmup
  capture_cipher_stats "mtls1.3-postquantum" "before"
  run_full_battery "mtls1.3-postquantum"
  capture_cipher_stats "mtls1.3-postquantum" "after"
}

# ==========================================
# RANDOMIZED EXECUTION ENGINE
# ==========================================
SETUPS=("plaintext" "mtls1.3-default" "mtls1.2-gcm" "mtls1.2-chacha" "mtls1.2-cbc" "mtls1.3-postquantum")

SHUFFLED_SETUPS=($(printf "%s\n" "${SETUPS[@]}" | shuf))

echo "========================================================================"
echo "🎯 EXECUTION PLAN (Randomized):"
for i in "${!SHUFFLED_SETUPS[@]}"; do
  echo "  $((i+1)). ${SHUFFLED_SETUPS[$i]}"
done
echo "========================================================================"
sleep 3

for SETUP in "${SHUFFLED_SETUPS[@]}"; do
  case $SETUP in
    "plaintext")       setup_plaintext ;;
    "mtls1.3-default") setup_mtls1_3 ;;
    "mtls1.2-gcm")     setup_mtls1_2_gcm ;;
    "mtls1.2-chacha")  setup_mtls1_2_chacha ;;
    "mtls1.2-cbc")     setup_mtls1_2_cbc ;;
    "mtls1.3-postquantum") setup_mtls1_3_pqc ;;
  esac

  echo "Cooling down for 60 seconds before the next setup to prevent thermal throttling..."
  sleep 60
done

# ==========================================
# FINAL REPORT GENERATION & CLEANUP
# ==========================================
echo "Resetting EnvoyFilters to clean state..."
kubectl delete envoyfilter --all -n default 2>/dev/null || true

echo "Generating comparison reports..."
python3 ./05_analitics/compare_results.py || echo "Warning: compare_results failed."
python3 ./05_analitics/stats_compare.py --results-dir ./04_results/Summary --baseline plaintext \
  | tee "./04_results/Summary/stats_compare_${TIMESTAMP}.txt" || true

echo "=== ALL TESTS COMPLETED SUCCESSFULLY ==="