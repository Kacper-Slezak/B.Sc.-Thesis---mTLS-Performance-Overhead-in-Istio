#!/bin/bash

echo -e "Delete old cluster (if it exists)"
k3d cluster delete inzynierka || true

echo -e "Create new cluster 'inzynierka'"
k3d cluster create inzynierka --api-port 6550 --k3s-arg "--disable=traefik@server:0" --wait

echo -e "Checking connection to the cluster"
kubectl get nodes

echo -e "Installing Istio (Profile: MINIMAL)"}"
istioctl install --set profile=minimal -y

echo -e "Enabling auto-injection of sidecars (Envoy)"
kubectl label namespace default istio-injection=enabled --overwrite

echo -e "Installing monitoring tools (Prometheus, Grafana, Kiali)"
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/addons/grafana.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/addons/kiali.yaml

echo -e "Deploying HTTPBIN application (Server)"
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/httpbin/httpbin.yaml

echo -e "Deploying K6 tool (Client)"
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
        command: ["tail", "-f", "/dev/null"]
EOF

echo -e "Kubernetes cluster 'inzynierka' is set up and ready to use!"
