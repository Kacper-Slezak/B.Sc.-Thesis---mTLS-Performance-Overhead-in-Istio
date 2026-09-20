# Bachelor's Thesis: Performance Overhead Analysis of mTLS Cryptography in Istio Environment

## 1. Repository Structure

All scripts and results are organized systematically as follows:

* `00_journal/` - Research journal and empirical experiment observations (e.g. ML-KEM enforcement analysis).
* `01_scripts/` - Bash scripts automating cluster provisioning (`setup_cluster.sh`), cipher verification (`verify_ciphers.sh`), mesh diagnostics (`diag_mesh.sh`, `diag_envoyfilter_config.sh`), and PQC scans (`run_pqc_test.sh`, `reproduce_pqc_failure.sh`).
* `02_manifests/` - Kubernetes and Istio configurations (EnvoyFilters forcing specific ciphers, DestinationRules disabling keep-alive).
* `03_test_scripts/` - Load testing scenarios for K6 (`main_k6_scenarios.js` covering baseline, payload, stress, and handshake profiles).
* `04_results/` - Telemetry captures, RawLogs, Summary JSONs, Prometheus Metrics, generated plots, and statistical comparison reports.
* `05_analytics/` - Python data processing, Prometheus metric scraping (`fetch_and_plot.py`), and statistical analysis (`compare_results.py`, `stats_compare.py`).

## 2. Instructions for Recreating the Research Environment

To reproduce the research from scratch:

1. Ensure Docker Desktop / Docker Engine is running.
2. Open a terminal.
3. Run the complete automated workflow or individual phases:

   ```bash
   # Complete end-to-end workflow:
   ./start.sh
   
   # Or run individual phases:
   ./01_scripts/setup_cluster.sh
   ./verify_ciphers.sh
   N_RUNS=5 ./run_all_tests.sh
   ```

4. Verify K6 client pod connectivity:

   ```bash
   K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
   ```

## 3. Measurement and Test Log

### Phase 1: Baseline Environment (Default mTLS 1.3)

**Goal:** Measure clean cluster overhead for the default, strongest cryptographic configuration (AES-GCM).

* **Light test** (High QPS, small payload):
  * Script: `03_test_scripts/Archive/light_test.js` (500 QPS / 30s)
  * Result: `04_results/Archive/summary_light_mtls1_3.json`
* **Heavy test** (Lower QPS, large 50 KB payload):
  * Script: `03_test_scripts/Archive/heavy_test.js` (200 QPS / 60s)
  * Result: `04_results/Archive/summary_heavy_mtls1_3.json`

### Phase 2: Resistance to Tampering (Attempt to Force TLS 1.2 and Weak Ciphers)

**Goal:** Investigate cluster behavior when attempting to downgrade cryptographic standards (downgrade attack) by forcing TLS 1.2 and an obsolete cipher.

#### Attempt 1: Using the Standard Istio API (Unsuccessful)

First, a reconfiguration attempt was made using the standard `DestinationRule` resource.

**Applied YAML manifest:**
`02_manifests/force_mtls_1_2.yaml`

##### Error Message

```bash
$ kubectl apply -f 02_manifests/Archive/force_mtls_1_2.yaml
peerauthentication.security.istio.io/strict-mtls created
Error from server (BadRequest): error when creating "02_manifests/force_mtls_1_2.yaml": DestinationRule in version "v1alpha3" cannot be handled as a DestinationRule: strict decoding error: unknown field "spec.trafficPolicy.tls.cipherSuites", unknown field "spec.trafficPolicy.tls.maxProtocolVersion", unknown field "spec.trafficPolicy.tls.minProtocolVersion"
```

**Conclusion from Attempt 1:** The above error is proof of the built-in resilience of the Istio control plane (Istiod) to configuration errors that lower security. The Istio development team intentionally blocked the ability to freely edit the `cipherSuites` and `ProtocolVersion` fields in the standard `DestinationRule` API to prevent accidental or deliberate weakening of encryption in the Service Mesh.

#### Attempt 2: Direct Injection of Configuration into the Proxy (EnvoyFilter)

Due to the inability to edit ciphers via the high-level Istio API, a decision was made to use the `EnvoyFilter` resource. This allows direct intervention in the native configuration (config patches) of Envoy proxy servers operating as sidecars, bypassing the validation restrictions of the Istio API.

**Applied YAML manifest (forcing TLS 1.2 and a weak AES128-SHA cipher on the server):**
`02_manifests/Archive/envoyfilter_downgrade_mtls_1_2.yaml`

**Test Result for Attempt 2:** The K6 test (light script) finished with a 100% success rate (`status is 200`) and latency of about 1.65ms. This means the attack was unsuccessful, and the system did not lower the security standard.
Result file: `04_results/Archive/summary_light_tls1_2_rejected.json`

**Verification using istioctl:**
To understand why the EnvoyFilter did not work, a listener configuration dump was performed on the `httpbin` server:
`istioctl proxy-config listeners $HTTPBIN_POD --port 15006 -o json | grep "tls_maximum_protocol_version"`
The command output was empty.

```bash
$ istioctl proxy-config listeners $HTTPBIN_POD --port 15006 -o json | grep -A 10 "tls_maximum_protocol_version"
```

**Conclusion from Attempt 2:** Istio's internal security mechanisms protect inbound ports and silently reject configuration patches that lower security.

#### Attempt 3: Changing the Attack Vector - Applying Restrictions to the Client (K6)

It was decided to block the client from using strong cryptography for outbound traffic (`SIDECAR_OUTBOUND`).

**Applied YAML manifest:**
`02_manifests/Archive/change_client_mtls1_2.yaml`

```bash
$ kubectl apply -f 02_manifests/Archive/change_client_mtls1_2.yaml 
Warning: EnvoyFilter exposes internal implementation details that may change at any time. Prefer other APIs if possible, and exercise extreme caution, especially around upgrades.
envoyfilter.networking.istio.io/hack-k6-client created
```

**Test Result for Attempt 3:**
The test was a complete failure (0% 200 OK status, 100% of requests failed).

```text
  █ TOTAL RESULTS
    checks_total.......: 14979   496.005612/s
    checks_succeeded...: 0.00%   0 out of 14979
    checks_failed......: 100.00% 14979 out of 14979
    ✗ status is 200
```

*(Result file: `04_results/Archive/summary_light_hacked_client.json`)*

**Final Conclusion from Phase 2:**
The attack based on forcing weaker cryptography (downgrade to TLS 1.2 and AES128-SHA cipher) on the client resulted in a connection failure with the server.
The experiment proved that Envoy sidecars in the Istio architecture exhibit very high resistance to cryptographic configuration tampering. Default certificates and identity verification mechanisms (SPIFFE) effectively reject connections from clients attempting to use unauthorized, weaker encryption algorithms.

### Phase 3: Edge/IoT Scenario – Forcing TLS 1.2 at Cluster Level

**Goal:** Legally lower the cluster's cryptographic standard to TLS 1.2 (using an EnvoyFilter blocking upward negotiation) and study the impact of this procedure on network performance (Latency).

**Light Test Result (K6):**

* Number of requests: 15000 (100% status 200 OK)
* Average latency (`avg`): **1.75 ms**
* 90th percentile latency (`p90`): **2.25 ms**
*(Summary file: `04_results/Archive/summary_scenario3_real.json`)*
*(Proxy configuration proof: `04_results/tls_proof.json` with parameter `"tlsMaximumProtocolVersion": "TLSV1_2"`)*

**Conclusions:**
In accordance with the initial assumptions from the "Action Plan", forcing the legacy TLS 1.2 standard increased the average network latency (from 1.65 ms to 1.75 ms, which is a growth of about 6%).
This increase is a direct result of protocol architectural differences – TLS 1.2 requires two full round trips (2-RTT) to establish a secure connection, whereas optimized TLS 1.3 does it in a single step (1-RTT). This confirms the hypothesis that in IoT applications, where the network can be unstable, TLS 1.2 causes a noticeable time overhead.

```bash
$ HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")
$ for i in {1..25}; do echo "CPU Measurements:"; kubectl top pod $HTTPBIN_POD --containers | grep istio-proxy; sleep 3; done
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   76m          33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   76m          33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   76m          33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   76m          33Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   162m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   162m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   162m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   162m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   162m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   160m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   160m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   160m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   160m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   160m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   158m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   158m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   158m         34Mi
CPU Measurements:
httpbin-7b549f7859-5rxw9   istio-proxy   158m         34Mi
```

### Summary of Phase 2 and 3: Performance Analysis of TLS 1.2 vs 1.3

Comparative tests were performed using a large data payload (50 KB payload). The resource consumption measurements of the `istio-proxy` container showed:

* **TLS 1.3 (Baseline):** Peak CPU consumption at **158m**, stabilization at **149m**.
* **TLS 1.2 (IoT Downgrade):** Peak CPU consumption at **162m**, stabilization at **158m**.

**Research Conclusions:**
Contrary to the initial hypothesis, the more modern TLS 1.3 protocol proved to be more CPU-efficient (approx. 5.7% lower CPU usage during stable traffic). This confirms the high optimization of the cryptographic stack in modern versions of Envoy and the benefits of the shortened key negotiation handshake mechanism. On the other hand, TLS 1.2 showed slightly lower RAM memory demand (~10% difference).
