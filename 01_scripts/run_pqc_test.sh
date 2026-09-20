#!/bin/bash
# ==============================================================================
# run_pqc_test.sh
# Automated scanner to test post-quantum and hybrid key-exchange curves
# (ML-KEM / Kyber / CECPQ2) against the deployed Istio Envoy proxy build.
# ==============================================================================
set -e

# Curves to scan: from modern NIST standards (ML-KEM) to historical drafts
CURVES=("X25519MLKEM768" "X25519Kyber768Draft00" "CECPQ2")

echo "=== Automated Post-Quantum Cryptography (PQC) Support Scan in Istio ==="

for CURVE in "${CURVES[@]}"; do
    echo -e "\n--------------------------------------------------"
    echo "🧪 EVALUATING CURVE: ${CURVE}"
    echo "--------------------------------------------------"
    
    # 1. Clean prior filters
    kubectl delete envoyfilter force-pqc-client force-pqc-server -n default 2>/dev/null || true
    
    # 2. Apply EnvoyFilters isolating this specific curve
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
        transport_socket:
          name: envoy.transport_sockets.tls
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
            common_tls_context:
              tls_params:
                tls_maximum_protocol_version: TLSv1_3
                tls_minimum_protocol_version: TLSv1_3
                ecdh_curves: ["${CURVE}"]
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
        transport_socket:
          name: envoy.transport_sockets.tls
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext
            common_tls_context:
              tls_params:
                tls_maximum_protocol_version: TLSv1_3
                tls_minimum_protocol_version: TLSv1_3
                ecdh_curves: ["${CURVE}"]
EOF

    echo "⏳ Waiting 15s for EnvoyFilter propagation..."
    sleep 15
    
    echo "🚀 Running test traffic through k6 (5 requests)..."
    kubectl exec -n default deploy/k6-deploy -- sh -c 'echo "import http from \"k6/http\"; export default function() { http.get(\"http://httpbin:8000/get\", {headers: {\"Connection\": \"close\"}}); }" > /tmp/pqc_quick.js && k6 run --vus 1 --iterations 5 /tmp/pqc_quick.js' > /tmp/k6_out.txt 2>&1 || true
    
    # Analyze outcome
    if grep -q "http_req_failed......: 100.00%" /tmp/k6_out.txt; then
        echo "❌ RESULT: Envoy REJECTED curve ${CURVE} (No compiler/runtime support in this Istio build)"
    elif grep -q "http_req_failed......: 0.00%" /tmp/k6_out.txt; then
        echo "✅ RESULT: SUCCESS! Envoy negotiated curve ${CURVE}."
        kubectl exec -n default deploy/httpbin -c istio-proxy -- curl -s localhost:15000/stats | grep -E "ssl\.curves" || true
    else
        echo "⚠️ RESULT: Unknown response or partial failure. Inspect proxy logs for details."
    fi
done

echo -e "\n=== Teardown & Cleanup ==="
kubectl delete envoyfilter force-pqc-client force-pqc-server -n default 2>/dev/null || true
echo "Completed."
