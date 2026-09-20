#!/bin/bash
# ==============================================================================
# reproduce_pqc_failure.sh
# Empirical experiment script for Chapter 6 of thesis:
# Isolates and reproduces handshake failure when enforcing Post-Quantum
# Cryptography (ML-KEM / Kyber768) without classical fallback on Istio.
# ==============================================================================
set -e

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="./04_results/Summary/pqc_failure_report_${TIMESTAMP}.txt"
mkdir -p ./04_results/Summary

echo "========================================================================" | tee -a "$REPORT_FILE"
echo "🔬 AUTOMATED PQC FAILURE REPRODUCTION EXPERIMENT" | tee -a "$REPORT_FILE"
echo "========================================================================" | tee -a "$REPORT_FILE"

K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")

echo "[1/5] Enabling connection & upstream DEBUG logging on k6 proxy..." | tee -a "$REPORT_FILE"
istioctl pc log "$K6_POD" --level connection:debug,upstream:debug > /dev/null

echo "[2/5] Applying Post-Quantum EnvoyFilters (Client & Server, ML-KEM only)..." | tee -a "$REPORT_FILE"
cat <<EOF | kubectl apply -f - > /dev/null
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
                ecdh_curves:
                  - "X25519MLKEM768"
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
EOF

echo "      Waiting 15s for filters to propagate..." | tee -a "$REPORT_FILE"
sleep 15

echo "[3/5] Running k6 drip test (1 request per second for 10s)..." | tee -a "$REPORT_FILE"
echo "      Expected result: 100% failure rate due to ML-KEM handshake negotiation abort." | tee -a "$REPORT_FILE"
echo 'import http from "k6/http"; import { sleep } from "k6"; export default function() { http.get("http://httpbin:8000/get"); sleep(1); }' | \
kubectl exec -i "$K6_POD" -c k6 -- k6 run --vus 1 --duration 10s - 2>&1 | command grep -i -e "http_req_failed" -e "http_reqs" | tee -a "$REPORT_FILE"

echo "[4/5] Extracting TLS connection abort evidence from Envoy logs..." | tee -a "$REPORT_FILE"
echo "------------------------------------------------------------------------" | tee -a "$REPORT_FILE"
# Standard grep with fixed patterns to ensure consistent output formatting
kubectl logs "$K6_POD" -c istio-proxy | tail -n 200 | command grep -i -e "closing data_to_write" -e "delayed close timer" -e "closing socket" | tail -n 15 | tee -a "$REPORT_FILE"
echo "------------------------------------------------------------------------" | tee -a "$REPORT_FILE"

echo "[5/5] Cleaning up (Removing EnvoyFilters, reverting log level)..." | tee -a "$REPORT_FILE"
kubectl delete envoyfilter --all -n default > /dev/null 2>&1 || true
istioctl pc log "$K6_POD" --level warning > /dev/null

echo "========================================================================" | tee -a "$REPORT_FILE"
echo "✅ Experiment complete. Evidence saved to: $REPORT_FILE"
echo "========================================================================"
