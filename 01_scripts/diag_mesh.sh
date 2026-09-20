#!/bin/bash
# ==============================================================================
# diag_mesh.sh
# Diagnostic tool to verify Istio service mesh health, sidecar injection,
# PeerAuthentication mode, and traffic encryption status between k6 and httpbin.
# This script is read-only and does not mutate cluster state.
# ==============================================================================
set -uo pipefail

echo "================================================================"
echo " 1. VERIFYING ISTIO SIDECAR INJECTION IN K6 POD"
echo "================================================================"
K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
K6_NS=$(kubectl get pod "$K6_POD" -o jsonpath="{.metadata.namespace}" 2>/dev/null)
echo "Pod: $K6_POD (namespace: $K6_NS)"
echo "Containers in k6 pod (.spec.containers):"
kubectl get pod "$K6_POD" -n "$K6_NS" -o jsonpath='{.spec.containers[*].name}{"\n"}'
echo "Init-containers in k6 pod (.spec.initContainers) [native sidecar location in newer Istio/K8s]:"
kubectl get pod "$K6_POD" -n "$K6_NS" -o jsonpath='{.spec.initContainers[*].name}{"\n"}'
echo "Annotation sidecar.istio.io/status (present only if injected):"
kubectl get pod "$K6_POD" -n "$K6_NS" -o jsonpath='{.metadata.annotations.sidecar\.istio\.io/status}{"\n"}' || echo "(none - SIDECAR NOT DETECTED)"
echo ""
ALL_CONTAINERS=$(kubectl get pod "$K6_POD" -n "$K6_NS" -o jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}')
if echo "$ALL_CONTAINERS" | grep -q istio-proxy; then
  echo ">>> RESULT: k6 pod HAS an istio-proxy sidecar present."
else
  echo ">>> RESULT: k6 pod DOES NOT have an istio-proxy sidecar!"
  echo "    Warning: EnvoyFilters matching 'app: k6' will be no-ops,"
  echo "    and all egress traffic will bypass mTLS directly to Service."
fi

echo ""
echo "================================================================"
echo " 2. VERIFYING ISTIO SIDECAR INJECTION IN HTTPBIN POD"
echo "================================================================"
HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
HTTPBIN_NS=$(kubectl get pod "$HTTPBIN_POD" -o jsonpath="{.metadata.namespace}" 2>/dev/null)
echo "Pod: $HTTPBIN_POD (namespace: $HTTPBIN_NS)"
kubectl get pod "$HTTPBIN_POD" -n "$HTTPBIN_NS" -o jsonpath='{.spec.containers[*].name}{"\n"}'

echo ""
echo "================================================================"
echo " 3. HTTPBIN REPLICA COUNT"
echo "================================================================"
kubectl get pods -l app=httpbin -n "$HTTPBIN_NS" -o wide

echo ""
echo "================================================================"
echo " 4. PEERAUTHENTICATION POLICY (mTLS enforcement mode)"
echo "================================================================"
echo "-- Mesh-wide policy (istio-system namespace) --"
kubectl get peerauthentication -n istio-system -o yaml 2>/dev/null | grep -E "mode:|name:" || echo "(no mesh-wide PeerAuthentication found - defaults to PERMISSIVE)"
echo ""
echo "-- Workload namespace policy ($HTTPBIN_NS namespace) --"
kubectl get peerauthentication -n "$HTTPBIN_NS" -o yaml 2>/dev/null | grep -E "mode:|name:" || echo "(no namespace PeerAuthentication found - inherits PERMISSIVE)"

echo ""
echo "================================================================"
echo " 5. DIAGNOSTIC REQUEST TO HTTPBIN"
echo "================================================================"
echo "Executing test request from k6 pod container to httpbin endpoint..."
kubectl exec "$K6_POD" -n "$K6_NS" -c k6 -- wget -qO- --timeout=5 http://httpbin.default.svc.cluster.local:8000/get 2>&1 | head -c 300 || true
echo ""

echo ""
echo "================================================================"
echo " DIAGNOSTIC SUMMARY & TROUBLESHOOTING"
echo "================================================================"
echo "1. If k6 does not have an istio-proxy sidecar:"
echo "   Ensure namespace has label: 'istio-injection: enabled' (kubectl get ns \$K6_NS --show-labels)."
echo "   If the deployment predates the label, restart it: kubectl rollout restart deployment/k6-deploy."
echo ""
echo "2. If PeerAuthentication is PERMISSIVE:"
echo "   The server will accept plaintext alongside mTLS. To enforce strict mutual authentication,"
echo "   apply a PeerAuthentication resource with mode: STRICT."
echo ""
echo "3. Verify active DestinationRules to ensure tls.mode is not set to DISABLE:"
echo "   kubectl get destinationrule -A -o yaml | grep -A3 'tls:'"
