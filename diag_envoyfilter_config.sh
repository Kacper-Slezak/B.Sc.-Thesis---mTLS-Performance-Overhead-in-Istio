#!/bin/bash
# ==========================================================================
# diag_envoyfilter_config.sh <manifest.yaml>
# ==========================================================================
set -uo pipefail

MANIFEST="${1:-}"
if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  echo "Uzycie: $0 <sciezka-do-manifestu-envoyfilter.yaml>" >&2
  exit 1
fi

K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")

echo "================================================================"
echo " 1. APLIKUJE $MANIFEST I CZEKAM NA PROPAGACJE"
echo "================================================================"
kubectl delete envoyfilter --all -n default >/dev/null 2>&1 || true
kubectl apply -f "$MANIFEST"
sleep 15

echo ""
echo "================================================================"
echo " 2. CZY ISTIOD W OGOLE ZAAKCEPTOWAL FILTR? (status/warnings)"
echo "================================================================"
kubectl get envoyfilter -n default -o yaml | grep -E "name:|status:|message:" || echo "(brak EnvoyFilter widocznych - apply sie nie udal?)"

echo ""
echo "================================================================"
echo " 3. ZYWY CONFIG KLIENTA (k6 sidecar) - cluster outbound|8000|...httpbin"
echo "================================================================"
echo "Szukam sekcji transport_socket_matches / transport_socket w dynamic_active_clusters:"
kubectl exec "$K6_POD" -c istio-proxy -- curl -s localhost:15000/config_dump?resource=dynamic_active_clusters \
  | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as e:
    print('BLAD parsowania JSON:', e); sys.exit(1)
found = False
for cfg in data.get('configs', []):
    cluster = cfg.get('cluster', {})
    name = cluster.get('name', '')
    if 'httpbin' in name:
        found = True
        print(f'--- cluster: {name} ---')
        ts_matches = cluster.get('transport_socket_matches', [])
        if ts_matches:
            print('Znaleziono transport_socket_matches:')
            for m in ts_matches:
                print(f\"  Match Name: {m.get('name')}\")
                ts = m.get('transport_socket', {})
                print(\"  \" + json.dumps(ts, indent=2).replace('\n', '\n  ')[:1500])
        else:
            ts = cluster.get('transport_socket', {})
            if ts:
                print('Znaleziono tylko glowny transport_socket:')
                print(json.dumps(ts, indent=2)[:1500])
            else:
                print('!! Brak transport_socket i transport_socket_matches')
if not found:
    print('!! Nie znaleziono zadnego clustra z \"httpbin\" w nazwie w dynamic_active_clusters.')
"

echo ""
echo "================================================================"
echo " 4. ZYWY CONFIG SERWERA (httpbin sidecar) - listener inbound port 80"
echo "================================================================"
echo "Szukam filter chain z destination_port 80 i jego tls_params:"
kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/config_dump?resource=dynamic_listeners \
  | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as e:
    print('BLAD parsowania JSON:', e); sys.exit(1)
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
    print('!! Nie znaleziono filter_chain z destination_port=80 na listenerze *_15006.')
"

echo ""
echo "================================================================"
echo " 5. PROBNY RUCH + PONOWNY ODCZYT STATOW (10 requestow, bez k6)"
echo "================================================================"
STATS_BEFORE=$(kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats | grep -i -E "ssl\.(ciphers|curves)")
for i in $(seq 1 10); do
  kubectl exec "$K6_POD" -c k6 -- wget -qO- --timeout=5 http://httpbin.default.svc.cluster.local:8000/get >/dev/null 2>&1
done
STATS_AFTER=$(kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats | grep -i -E "ssl\.(ciphers|curves)")
echo "PRZED:"
echo "$STATS_BEFORE"
echo "PO (10x wget):"
echo "$STATS_AFTER"
if [ "$STATS_BEFORE" = "$STATS_AFTER" ]; then
  echo "!! Nadal zero ruchu nawet przy prostym wget spoza k6 - problem jest"
  echo "   w konfiguracji Envoya/routingu, nie w samym k6/skrypcie testowym."
fi

echo ""
echo "================================================================"
echo " 6. LOGI ISTIOD - bledy/warningi zwiazane z tym EnvoyFilter"
echo "================================================================"
ISTIOD_POD=$(kubectl get pods -n istio-system -l app=istiod -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
if [ -n "$ISTIOD_POD" ]; then
  # PATCH: Ograniczamy logi do ostatniej minuty, żeby zignorować stare błędy!
  LOGS=$(kubectl logs -n istio-system "$ISTIOD_POD" --since=1m | grep -i -E "envoyfilter|reject|nack|error")
  if [ -z "$LOGS" ]; then
    echo "(BRAK BŁĘDÓW - w ciągu ostatniej minuty Istiod nie odrzucił żadnej konfiguracji!)"
  else
    echo "$LOGS" | tail -30
  fi
else
  echo "(nie znaleziono poda istiod - pomijam)"
fi