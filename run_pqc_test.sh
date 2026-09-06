#!/bin/bash
set -e

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "========================================================================"
echo "🧪 POST-QUANTUM CRYPTOGRAPHY (PQC) PERFORMANCE TEST SUITE"
echo "========================================================================"

echo "Archiving previous test results..."
python3 ./05_analitics/archive_results.py || echo "Warning: Archiving failed, proceeding anyway."

mkdir -p ./04_results/Summary
mkdir -p ./04_results/RawLogs
mkdir -p ./04_results/Plots
mkdir -p ./04_results/Metrics
mkdir -p ./04_results/Archive

K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")
echo "Detected K6 pod: $K6_POD"

# ==========================================
# PORT-FORWARDING
# ==========================================
echo "Starting port-forward to Prometheus..."
pkill -f "port-forward svc/prometheus" || true
kubectl port-forward -n istio-system svc/prometheus 9090:9090 > /dev/null 2>&1 &
PROM_PF_PID=$!

sleep 5

# ==========================================
# HELPER FUNCTIONS
# ==========================================
capture_stats() {
  local SETUP_NAME=$1
  local SUFFIX=$2 
  
  echo "Capturing crypto stats for ${SETUP_NAME} (${SUFFIX})..."
  
  # Pobieramy zarówno wynegocjowany szyfr, jak i KRZYWĄ KRYPTOGRAFICZNĄ (KEM)
  kubectl exec "$HTTPBIN_POD" -c istio-proxy -- sh -c 'curl -s localhost:15000/stats | grep -i "ssl.ciphers"' > "./04_results/Summary/crypto_stats_${SETUP_NAME}_${SUFFIX}_${TIMESTAMP}.txt" || true
  kubectl exec "$HTTPBIN_POD" -c istio-proxy -- sh -c 'curl -s localhost:15000/stats | grep -i "ssl.curves"' >> "./04_results/Summary/crypto_stats_${SETUP_NAME}_${SUFFIX}_${TIMESTAMP}.txt" || true

  echo "--- Found Crypto Parameters for ${SETUP_NAME} ---"
  cat "./04_results/Summary/crypto_stats_${SETUP_NAME}_${SUFFIX}_${TIMESTAMP}.txt"
  echo "-------------------------------------------------"
}

run_warmup() {
  echo "--- WARM-UP RUN (15s) to initialize SSL caches and CPU ---"
  echo 'import http from "k6/http"; export default function() { http.get("http://httpbin:8000/get"); }' | \
  kubectl exec -i $K6_POD -c k6 -- k6 run --vus 10 --duration 15s - > /dev/null 2>&1 || true
  echo "Warm-up complete. Sleeping 10s..."
  sleep 10
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

  echo "------------------------------------------------------------------------"
  echo "🚀 Running Profile: [${TEST_TYPE}] | Setup: [${SETUP_NAME}]"
  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    echo "Keep-Alive: OFF (Connection: close) -> High TLS Handshake stress!"
  else
    echo "Keep-Alive: ON (Keep-Alive) -> Symmetric cipher stress!"
  fi
  
  local START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    kubectl apply -f ./02_manifests/dr_nokeepalive.yaml > /dev/null
    sleep 10
  fi

  # Uruchamiamy test K6
  cat ./03_test_scripts/main_k6_scenarios.js | kubectl exec -i $K6_POD -c k6 -- k6 run -e TEST_TYPE=${TEST_TYPE} -e DISABLE_KEEP_ALIVE=${DISABLE_KEEP_ALIVE} --out json=/tmp/raw.json -

  local END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$DISABLE_KEEP_ALIVE" = "true" ]; then
    kubectl delete -f ./02_manifests/dr_nokeepalive.yaml > /dev/null || true
  fi
  
  echo "Downloading logs and fetching metrics for ${FILE_PREFIX}..."
  kubectl exec $K6_POD -c k6 -- gzip -c /tmp/raw.json > ./04_results/RawLogs/raw_${FILE_PREFIX}.json.gz
  gzip -d ./04_results/RawLogs/raw_${FILE_PREFIX}.json.gz
  kubectl exec $K6_POD -c k6 -- cat /tmp/summary.json > ./04_results/Summary/summary_${FILE_PREFIX}.json
  
  python3 ./05_analitics/fetch_and_plot.py --start "$START_TIME" --end "$END_TIME" --setup "$SETUP_NAME" --test-type "$TEST_TYPE" --prefix "$FILE_PREFIX" > /dev/null 2>&1 || echo "Warning: Metric fetch failed."
  
  sleep 5
}


# ==========================================
# PHASE 1: STANDARD mTLS 1.3 (Reference)
# ==========================================
echo ""
echo "========================================================================"
echo "PHASE 1: Standard mTLS 1.3 (Classic X25519 Key Exchange)"
echo "========================================================================"
kubectl delete envoyfilter --all -n default 2>/dev/null || true
sleep 10

run_warmup
capture_stats "mtls1.3-standard" "before"

# Badamy maksymalną przepustowość przesyłu (Keep-Alive ON)
run_test_profile "mtls1.3-standard" "stress" "false"

# Badamy maksymalny narzut negocjacji TLS (Handshake na każde zapytanie)
run_test_profile "mtls1.3-standard" "baseline" "true"

capture_stats "mtls1.3-standard" "after"

echo "⏳ Cooling down for 60 seconds before PQC tests to prevent thermal throttling..."
sleep 60


# ==========================================
# PHASE 2: POST-QUANTUM mTLS 1.3 (ML-KEM)
# ==========================================
echo ""
echo "========================================================================"
echo "PHASE 2: Post-Quantum mTLS 1.3 (X25519MLKEM768 Key Exchange)"
echo "========================================================================"

# Aplikujemy filtry kwantowe na serwer i klienta
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
        filterChain:
          destinationPort: 8080
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

echo "Waiting 15 seconds for Quantum EnvoyFilter propagation..."
sleep 15

run_warmup
capture_stats "mtls1.3-postquantum" "before"

# Badamy maksymalną przepustowość przesyłu (Keep-Alive ON)
run_test_profile "mtls1.3-postquantum" "stress" "false"

# Badamy maksymalny narzut negocjacji PQC (Gigantyczne paczki ML-KEM na każde zapytanie)
run_test_profile "mtls1.3-postquantum" "baseline" "true"

capture_stats "mtls1.3-postquantum" "after"


# ==========================================
# CLEANUP
# ==========================================
echo "Cleaning up..."
kubectl delete envoyfilter --all -n default 2>/dev/null || true
kill $PROM_PF_PID || true

echo "=== QUANTUM TESTS COMPLETED SUCCESSFULLY ==="