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

**Option A — Complete End-to-End Workflow (One-Click):**
Run the automated pipeline to provision cluster, verify ciphers, execute basic benchmarks, and launch Grafana:
```bash
./start.sh
```

**Option B — Phased Granular Execution:**

1. **Initialize Cluster & Service Mesh:**
   Run the setup script once at the start of testing:
   ```bash
   ./01_scripts/setup_cluster.sh
   ```
   This provisions the k3d cluster, installs Istio with the minimal profile, injects sidecars, and deploys `httpbin` and `k6`.

2. **Verify Cryptographic Negotiation:**
   Execute live telemetry verification across all configurations:
   ```bash
   ./01_scripts/verify_ciphers.sh
   ```
   Ensures Envoy proxy instances correctly negotiate the specified ciphers and curves before conducting performance runs.

3. **Execute Benchmark Battery:**
   Run the official basic benchmark suite (randomized setups):
   ```bash
   N_RUNS=5 ./run_basic_test.sh
   ```
   Or execute the full exploratory test suite:
   ```bash
   ./test_trying/start.sh
   # or:
   N_RUNS=3 ./test_trying/run_all_test_v2.sh
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
     sum(irate(container_cpu_usage_seconds_total{namespace="default", container="istio-proxy", pod=~"httpbin-.*"}[30s])) * 1000
     ```
   - **Application CPU Consumption:**
     ```promql
     sum(irate(container_cpu_usage_seconds_total{namespace="default", container="httpbin", pod=~"httpbin-.*"}[30s])) * 1000
     ```
   - **TLS Handshake Rate:**
     ```promql
     sum(irate(envoy_listener_ssl_handshake{namespace="default", pod=~"httpbin-.*"}[30s]))
     ```
   - **TLS Handshake Duration (ms):**
     Captured from Envoy `/stats/prometheus` (`envoy_*_ssl_handshake_sum` / `count`) and injected directly into `summary_*.json` under `.metrics.envoy_tls_handshake_ms_mean`.
   - **Cipher & Curve Statistics:**
     Captured directly from the Envoy administrative interface at `localhost:15000/stats` filtered by `ssl.ciphers` and `ssl.curves`.
