#!/bin/bash
# ==========================================================================
# verify_ciphers.sh (v2 - poprawiony)
#
# CEL: Zanim odpalisz 40-minutowa baterie testow k6, sprawdz w 2 minuty
# czy kazdy z 5 setupow FAKTYCZNIE negocjuje to, co jest w opisie raportu.
#
# CO BYLO NAPRAWIONE WZGLEDEM v1:
#   1. Tabela SETUPS uzywala 'IFS="|" read' do parsowania, ale regex
#      "TLS_AES_(128|256)_GCM" sam zawiera znak '|' - kolidowalo to z
#      delimiterem i lamalo caly regex (stad "grep: Unmatched (").
#      FIX: cztery osobne tablice rownolegle zamiast jednego stringa
#      dzielonego po '|' - zero konfliktu ze znakami specjalnymi w regexach.
#   2. Dopasowanie krzywej uzywalo kotwicy '$' myslac ze zakotwiczy koniec
#      NAZWY krzywej ("X25519$"), ale linia stat ma postac
#      "ssl.curves.X25519: 703248" - '$' kotwiczy do konca CALEJ linii,
#      wiec nigdy nie trafialo. FIX: kotwiczenie do dwukropka zaraz po
#      nazwie ("ssl\.curves\.X25519:"), co poprawnie odroznia X25519 od
#      X25519MLKEM768 (bo to drugie nie ma ':' zaraz po "X25519").
#
# WAZNE OGRANICZENIE ENVOYA (bez zmian wzgledem v1): pole `cipher_suites`
# w tls_params dziala TYLKO dla TLS 1.2. Dla TLS 1.3 Envoy/BoringSSL sam
# wybiera z ustalonej listy wg oferty klienta - nie da sie tego wymusic
# przez cipher_suites tak jak dla 1.2. Ten skrypt Ci powie czy to w ogole
# ma znaczenie dla Twojego porownania (patrz podsumowanie na koncu).
#
# UZYCIE:
#   chmod +x verify_ciphers.sh
#   ./verify_ciphers.sh
# ==========================================================================
set -uo pipefail

NAMESPACE="default"
MANIFEST_DIR="./02_manifests"
RESULTS_DIR="./04_results/Summary"
mkdir -p "$RESULTS_DIR"

K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
if [ -z "$K6_POD" ]; then
  echo "BLAD: nie znaleziono poda k6 (label app=k6). Sprawdz kubectl context." >&2
  exit 1
fi

# ---- cztery rownolegle tablice zamiast jednego dzielonego stringa ----
NAMES=(
  "mtls1.3-default"
  "mtls1.2-gcm"
  "mtls1.2-chacha"
  "mtls1.2-cbc"
  "mtls1.3-postquantum"
)
MANIFESTS=(
  ""
  "${MANIFEST_DIR}/envoyfilter_gcm.yaml"
  "${MANIFEST_DIR}/envoyfilter_chacha.yaml"
  "${MANIFEST_DIR}/envoyfilter_cbc.yaml"
  "__PQC__"
)
# regex NAZWY ciphera (bez kotwicy koncowej - dokladamy ':' w funkcji check_cipher)
EXPECTED_CIPHERS=(
  "TLS_AES_(128|256)_GCM_SHA(256|384)"
  "ECDHE-RSA-AES128-GCM-SHA256"
  "ECDHE-RSA-CHACHA20-POLY1305"
  "ECDHE-RSA-AES128-SHA256"
  "TLS_AES_(128|256)_GCM_SHA(256|384)"
)
# doslowna nazwa krzywej (bez regexowych znakow specjalnych - dopasowanie
# scisle przez kotwiczenie do ':' w funkcji check_curve)
EXPECTED_CURVES=(
  "X25519"
  "X25519"
  "X25519"
  "X25519"
  "X25519MLKEM768"
)

PQC_MANIFEST=$(mktemp)
cat > "$PQC_MANIFEST" <<'EOF'
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
                ecdh_curves: ["X25519MLKEM768", "X25519Kyber768Draft00", "X25519"]
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
                ecdh_curves: ["X25519MLKEM768", "X25519Kyber768Draft00", "X25519"]
EOF

# Sprawdza czy cipher o danej NAZWIE (regex dozwolony) MIAL PRZYROST licznika
# miedzy stanem przed a po wygenerowaniu ruchu w TYM setupie. To jest wazna
# roznica wzgledem samego ">0": liczniki w /stats sa KUMULATYWNE od startu
# poda i nigdy sie nie zeruja miedzy setupami - wiec sam fakt ze cipher X
# ma wartosc >0 nic nie mowi po pierwszym secie ktory go uzyl. Trzeba
# sprawdzic PRZYROST wlasnie w oknie tego konkretnego testu.
check_delta() {
  local before_file="$1" after_file="$2" name_regex="$3" stat_type="$4" # ciphers|curves
  local found=1
  while IFS= read -r line; do
    local key="${line%%:*}"
    local after_val="${line#*: }"
    local before_val
    before_val=$(awk -F': ' -v k="$key" '$1==k {print $2; exit}' "$before_file")
    [ -z "$before_val" ] && before_val=0
    if [ "$after_val" -gt "$before_val" ] 2>/dev/null; then
      found=0
    fi
  done < <(grep -E "ssl\.${stat_type}\.(${name_regex}):" "$after_file")
  return $found
}

echo "================================================================"
echo " WERYFIKACJA RZECZYWISTYCH PARAMETROW TLS - 5 setupow"
echo "================================================================"

declare -A FAILS=()

for i in "${!NAMES[@]}"; do
  NAME="${NAMES[$i]}"
  MANIFEST="${MANIFESTS[$i]}"
  EXPECTED_CIPHER="${EXPECTED_CIPHERS[$i]}"
  EXPECTED_CURVE="${EXPECTED_CURVES[$i]}"

  echo ""
  echo "--- Setup: $NAME ---"
  kubectl delete envoyfilter --all -n "$NAMESPACE" >/dev/null 2>&1 || true

  if [ "$MANIFEST" = "__PQC__" ]; then
    kubectl apply -f "$PQC_MANIFEST" >/dev/null
  elif [ -n "$MANIFEST" ]; then
    kubectl apply -f "$MANIFEST" >/dev/null
  fi

  echo "Czekam 12s na propagacje konfiguracji..."
  sleep 12

  HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)

  STATS_BEFORE_FILE=$(mktemp)
  kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats 2>/dev/null \
    | grep -i -E "ssl\.(ciphers|curves)" > "$STATS_BEFORE_FILE"

  echo "import http from 'k6/http'; export default function() { http.get('http://httpbin.default.svc.cluster.local:8000/get'); }" | \
    kubectl exec -i "$K6_POD" -c k6 -- k6 run --vus 5 --duration 8s - >/dev/null 2>&1 || true

  STATS_AFTER_FILE=$(mktemp)
  kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats 2>/dev/null \
    | grep -i -E "ssl\.(ciphers|curves)" > "$STATS_AFTER_FILE"

  echo "--- stan PO (kumulatywny, dla wgladu): ---"
  cat "$STATS_AFTER_FILE" | tee "${RESULTS_DIR}/verify_${NAME}.txt"

  CIPHER_OK="NIE"; CURVE_OK="NIE"
  if check_delta "$STATS_BEFORE_FILE" "$STATS_AFTER_FILE" "$EXPECTED_CIPHER" "ciphers"; then CIPHER_OK="TAK"; fi
  if check_delta "$STATS_BEFORE_FILE" "$STATS_AFTER_FILE" "$EXPECTED_CURVE" "curves"; then CURVE_OK="TAK"; fi
  rm -f "$STATS_BEFORE_FILE" "$STATS_AFTER_FILE"

  echo ">>> Oczekiwany cipher mial PRZYROST licznika w tym oknie: $CIPHER_OK"
  echo ">>> Oczekiwana krzywa miala PRZYROST licznika w tym oknie: $CURVE_OK"

  if [ "$CIPHER_OK" != "TAK" ] || [ "$CURVE_OK" != "TAK" ]; then
    FAILS["$NAME"]="cipher_ok=$CIPHER_OK curve_ok=$CURVE_OK"
  fi
done

kubectl delete envoyfilter --all -n "$NAMESPACE" >/dev/null 2>&1 || true
rm -f "$PQC_MANIFEST"

echo ""
echo "================================================================"
echo " PODSUMOWANIE"
echo "================================================================"
if [ ${#FAILS[@]} -eq 0 ]; then
  echo "Wszystkie setupy negocjuja to, co powinny. Mozna odpalac pelna baterie."
else
  echo "UWAGA - te setupy NIE zgadzaja sie z oczekiwaniami:"
  for k in "${!FAILS[@]}"; do
    echo "  - $k: ${FAILS[$k]}"
  done
  echo ""
  echo "Jesli na liscie sa TYLKO mtls1.3-default i mtls1.3-postquantum z"
  echo "cipher_ok=NIE - to nie jest blad skryptu ani configu, tylko realne"
  echo "ograniczenie: TLS 1.3 w Envoy/BoringSSL NIE pozwala wymusic ciphera"
  echo "przez 'cipher_suites' (dziala tylko dla TLS 1.2). Musisz to opisac"
  echo "w pracy jako swiadome ograniczenie eksperymentu, nie ukrywac."
  echo ""
  echo "Jesli curve_ok=NIE wystepuje TEZ dla setupow 1.2 (gcm/chacha/cbc),"
  echo "ktore w ogole nie powinny dotykac krzywej PQC - to bylby prawdziwy"
  echo "problem (znaczyloby ze klient mimo wszystko oferuje X25519MLKEM768"
  echo "i serwer/proxy to akceptuje mimo wymuszonego TLS 1.2 - sprawdz czy"
  echo "EnvoyFilter faktycznie wymusza tls_maximum_protocol_version=TLSv1_2"
  echo "po obu stronach)."
fi