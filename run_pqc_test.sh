#!/bin/bash
set -e

# Lista krzywych do przetestowania (od najnowszych standardów po starsze eksperymenty)
CURVES=("X25519MLKEM768" "X25519Kyber768Draft00" "CECPQ2")

echo "=== Rozpoczęcie automatycznego skanowania wsparcia PQC w Istio ==="

for CURVE in "${CURVES[@]}"; do
    echo -e "\n--------------------------------------------------"
    echo "🧪 TESTOWANA KRZYWA: ${CURVE}"
    echo "--------------------------------------------------"
    
    # 1. Czyszczenie
    kubectl delete envoyfilter force-pqc-client force-pqc-server -n default 2>/dev/null || true
    
    # 2. Aplikowanie filtra tylko dla tej jednej krzywej
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

    echo "⏳ Oczekiwanie na propagację konfiguracji (15s)..."
    sleep 15
    
    echo "🚀 Uruchamianie k6 (5 zapytań)..."
    # Uruchamiamy k6 z grepem, aby złapać tylko linie informujące o błędach lub sukcesie
    kubectl exec -n default deploy/k6-deploy -- sh -c 'echo "import http from \"k6/http\"; export default function() { http.get(\"http://httpbin:8000/get\", {headers: {\"Connection\": \"close\"}}); }" > /tmp/pqc_quick.js && k6 run --vus 1 --iterations 5 /tmp/pqc_quick.js' > /tmp/k6_out.txt 2>&1 || true
    
    # Analiza wyników
    if grep -q "http_req_failed......: 100.00%" /tmp/k6_out.txt; then
        echo "❌ WYNIK: Envoy ODRZUCIŁ krzywą ${CURVE} (Brak wsparcia w tej kompilacji Istio)"
    elif grep -q "http_req_failed......: 0.00%" /tmp/k6_out.txt; then
        echo "✅ WYNIK: SUKCES! Envoy akceptuje krzywą ${CURVE}. Mamy połączenie PQC!"
        kubectl exec -n default deploy/httpbin -c istio-proxy -- curl -s localhost:15000/stats | grep -E "ssl\.curves" || true
    else
        echo "⚠️ WYNIK: Nieznany błąd. Sprawdź logi proxy."
    fi
done

echo -e "\n=== Sprzątanie po testach ==="
kubectl delete envoyfilter force-pqc-client force-pqc-server -n default 2>/dev/null || true
echo "Gotowe."