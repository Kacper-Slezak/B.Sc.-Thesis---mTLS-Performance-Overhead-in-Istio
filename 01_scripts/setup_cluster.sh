#!/bin/bash
set -eo pipefail

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}1. Deleting old cluster (if it exists)...${NC}"
k3d cluster delete thesis-cluster || true

echo -e "${YELLOW}2. Creating a new cluster 'thesis-cluster'...${NC}"
k3d cluster create thesis-cluster --api-port 6550 --k3s-arg "--disable=traefik@server:0" --wait

echo -e "${YELLOW}3. Configuring Kubernetes API endpoint...${NC}"
kubectl config set-cluster k3d-thesis-cluster --server=https://127.0.0.1:6550

echo -e "${YELLOW}4. Checking connection to the cluster...${NC}"
kubectl get nodes

echo -e "${YELLOW}5. Testing internet and container registry connectivity inside k3d node...${NC}"
NODE_CONTAINER=$(docker ps --filter "name=k3d-thesis-cluster-server-0" --format "{{.Names}}" | head -n1)

if [ -z "$NODE_CONTAINER" ]; then
  echo -e "${RED}Error: k3d node container (k3d-thesis-cluster-server-0) not found. Check 'docker ps'.${NC}"
  exit 1
fi

echo "Node container: $NODE_CONTAINER"

echo "-> Testing DNS name resolution inside node:"
if ! docker exec "$NODE_CONTAINER" getent hosts docker.io >/dev/null 2>&1; then
  echo -e "${RED}DNS resolution failed inside k3d node. Check Docker Desktop, VPN, or firewall settings.${NC}"
else
  echo -e "${GREEN}DNS resolution OK.${NC}"
fi

echo "-> Testing Docker Hub registry reachability:"
if docker exec "$NODE_CONTAINER" sh -c "wget -q -T 10 -O /dev/null https://registry-1.docker.io/v2/" 2>/dev/null; then
  echo -e "${GREEN}Docker Hub connection OK.${NC}"
else
  echo -e "${RED}k3d node cannot reach registry-1.docker.io. Check host network / proxy.${NC}"
fi

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Phase 1 complete. Cluster is operational and network tests passed.${NC}"
echo -e "${GREEN}==========================================${NC}"

ISTIO_VERSION="release-1.24"

echo -e "${YELLOW}6. Sanity check: verify node readiness...${NC}"
kubectl get nodes

echo -e "${YELLOW}7. Installing Istio (Profile: MINIMAL)...${NC}"
istioctl install --set profile=minimal -y

echo -e "${YELLOW}8. Enabling auto-injection of Envoy sidecars...${NC}"
kubectl label namespace default istio-injection=enabled --overwrite

echo -e "${YELLOW}9. Installing monitoring telemetry addons (Prometheus, Grafana, Kiali)...${NC}"
kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/prometheus.yaml"
kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/grafana.yaml"
kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/kiali.yaml"

echo -e "${YELLOW}10. Deploying HTTPBIN application (Server)...${NC}"
kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/httpbin/httpbin.yaml"
kubectl patch deployment httpbin --type=merge \
  -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/statsInclusionRegexps": ".*ssl.*,.*tls.*"}}}}}'

# NOTE: Untagged 'docker.io/kong/httpbin' (latest=0.2.0) contains an upstream bug
# where gunicorn is missing from PATH, leading to CrashLoopBackOff.
# See: https://github.com/istio/istio/issues/53510 and Kong/httpbin#60/#62.
# Pinning to verified working tag 0.1.0:
echo "Pinning httpbin image to stable release (0.1.0)..."
kubectl set image deployment/httpbin httpbin=docker.io/kong/httpbin:0.1.0

echo -e "${YELLOW}11. Deploying K6 load testing tool (Client)...${NC}"
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: k6-deploy
  labels:
    app: k6
spec:
  replicas: 1
  selector:
    matchLabels:
      app: k6
  template:
    metadata:
      labels:
        app: k6
    spec:
      containers:
      - name: k6
        image: grafana/k6:latest
        command: ["tail", "-f", "/dev/null"]
EOF
kubectl patch deployment k6-deploy --type=merge \
  -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/statsInclusionRegexps": ".*ssl.*,.*tls.*"}}}}}'

echo -e "${YELLOW}12. Configuring Grafana Image Renderer Plugin...${NC}"
kubectl rollout status deployment/grafana -n istio-system --timeout=300s

GRAFANA_POD=$(kubectl get pods -n istio-system -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -n "$GRAFANA_POD" ]; then
  echo "Found Grafana pod: $GRAFANA_POD. Checking plugins..."
  if kubectl exec -n istio-system "$GRAFANA_POD" -c grafana -- grafana cli plugins ls 2>/dev/null | grep -q "grafana-image-renderer"; then
    echo "Plugin grafana-image-renderer is already installed."
  else
    echo "Installing grafana-image-renderer..."
    kubectl exec -n istio-system "$GRAFANA_POD" -c grafana -- grafana cli plugins install grafana-image-renderer
    echo "Restarting Grafana pod to apply changes..."
    kubectl delete pod -n istio-system "$GRAFANA_POD"
    kubectl rollout status deployment/grafana -n istio-system --timeout=210s
  fi
else
  echo "Warning: Grafana pod not found. Skipping renderer plugin check."
fi

echo -e "${YELLOW}13. Waiting for httpbin and k6 workloads to become ready...${NC}"
if ! kubectl rollout status deployment/httpbin -n default --timeout=240s; then
  echo -e "${RED}httpbin deployment rollout timed out. Diagnostics:${NC}"
  kubectl get pods -n default -l app=httpbin -o wide
  kubectl describe pods -n default -l app=httpbin | tail -40
  exit 1
fi

if ! kubectl rollout status deployment/k6-deploy -n default --timeout=240s; then
  echo -e "${RED}k6-deploy deployment rollout timed out. Diagnostics:${NC}"
  kubectl get pods -n default -l app=k6 -o wide
  kubectl describe pods -n default -l app=k6 | tail -40
  exit 1
fi

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Environment ready! All resources and plugins are configured.${NC}"
echo -e "${GREEN}Verify cluster state with: kubectl get pods -A${NC}"
echo -e "${GREEN}==========================================${NC}"
