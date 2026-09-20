#!/bin/bash
# ==========================================================================
# verify_ciphers.sh
# Verifies actual negotiated TLS cipher suites and elliptic curves
# across all evaluated Istio Envoy proxy configurations using live telemetry.
# ==========================================================================
set -uo pipefail

NAMESPACE="default"
MANIFEST_DIR="./02_manifests"
RESULTS_DIR="./04_results/Summary"
mkdir -p "$RESULTS_DIR"

K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
if [ -z "$K6_POD" ]; then
  echo "ERROR: k6 pod not found (label app=k6). Verify kubectl cluster context." >&2
  exit 1
fi
echo "Info: K6_POD=$K6_POD"

# ---- Test setup definitions (6 TLS configurations) ----
NAMES=(
  "mtls1.3-default"
  "mtls1.2-gcm"
  "mtls1.2-gcm256"
  "mtls1.2-chacha"
  "mtls1.2-cbc"
  "mtls1.3-postquantum"
)

MANIFESTS=(
  ""
  "${MANIFEST_DIR}/envoyfilter_gcm.yaml"
  "${MANIFEST_DIR}/envoyfilter_gcm256.yaml"
  "${MANIFEST_DIR}/envoyfilter_chacha.yaml"
  "${MANIFEST_DIR}/envoyfilter_cbc.yaml"
  "${MANIFEST_DIR}/envoyfilter_pqc.yaml"
)

EXPECTED_CIPHERS=(
  "TLS_AES_(128|256)_GCM_SHA(256|384)"
  "ECDHE-RSA-AES128-GCM-SHA256"
  "ECDHE-RSA-AES256-GCM-SHA384"
  "ECDHE-RSA-CHACHA20-POLY1305"
  "ECDHE-RSA-AES128-SHA256"
  "TLS_AES_(128|256)_GCM_SHA(256|384)"
)

EXPECTED_CURVES=(
  "X25519"
  "X25519"
  "X25519"
  "X25519"
  "X25519"
  "X25519MLKEM768"
)

# Checks whether a specific cipher or curve counter incremented (delta > 0)
# within the measurement window between before and after snapshots.
check_delta() {
  local before_file="$1" after_file="$2" name_regex="$3" stat_type="$4"
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
echo " TLS PARAMETER VERIFICATION (${#NAMES[@]} setups)"
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

  if [ -n "$MANIFEST" ]; then
    echo "Applying EnvoyFilter: $MANIFEST"
    kubectl apply -f "$MANIFEST" >/dev/null
  fi

  echo "Waiting 12s for Envoy configuration propagation..."
  sleep 12

  HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
  if [ -z "$HTTPBIN_POD" ]; then
    echo "ERROR: httpbin pod not found - skipping setup." >&2
    continue
  fi

  STATS_BEFORE_FILE=$(mktemp)
  kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats 2>/dev/null \
    | grep -i -E "ssl\.(ciphers|curves)" > "$STATS_BEFORE_FILE"

  echo "Generating diagnostic traffic (5 VUs / 8s) via k6..."
  K6_WARMUP_LOG=$(mktemp)
  echo "import http from 'k6/http'; export default function() { http.get('http://httpbin.default.svc.cluster.local:8000/get'); }" | \
    kubectl exec -i "$K6_POD" -c k6 -- k6 run --vus 5 --duration 8s - > "$K6_WARMUP_LOG" 2>&1
  K6_EXIT=$?
  
  if [ $K6_EXIT -ne 0 ]; then
    echo "WARNING: k6 run exited with code $K6_EXIT (cipher negotiation may have failed)." >&2
  else
    grep -E "http_reqs|iterations" "$K6_WARMUP_LOG" || echo "  (Warning: no http_reqs line in k6 output)"
  fi
  rm -f "$K6_WARMUP_LOG"

  STATS_AFTER_FILE=$(mktemp)
  kubectl exec "$HTTPBIN_POD" -c istio-proxy -- curl -s localhost:15000/stats 2>/dev/null \
    | grep -i -E "ssl\.(ciphers|curves)" > "$STATS_AFTER_FILE"

  echo "--- Cumulative telemetry stats after run: ---"
  cat "$STATS_AFTER_FILE" | tee "${RESULTS_DIR}/verify_${NAME}.txt"

  CIPHER_OK="FAIL"; CURVE_OK="FAIL"
  if check_delta "$STATS_BEFORE_FILE" "$STATS_AFTER_FILE" "$EXPECTED_CIPHER" "ciphers"; then CIPHER_OK="PASS"; fi
  if check_delta "$STATS_BEFORE_FILE" "$STATS_AFTER_FILE" "$EXPECTED_CURVE" "curves"; then CURVE_OK="PASS"; fi
  rm -f "$STATS_BEFORE_FILE" "$STATS_AFTER_FILE"

  echo ">>> Expected cipher counter incremented in test window: $CIPHER_OK"
  echo ">>> Expected curve counter incremented in test window:  $CURVE_OK"

  if [ "$CIPHER_OK" != "PASS" ] || [ "$CURVE_OK" != "PASS" ]; then
    FAILS["$NAME"]="cipher_ok=$CIPHER_OK curve_ok=$CURVE_OK"
  fi
done

kubectl delete envoyfilter --all -n "$NAMESPACE" >/dev/null 2>&1 || true

echo ""
echo "================================================================"
echo " VERIFICATION SUMMARY"
echo "================================================================"
if [ ${#FAILS[@]} -eq 0 ]; then
  echo "All setups negotiated the expected cryptographic algorithms. Ready for benchmark execution!"
else
  echo "WARNING: The following setups did not match expectations (inspect logs for details):"
  for k in "${!FAILS[@]}"; do
    echo "  - $k: ${FAILS[$k]}"
  done
fi
