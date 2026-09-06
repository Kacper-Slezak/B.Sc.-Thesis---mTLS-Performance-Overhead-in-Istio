#!/bin/bash
# ==========================================================================
# diag_mesh.sh
#
# CEL: 800+ udanych requestow, zero ruchu na ssl.ciphers/ssl.curves httpbin.
# To prawie zawsze oznacza jedno z:
#   (a) pod k6 nie ma wstrzykniete sidecara Envoy - EnvoyFilter'y na
#       app=k6 sa wtedy no-opem, ruch leci plaintextem wprost do Service
#   (b) PeerAuthentication jest PERMISSIVE i httpbin akceptuje plaintext
#       rownolegle z mTLS na tym samym porcie - wiec plaintext od klienta
#       bez sidecara przechodzi bez szyfrowania i bez wplywu na ssl stats
#   (c) k6 i httpbin sa w roznych namespace'ach z niespojna injection policy
#
# Ten skrypt tylko CZYTA stan klastra, niczego nie zmienia.
# ==========================================================================
set -uo pipefail

echo "================================================================"
echo " 1. CZY POD K6 MA SIDECAR ISTIO?"
echo "================================================================"
K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
K6_NS=$(kubectl get pod "$K6_POD" -o jsonpath="{.metadata.namespace}" 2>/dev/null)
echo "Pod: $K6_POD (namespace: $K6_NS)"
echo "Kontenery w podzie k6 (.spec.containers):"
kubectl get pod "$K6_POD" -n "$K6_NS" -o jsonpath='{.spec.containers[*].name}{"\n"}'
echo "Init-kontenery w podzie k6 (.spec.initContainers) - TU siedzi sidecar"
echo "w nowszych wersjach Istio z 'native sidecars' (K8s sidecar containers,"
echo "restartPolicy: Always) - takie pody tez pokazuja 2/2 w 'kubectl get pods',"
echo "wiec sprawdzanie samego .spec.containers daje falszywy negatyw:"
kubectl get pod "$K6_POD" -n "$K6_NS" -o jsonpath='{.spec.initContainers[*].name}{"\n"}'
echo "Adnotacja sidecar.istio.io/status (obecna TYLKO jesli sidecar zostal wstrzykniety):"
kubectl get pod "$K6_POD" -n "$K6_NS" -o jsonpath='{.metadata.annotations.sidecar\.istio\.io/status}{"\n"}' || echo "(brak - BRAK SIDECARA)"
echo ""
ALL_CONTAINERS=$(kubectl get pod "$K6_POD" -n "$K6_NS" -o jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}')
if echo "$ALL_CONTAINERS" | grep -q istio-proxy; then
  echo ">>> WYNIK: pod k6 MA sidecar istio-proxy (jako $(echo "$ALL_CONTAINERS" | grep -qw istio-proxy && [ -n "$(kubectl get pod "$K6_POD" -n "$K6_NS" -o jsonpath='{.spec.initContainers[*].name}' | grep istio-proxy)" ] && echo "native sidecar / initContainer" || echo "zwykly container"))."
else
  echo ">>> WYNIK: pod k6 NIE MA sidecara istio-proxy!"
  echo "    To wyjasnia wszystko - Twoje EnvoyFilter'y na 'app: k6' nie maja"
  echo "    czego patchowac (brak Envoya po stronie klienta), a caly ruch"
  echo "    leci plaintextem bezposrednio do Service httpbin."
fi

echo ""
echo "================================================================"
echo " 2. CZY POD HTTPBIN MA SIDECAR ISTIO?"
echo "================================================================"
HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
HTTPBIN_NS=$(kubectl get pod "$HTTPBIN_POD" -o jsonpath="{.metadata.namespace}" 2>/dev/null)
echo "Pod: $HTTPBIN_POD (namespace: $HTTPBIN_NS)"
kubectl get pod "$HTTPBIN_POD" -n "$HTTPBIN_NS" -o jsonpath='{.spec.containers[*].name}{"\n"}'

echo ""
echo "================================================================"
echo " 3. ILE REPLIK MA HTTPBIN? (jesli >1, ruch moze omijac ten pod,"
echo "    ktorego stats sprawdzamy - Service load-balancuje miedzy nimi)"
echo "================================================================"
kubectl get pods -l app=httpbin -n "$HTTPBIN_NS" -o wide

echo ""
echo "================================================================"
echo " 4. TRYB PEERAUTHENTICATION (mTLS enforcement)"
echo "================================================================"
echo "-- Globalny (namespace istio-system, mesh-wide) --"
kubectl get peerauthentication -n istio-system -o yaml 2>/dev/null | grep -E "mode:|name:" || echo "(brak globalnej PeerAuthentication - domyslnie PERMISSIVE)"
echo ""
echo "-- W namespace httpbin ($HTTPBIN_NS) --"
kubectl get peerauthentication -n "$HTTPBIN_NS" -o yaml 2>/dev/null | grep -E "mode:|name:" || echo "(brak PeerAuthentication w tym namespace - dziedziczy globalna/domyslna PERMISSIVE)"

echo ""
echo "================================================================"
echo " 5. PROBNY REQUEST Z JAWNYM SPRAWDZENIEM CZY BYL TLS"
echo "================================================================"
echo "Uruchamiam curl -v z wewnatrz poda k6 (kontener k6, NIE istio-proxy)"
echo "bezposrednio do httpbin - jesli zobaczysz 'SSL connection' albo"
echo "podobne w logu, polaczenie bylo szyfrowane. Jesli nie - plaintext."
kubectl exec "$K6_POD" -n "$K6_NS" -c k6 -- wget -qO- --timeout=5 http://httpbin.default.svc.cluster.local:8000/get 2>&1 | head -c 300 || true
echo ""
echo "(ten request byl HTTP, nie curl -v, bo k6 image czesto nie ma curl -"
echo " ale jesli sie udal bez bledu, to i tak potwierdza plaintext dziala)"

echo ""
echo "================================================================"
echo " PODSUMOWANIE - NA CO PATRZEC"
echo "================================================================"
echo "Jesli w punkcie 1 pod k6 NIE MA istio-proxy -> to jest przyczyna."
echo "Napraw: sprawdz czy namespace w ktorym dziala k6 ma label"
echo "'istio-injection: enabled' (kubectl get ns \$K6_NS --show-labels),"
echo "a jesli deployment k6 powstal PRZED nadaniem tego labelu - trzeba"
echo "go zrestartowac (kubectl rollout restart deployment/<k6-deployment>),"
echo "bo injection dzieje sie tylko przy tworzeniu nowego poda."
echo ""
echo "Jesli k6 MA sidecar, ale PeerAuthentication w punkcie 4 to PERMISSIVE"
echo "(albo brak wpisu = domyslnie PERMISSIVE) - to nadal MOZE tlumaczyc"
echo "sytuacje jesli z jakiegos powodu klient neguje mTLS mimo obecnosci"
echo "sidecara (np. DestinationRule z tls.mode: DISABLE gdzies w tle)."
echo "Sprawdz: kubectl get destinationrule -A -o yaml | grep -A3 'tls:'"