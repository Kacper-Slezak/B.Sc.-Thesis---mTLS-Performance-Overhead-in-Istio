  #!/bin/bash
  set -e
  set -e pipefail

  YELLOW='\033[1;33m'
  GREEN='\033[1;32m'
  RED='\033[0;31m'
  NC='\033[0m'

  echo -e "${YELLOW}1. Deleting old cluster (if it exists)...${NC}"
  k3d cluster delete thesis-cluster || true

  echo -e "${YELLOW}2. Creating a new cluster 'thesis-cluster'...${NC}"
  k3d cluster create thesis-cluster --api-port 6550 --k3s-arg "--disable=traefik@server:0" --wait

  echo -e "${YELLOW}3. Fixing host.docker.internal error on Windows...${NC}"
  kubectl config set-cluster k3d-thesis-cluster --server=https://127.0.0.1:6550

  echo -e "${YELLOW}4. Checking connection to the cluster...${NC}"
  kubectl get nodes

  echo -e "${YELLOW}5. Testing internet / registry access from INSIDE the k3d node...${NC}"
  NODE_CONTAINER=$(docker ps --filter "name=k3d-thesis-cluster-server-0" --format "{{.Names}}" | head -n1)

  if [ -z "$NODE_CONTAINER" ]; then
    echo -e "${RED}Nie znaleziono kontenera node'a k3d (k3d-thesis-cluster-server-0). Sprawdź 'docker ps'.${NC}"
    exit 1
  fi

  echo "Node container: $NODE_CONTAINER"

  echo "-> Test DNS (rozwiązywanie nazw) wewnątrz node'a:"
  if ! docker exec "$NODE_CONTAINER" getent hosts docker.io >/dev/null 2>&1; then
    echo -e "${RED}DNS NIE działa wewnątrz node'a k3d - to bardzo częsta przyczyna 'ContainerCreating' na zawsze.${NC}"
    echo "Sprawdź ustawienia sieci Docker Desktop / VPN / firewall."
  else
    echo -e "${GREEN}DNS OK.${NC}"
  fi

  echo "-> Test pobrania warstwy obrazu z Docker Hub (mały obraz testowy):"
  if docker exec "$NODE_CONTAINER" sh -c "wget -q -T 10 -O /dev/null https://registry-1.docker.io/v2/" 2>/dev/null; then
    echo -e "${GREEN}Połączenie z Docker Hub OK.${NC}"
  else
    echo -e "${RED}Node k3d NIE może połączyć się z registry-1.docker.io.${NC}"
    echo "To wygląda na problem z internetem / proxy / firewallem na hoście Docker."
  fi

  echo -e "${GREEN}==========================================${NC}"
  echo -e "${GREEN}Faza 1 zakończona. Klaster stoi i podano wynik testu sieci.${NC}"
  echo -e "${GREEN}Jeśli oba testy wyszły OK -> uruchom fazę 2 (install-istio).${NC}"
  echo -e "${GREEN}Jeśli DNS lub registry NIE działa -> najpierw napraw sieć (patrz komunikaty powyżej).${NC}"

    ISTIO_VERSION="release-1.24"

  echo -e "${YELLOW}0. Sanity check: czy klaster i node są gotowe?${NC}"
  kubectl get nodes

  echo -e "${YELLOW}1. Installing Istio (Profile: MINIMAL)...${NC}"
  istioctl install --set profile=minimal -y

  echo -e "${YELLOW}2. Enabling auto-injection of sidecars (Envoy)...${NC}"
  kubectl label namespace default istio-injection=enabled --overwrite

  echo -e "${YELLOW}3. Installing monitoring tools...${NC}"
  kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/prometheus.yaml"
  kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/grafana.yaml"
  kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/kiali.yaml"

  echo -e "${YELLOW}4. Deploying HTTPBIN application (Server)...${NC}"
  kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/httpbin/httpbin.yaml"
  kubectl patch deployment httpbin --type=merge \
    -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/statsInclusionRegexps": ".*ssl.*,.*tls.*"}}}}}'
  # UWAGA: obraz "docker.io/kong/httpbin" bez taga (czyli :latest = 0.2.0) ma znany,
  # upstream'owy bug - gunicorn nie jest zainstalowany w venv, przez co kontener
  # wchodzi w CrashLoopBackOff z błędem "gunicorn could not be found within PATH".
  # Zob. https://github.com/istio/istio/issues/53510 oraz Kong/httpbin#60/#62.
  # Fix: przypinamy działający tag 0.1.0.
  echo "Patching httpbin image to a working tag (0.2.0 is broken upstream)..."
  kubectl set image deployment/httpbin httpbin=docker.io/kong/httpbin:0.1.0

  echo -e "${YELLOW}5. Deploying K6 tool (Client)...${NC}"
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

  echo -e "${YELLOW}6. Configuring Grafana Image Renderer Plugin...${NC}"
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
    echo "Warning: Could not find Grafana pod. Skipping plugin check."
  fi

  echo -e "${YELLOW}7. Waiting for httpbin and k6 pods to become ready...${NC}"
  if ! kubectl rollout status deployment/httpbin -n default --timeout=240s; then
    echo -e "${YELLOW}httpbin rollout nie zakończył się w czasie - diagnostyka:${NC}"
    kubectl get pods -n default -l app=httpbin -o wide
    kubectl describe pods -n default -l app=httpbin | tail -40
    exit 1
  fi

  if ! kubectl rollout status deployment/k6-deploy -n default --timeout=240s; then
    echo -e "${YELLOW}k6-deploy rollout nie zakończył się w czasie - diagnostyka:${NC}"
    kubectl get pods -n default -l app=k6 -o wide
    kubectl describe pods -n default -l app=k6 | tail -40
    exit 1
  fi

  echo -e "${GREEN}==========================================${NC}"
  echo -e "${GREEN}Environment ready! All resources and plugins are configured.${NC}"
  echo -e "${GREEN}Check their status by running: kubectl get pods -A${NC}"