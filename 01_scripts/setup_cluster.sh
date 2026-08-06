#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
NC='\033[0m' # No Color

echo -e "${YELLOW}1. Deleting old cluster (if it exists)...${NC}"
k3d cluster delete thesis-cluster || true

echo -e "${YELLOW}2. Creating a new cluster 'thesis-cluster'...${NC}"
k3d cluster create thesis-cluster --api-port 6550 --k3s-arg "--disable=traefik@server:0" --wait

echo -e "${YELLOW}3. Fixing host.docker.internal error on Windows...${NC}"
kubectl config set-cluster k3d-thesis-cluster --server=https://127.0.0.1:6550

echo -e "${YELLOW}4. Checking connection to the cluster...${NC}"
kubectl get nodes

echo -e "${YELLOW}5. Installing Istio (Profile: MINIMAL)...${NC}"
istioctl install --set profile=minimal -y

echo -e "${YELLOW}6. Enabling auto-injection of sidecars (Envoy)...${NC}"
kubectl label namespace default istio-injection=enabled --overwrite

echo -e "${YELLOW}7. Installing monitoring tools...${NC}"
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/addons/grafana.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/addons/kiali.yaml

echo -e "${YELLOW}8. Deploying HTTPBIN application (Server)...${NC}"
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/httpbin/httpbin.yaml

echo -e "${YELLOW}9. Deploying K6 tool (Client)...${NC}"
cat <<EOF | kubectl apply -f -
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
        command: ["tail", "-f", "/dev/null"] # Keep-alive command to hold the container running
EOF
echo -e "${YELLOW}10. Configuring Grafana Image Renderer Plugin...${NC}"
echo "Waiting for Grafana deployment to roll out and spin up pods..."

# Profesjonalne czekanie na gotowość całego Deploymentu zamiast szukania podów po etykietach
kubectl rollout status deployment/grafana -n istio-system --timeout=180s

echo "Grafana deployment is ready. Fetching active pod name..."
GRAFANA_POD=$(kubectl get pods -n istio-system -l app=grafana -o jsonpath="{.items[0].metadata.name}" || echo "")

if [ -n "$GRAFANA_POD" ]; then
  echo "Checking if grafana-image-renderer is already installed..."
  if kubectl exec -n istio-system "$GRAFANA_POD" -c grafana -- grafana-cli plugins ls | grep -q "grafana-image-renderer"; then
    echo "Plugin grafana-image-renderer is already installed."
  else
    echo "Plugin not found. Installing grafana-image-renderer inside the Grafana pod..."
    kubectl exec -n istio-system "$GRAFANA_POD" -c grafana -- grafana-cli --timeout 60s plugins install grafana-image-renderer
    
    echo "Restarting Grafana pod to apply changes..."
    kubectl delete pod -n istio-system "$GRAFANA_POD"
    
    echo "Waiting for the new Grafana pod to become fully ready again..."
    kubectl rollout status deployment/grafana -n istio-system --timeout=180s
  fi
else
  echo "Warning: Could not find Grafana pod in istio-system namespace. Skipping plugin check."
fi

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Environment ready! All resources and plugins are configured.${NC}"
echo -e "${GREEN}Check their status by running: kubectl get pods -A${NC}"