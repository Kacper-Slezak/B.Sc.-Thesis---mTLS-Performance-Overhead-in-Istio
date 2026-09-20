#!/bin/bash
# ==============================================================================
# diag_envoyfilter_config.sh <manifest.yaml>
# Diagnostic tool to inspect active Envoy proxy configurations (listeners,
# clusters, transport sockets) and verify EnvoyFilter application and Istiod logs.
# ==============================================================================
set -uo pipefail

MANIFEST="${1:-}"
if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  echo "Usage: $0 <path-to-envoyfilter-manifest.yaml>" >&2
  exit 1
fi

K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")

echo "================================================================"
echo " 1. APPLYING $MANIFEST AND WAITING FOR PROPAGATION"
echo "================================================================"
kubectl delete envoyfilter --all -n default >/dev/null 2>&1 || true
kubectl apply -f "$MANIFEST"
sleep 15

echo ""
echo "================================================================"
echo " 2. CHECKING ISTIOD ENVOYFILTER STATUS & WARNINGS"
echo "================================================================"
kubectl get envoyfilter -n default -o yaml | grep -E "name:|status:|message:" || echo "(No EnvoyFilters detected - apply may have failed)"

echo ""
echo "================================================================"
echo " 3. INSPECTING CLIENT ENVOY CONFIG (k6 sidecar) - outbound cluster"
echo "================================================================"
echo "Searching for transport_socket_matches / transport_socket in dynamic_active_clusters:"
kubectl exec "$K6_POD" -c istio-proxy -- curl -s localhost:15000/config_dump?resource=dynamic_active_clusters \
  | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as e:
    print('JSON parsing error:', e); sys.exit(1)
found = False
for cfg in data.get('configs', []):
    cluster = cfg.get('cluster', {})
    name = cluster.get('name', '')
    if 'httpbin' in name:
        found = True
        print(f'--- cluster: {name} ---')
        ts_matches = cluster.get('transport_socket_matches', [])
        if ts_matches:
            print('Found transport_socket_matches:')
            for m in ts_matches:
                print(f\"  Match Name: {m.get('name')}\")
                ts = m.get('transport_socket', {})
                print(\"  \" + json.dumps(ts, indent=2).replace('\n', '\n  ')[:1500])
        else:
            ts = cluster.get('transport_socket', {})
            if ts:
                print('Found primary transport_socket:')
                print(json.dumps(ts, indent=2)[:1500])
            else:
                print('!! No transport_socket or transport_socket_matches found')
if not found:
    print('!! No clusters containing \"httpbin\" found in dynamic_active_clusters.')
"

echo ""
echo "================================================================"
echo " 4. INSPECTING SERVER ENVOY CONFIG (httpbin sidecar) - inbound listener"
echo "================================================================"
echo "Searching for filter chain with destination_port 80 and tls_params:"
kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/config_dump?resource=dynamic_listeners \
  | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as e:
    print('JSON parsing error:', e); sys.exit(1)
found = False
for cfg in data.get('dynamic_listeners', []):
    listener = cfg.get('active_state', {}).get('listener', {})
    name = listener.get('name', '')
    if '15006' not in name:
        continue
    for fc in listener.get('filter_chains', []):
        match = fc.get('filter_chain_match', {})
        if match.get('destination_port') == 80:
            found = True
            print(f'--- listener: {name}, filter_chain_match: {match} ---')
            ts = fc.get('transport_socket', {})
            print(json.dumps(ts, indent=2)[:2000])
if not found:
    print('!! No filter_chain with destination_port=80 found on listener *_15006.')
"

echo ""
echo "================================================================"
echo " 5. PROBING TRAFFIC & RE-READING ENVOY STATS (10 requests)"
echo "================================================================"
STATS_BEFORE=$(kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats | grep -i -E "ssl\.(ciphers|curves)")
for i in $(seq 1 10); do
  kubectl exec "$K6_POD" -c k6 -- wget -qO- --timeout=5 http://httpbin.default.svc.cluster.local:8000/get >/dev/null 2>&1
done
STATS_AFTER=$(kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats | grep -i -E "ssl\.(ciphers|curves)")
echo "BEFORE:"
echo "$STATS_BEFORE"
echo "AFTER (10x wget):"
echo "$STATS_AFTER"
if [ "$STATS_BEFORE" = "$STATS_AFTER" ]; then
  echo "!! Zero traffic recorded in ssl telemetry. Verify routing configuration and sidecar injection."
fi

echo ""
echo "================================================================"
echo " 6. ISTIOD LOGS - Errors and Warnings for this EnvoyFilter"
echo "================================================================"
ISTIOD_POD=$(kubectl get pods -n istio-system -l app=istiod -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
if [ -n "$ISTIOD_POD" ]; then
  LOGS=$(kubectl logs -n istio-system "$ISTIOD_POD" --since=1m | grep -i -E "envoyfilter|reject|nack|error")
  if [ -z "$LOGS" ]; then
    echo "(No errors detected: Istiod did not reject configuration in the last 60s)"
  else
    echo "$LOGS" | tail -30
  fi
else
  echo "(istiod pod not found - skipping log check)"
fi
