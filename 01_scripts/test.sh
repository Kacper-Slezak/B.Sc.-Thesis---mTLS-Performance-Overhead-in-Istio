#!/bin/bash
# ==============================================================================
# test.sh
# Diagnostic verification script:
# Evaluates sidecar CPU consumption under TLS 1.2 with Keep-Alive disabled
# (maxRequestsPerConnection=1), proving forced connection termination/creation.
# ==============================================================================
set -e

echo "======================================================"
echo "🔍 DIAGNOSTIC RUN: No-KeepAlive mTLS CPU Profiling"
echo "======================================================"

K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")

echo "Cleaning environment..."
kubectl delete envoyfilter --all -n default 2>/dev/null || true
kubectl delete destinationrule --all -n default 2>/dev/null || true

echo "Applying policies (EnvoyFilter Inbound + DestinationRule No-KeepAlive)..."
cat <<EOF | kubectl apply -f -
# 1. Server inbound cipher restriction
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: force-cipher-httpbin
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
                tls_maximum_protocol_version: TLSv1_2
                tls_minimum_protocol_version: TLSv1_2
                cipher_suites:
                - "ECDHE-ECDSA-AES128-GCM-SHA256"
---
# 2. DestinationRule: Disable Keep-Alive (1 request per connection) + disable HTTP/2 upgrade
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: disable-keepalive
  namespace: default
spec:
  host: httpbin.default.svc.cluster.local
  trafficPolicy:
    connectionPool:
      http:
        maxRequestsPerConnection: 1
        h2UpgradePolicy: DO_NOT_UPGRADE
EOF

echo "Waiting 10 seconds for proxy reconfiguration..."
sleep 10

echo "======================================================"
echo "Starting background k6 load test (50 VUs, 15s duration)..."
cat ./03_test_scripts/main_k6_scenarios.js | kubectl exec -i "$K6_POD" -c k6 -- k6 run -e TEST_TYPE=baseline -e DISABLE_KEEP_ALIVE=true --vus 50 --duration 15s - > /tmp/k6_logs.txt 2>&1 &
K6_PID=$!

echo "Proxy CPU utilization measurements during test run:"
for i in {1..9}; do
  kubectl top pod "$HTTPBIN_POD" --containers 2>/dev/null | grep istio-proxy || true
  sleep 3
done

wait $K6_PID

echo "======================================================"
echo "Envoy connection telemetry (outbound connection count):"
kubectl exec "$K6_POD" -c istio-proxy -- curl -s http://localhost:15000/stats | grep "cx_total" | grep "outbound" || echo "Metric not found"

echo "Cleanup complete."
