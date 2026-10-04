#!/bin/bash
set -e

# ==============================================================================
# End-to-end benchmark workflow runner
# ==============================================================================
# Sets up k3d cluster and Istio if needed, checks pod readiness,
# verifies cipher negotiation, runs the benchmark battery, and launches Grafana.
# ==============================================================================

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")" && pwd))"
cd "$REPO_ROOT"

TEST_SUITE="${TEST_SUITE:-basic}"
N_RUNS="${N_RUNS:-5}"
SKIP_CLUSTER_SETUP="${SKIP_CLUSTER_SETUP:-false}"

echo "========================================================================"
echo "Starting end-to-end benchmark workflow"
echo "  Test suite:          $TEST_SUITE"
echo "  Iterations (N_RUNS): $N_RUNS"
echo "  Skip cluster setup:  $SKIP_CLUSTER_SETUP"
echo "========================================================================"

mkdir -p ./04_results/Archive

# Phase 1: Cluster initialization
if [ "$SKIP_CLUSTER_SETUP" = "true" ]; then
  echo "Skipping cluster setup (SKIP_CLUSTER_SETUP=true)."
else
  if kubectl get pod -l app=httpbin >/dev/null 2>&1 && kubectl get pod -l app=k6 >/dev/null 2>&1; then
    echo "Found running httpbin and k6 pods in cluster."
    read -r -t 10 -p "Recreate cluster from scratch? [y/N] (auto-skip in 10s): " RECREATE || true
    echo ""
    if [[ "$RECREATE" =~ ^[yY]$ ]]; then
      echo "Recreating cluster via setup_cluster.sh..."
      ./01_scripts/setup_cluster.sh
    else
      echo "Continuing with existing cluster."
    fi
  else
    echo "Initializing new cluster (k3d + Istio + test pods)..."
    ./01_scripts/setup_cluster.sh
  fi
fi

# Phase 2: Wait for workload readiness
echo "Waiting for httpbin and k6 pods to become ready..."
kubectl wait --for=condition=ready pod -l app=httpbin --timeout=180s
kubectl wait --for=condition=ready pod -l app=k6 --timeout=180s

K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")
echo "  K6 pod:      $K6_POD"
echo "  HTTPBin pod: $HTTPBIN_POD"

# Phase 3: Verify cipher negotiation
echo "Verifying TLS cipher negotiation on Envoy proxies..."
./01_scripts/verify_ciphers.sh || echo "Warning: verify_ciphers reported warnings, proceeding with tests..."

# Phase 4: Run benchmark battery
echo "Running benchmarks..."
if [ "$TEST_SUITE" = "all" ]; then
  echo "Running full exploratory test battery from test_trying/..."
  N_RUNS=$N_RUNS ./test_trying/run_all_test_v2.sh
else
  echo "Running core thesis baseline test suite..."
  N_RUNS=$N_RUNS ./run_basic_test.sh
fi

# Phase 5: Open Grafana dashboard
echo "Starting port-forward to Grafana..."
pkill -f "port-forward svc/grafana" || true
kubectl port-forward svc/grafana 3000:3000 -n istio-system > /dev/null 2>&1 &

sleep 3

if command -v xdg-open > /dev/null 2>&1; then
  xdg-open "http://localhost:3000" 2>/dev/null || true
elif command -v open > /dev/null 2>&1; then
  open "http://localhost:3000" 2>/dev/null || true
else
  echo "Grafana dashboard available at: http://localhost:3000"
fi

echo "========================================================================"
echo "Benchmark workflow completed."
echo "Results saved in ./04_results/Summary"
echo "========================================================================"
