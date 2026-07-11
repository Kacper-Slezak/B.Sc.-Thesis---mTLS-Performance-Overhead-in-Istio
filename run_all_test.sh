#!/bin/bash
set -e

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "Creating result directories..."
mkdir -p ./04_results/Summary
mkdir -p ./04_results/RawLogs

K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
echo "Detected K6 pod: $K6_POD"

# Function to run a specific test profile
run_test_profile() {
  local SETUP_NAME=$1
  local TEST_TYPE=$2
  
  # Format: raw_SETUP_TESTTYPE_TIMESTAMP.json
  local FILE_PREFIX="${SETUP_NAME}_${TEST_TYPE}_${TIMESTAMP}"

  echo "Starting test profile: [${TEST_TYPE}] for setup: [${SETUP_NAME}]"
  
  cat ./03_test_scripts/main_k6_scenarios.js | kubectl exec -i $K6_POD -c k6 -- k6 run -e TEST_TYPE=${TEST_TYPE} --out json=/tmp/raw.json -
  
  echo "Downloading results for ${FILE_PREFIX}..."
  kubectl cp $K6_POD:/tmp/raw.json ./04_results/RawLogs/raw_${FILE_PREFIX}.json -c k6
  kubectl cp $K6_POD:/tmp/summary.json ./04_results/Summary/summary_${FILE_PREFIX}.json -c k6
  echo "Completed: ${FILE_PREFIX}"
  echo "----------------------------------------"
  sleep 5
}

# ==========================================
# SETUP 1: mTLS 1.3 (Istio Default)
# ==========================================
echo "=== BEGIN SETUP 1: mTLS 1.3 (Default) ==="
# Remove any existing EnvoyFilters to ensure default Istio behavior
kubectl delete envoyfilter --all -n default || true
echo "Waiting 10s for default configuration propagation..."
sleep 10

run_test_profile "mtls1.3-default" "baseline"
run_test_profile "mtls1.3-default" "payload"
run_test_profile "mtls1.3-default" "stress"

# ==========================================
# SETUP 2: mTLS 1.2 with AES-GCM
# ==========================================
echo "=== BEGIN SETUP 2: mTLS 1.2 (AES-GCM) ==="
kubectl delete envoyfilter --all -n default || true
kubectl apply -f ./02_manifests/envoyfilter_gcm.yaml

echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
sleep 15
kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-gcm_${TIMESTAMP}.yaml

run_test_profile "mtls1.2-gcm" "baseline"
run_test_profile "mtls1.2-gcm" "payload"
run_test_profile "mtls1.2-gcm" "stress"

# ==========================================
# SETUP 3: mTLS 1.2 with ChaCha20
# ==========================================
echo "=== BEGIN SETUP 3: mTLS 1.2 (ChaCha20) ==="
kubectl delete envoyfilter --all -n default || true
kubectl apply -f ./02_manifests/envoyfilter_chacha.yaml

echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
sleep 15
kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-chacha_${TIMESTAMP}.yaml

run_test_profile "mtls1.2-chacha" "baseline"
run_test_profile "mtls1.2-chacha" "payload"
run_test_profile "mtls1.2-chacha" "stress"

# ==========================================
# SETUP 4: mTLS 1.2 with AES-CBC
# ==========================================
echo "=== BEGIN SETUP 4: mTLS 1.2 (AES-CBC) ==="
kubectl delete envoyfilter --all -n default || true
kubectl apply -f ./02_manifests/envoyfilter_cbc.yaml

echo "Waiting 15 seconds for Envoy proxy configuration propagation..."
sleep 15
kubectl get envoyfilter -n default -o yaml > ./04_results/Summary/envoy_proof_mtls1.2-cbc_${TIMESTAMP}.yaml

run_test_profile "mtls1.2-cbc" "baseline"
run_test_profile "mtls1.2-cbc" "payload"
run_test_profile "mtls1.2-cbc" "stress"

echo "=== ALL TESTS COMPLETED SUCCESSFULLY ==="