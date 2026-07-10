#!/bin/bash

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
NC='\033[0m' # No Color

echo -e "${YELLOW}1. Usuwanie starego klastra (jeśli istnieje)...${NC}"
k3d cluster delete inzynierka || true

echo -e "${YELLOW}2. Tworzenie nowego klastra 'inzynierka'...${NC}"
k3d cluster create inzynierka --api-port 6550 --k3s-arg "--disable=traefik@server:0" --wait

echo -e "${YELLOW}3. Naprawianie błędu host.docker.internal na Windowsie...${NC}"
kubectl config set-cluster k3d-inzynierka --server=https://127.0.0.1:6550

echo -e "${YELLOW}4. Sprawdzanie połączenia z klastrem...${NC}"
kubectl get nodes

echo -e "${YELLOW}5. Instalacja Istio (Profil: MINIMAL)...${NC}"
istioctl install --set profile=minimal -y

echo -e "${YELLOW}6. Włączanie auto-wstrzykiwania sidecarów (Envoy)...${NC}"
kubectl label namespace default istio-injection=enabled --overwrite

echo -e "${YELLOW}7. Instalacja narzędzi monitorujących...${NC}"
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/addons/grafana.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/addons/kiali.yaml

echo -e "${YELLOW}8. Wdrażanie aplikacji HTTPBIN (Serwer)...${NC}"
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/httpbin/httpbin.yaml

echo -e "${YELLOW}9. Wdrażanie narzędzia K6 (Klient)...${NC}"
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
        command: ["tail", "-f", "/dev/null"] # Komenda utrzymująca kontener przy życiu
EOF

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Środowisko gotowe! Poczekaj około minuty, aż pody wstaną.${NC}"
echo -e "${GREEN}Sprawdź ich status wpisując: kubectl get pods${NC}"