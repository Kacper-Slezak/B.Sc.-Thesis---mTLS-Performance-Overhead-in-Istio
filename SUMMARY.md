# Test Scenarios and Methodology Summary

### Test Scenarios Matrix

The benchmarks evaluate cryptographic overhead across two orthogonal axes: **Infrastructure Configuration** (cryptographic protocol, cipher suite, and curve) and **Traffic Profile** (k6 load profile).

| ID | Infrastructure Setup | Traffic Profile (`TEST_TYPE`) | Description |
| --- | --- | --- | --- |
| 1A | Plaintext (No mTLS) | `baseline` | Sustained GET traffic (100 VUs) measuring clean baseline latency without encryption. |
| 1B | Plaintext (No mTLS) | `payload` | High data volume POST requests (~5MB) measuring transmission throughput without encryption. |
| 1C | Plaintext (No mTLS) | `stress` | Ramping load up to 500 VUs to determine clean saturation limits. |
| 2A | mTLS 1.3 (Default Istio) | `baseline` | Default TLS 1.3 with hardware-accelerated AES-GCM (128/256-bit). |
| 2B | mTLS 1.3 (Default Istio) | `payload` | Bulk encryption evaluation for modern AEAD ciphers under high payload volume. |
| 2C | mTLS 1.3 (Default Istio) | `stress` | Concurrency and proxy CPU saturation under TLS 1.3. |
| 3A | mTLS 1.2 (AES-128-GCM) | `baseline` / `payload` / `stress` | Legacy TLS 1.2 with 128-bit AES-GCM via EnvoyFilter. |
| 3B | mTLS 1.2 (AES-256-GCM) | `baseline` / `payload` / `stress` | 256-bit AES-GCM evaluating key size impact on throughput and CPU. |
| 4A | mTLS 1.2 (ChaCha20-Poly1305) | `baseline` / `payload` / `stress` | Stream cipher alternative evaluating software performance without hardware AES-NI. |
| 5A | mTLS 1.2 (AES-128-SHA256 CBC) | `baseline` / `payload` / `stress` | Legacy block cipher mode evaluating single-threaded CPU bottleneck during bulk decryption. |
| 6A | mTLS 1.3 (Post-Quantum Hybrid) | `baseline` / `payload` / `stress` | Hybrid X25519 + ML-KEM-768 / Kyber curve negotiation. |
| 7A | All Configurations | `handshake` (No-KeepAlive) | Isolated connection establishment test (constant arrival rate, connection close) isolating handshake cost. |

---

### Step-by-Step Execution Guide

1. **Initialize Cluster & Service Mesh:**
   Run the setup script once at the start of testing:
   ```bash
   ./01_scripts/setup_cluster.sh
   ```
   This provisions the k3d cluster, installs Istio with the minimal profile, injects sidecars, and deploys `httpbin` and `k6`.

2. **Verify Cryptographic Negotiation:**
   Execute live telemetry verification across all configurations:
   ```bash
   ./verify_ciphers.sh
   ```
   Ensures Envoy proxy instances correctly negotiate the specified ciphers and curves before conducting performance runs.

3. **Execute Benchmark Battery:**
   Run the automated test runner (with randomized test ordering to avoid thermal or temporal bias):
   ```bash
   N_RUNS=5 ./run_all_tests.sh
   ```
   Or execute the end-to-end pipeline:
   ```bash
   ./start.sh
   ```

---

### Telemetry, Prometheus, and Grafana

1. **Live Dashboard Access:**
   ```bash
   kubectl port-forward svc/grafana 3000:3000 -n istio-system
   ```
   Open `http://localhost:3000` and access the **Istio Workload Dashboard**.

2. **Key Telemetry Metrics:**
   - **Proxy CPU Consumption:**
     ```promql
     sum(rate(container_cpu_usage_seconds_total{namespace="default", container="istio-proxy", pod=~"httpbin-.*"}[1m])) * 1000
     ```
   - **Application CPU Consumption:**
     ```promql
     sum(rate(container_cpu_usage_seconds_total{namespace="default", container="httpbin", pod=~"httpbin-.*"}[1m])) * 1000
     ```
   - **TLS Handshake Rate:**
     ```promql
     sum(rate(envoy_listener_ssl_handshake{namespace="default", pod=~"httpbin-.*"}[1m]))
     ```
   - **Cipher & Curve Statistics:**
     Captured directly from the Envoy administrative interface at `localhost:15000/stats` filtered by `ssl.ciphers` and `ssl.curves`.
