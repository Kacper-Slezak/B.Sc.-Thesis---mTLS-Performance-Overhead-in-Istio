### **Table of Contents: Performance Overhead Analysis of Classical and Post-Quantum Cryptography (PQC) in a Service Mesh Architecture using Istio**

**1. Introduction**

* 1.1. Objectives and Research Hypotheses
* 1.2. Scope of the Thesis
* 1.3. Document Structure

**2. Theoretical Foundations of Cryptography in Microservices Architecture**

* 2.1. The Service Mesh Concept and the Role of Istio / Envoy Proxy
* 2.2. Mutual TLS (mTLS): Authentication and Traffic Encryption
* 2.3. Anatomy of the TLS 1.3 Protocol
* 2.3.1. Asymmetric Cryptography (Handshake and Key Negotiation)
* 2.3.2. Symmetric Cryptography (Payload Encryption)


* 2.4. Post-Quantum Cryptography (PQC) and the NIST FIPS 203 (ML-KEM) Standard

**3. Research Environment and Testing Methodology**

* 3.1. Test Environment Architecture (K3d, Kubernetes, Istio Minimal Profile)
* 3.2. Load Generation and Monitoring Tools (k6, Prometheus, Grafana)
* 3.3. Overhead Measurement Methodology (RPS, Proxy CPU, Latency)
* 3.4. Definition of Test Scenarios:
* 3.4.1. The Impact of Keep-Alive vs. No-KeepAlive Connections (Handshake Isolation)
* 3.4.2. Throughput Tests (Baseline/Stress) vs. Data Volume (Payload)



**4. The Impact of mTLS on Service Mesh Performance (Plaintext vs. mTLS)**

* 4.1. Establishing Baseline Metrics for Unencrypted Traffic (Plaintext)
* 4.2. Overhead Analysis During Connection Establishment (The Handshake Bottleneck)
* 4.3. The Cost of Maintaining an Encrypted Tunnel in Long-Lived Connections (Keep-Alive)
* 4.4. Conclusions: Asymmetric CPU Overhead in Envoy Proxy

**5. Performance Comparison of Symmetric Cipher Suites**

* 5.1. Customizing TLS Configuration via the `EnvoyFilter` Mechanism
* 5.2. Hardware Acceleration of AES-128-GCM in the Default Istio Profile
* 5.3. ChaCha20-Poly1305: A Software Alternative
* 5.4. AES-CBC: The Impact of Single-Threading on CPU Usage in Payload Tests
* 5.5. Conclusions: Symmetric Cipher Selection and Cluster Operational Costs

**6. Readiness Analysis of Istio for Post-Quantum Standards (Research Experiment)**

* 6.1. Defining Hybrid Key Exchange (X25519MLKEM768 / Kyber) in the BoringSSL Specification
* 6.2. PQC Enforcement Methodology (Configuration Fuzzing and Algorithm Isolation)
* 6.3. Analysis of TLS Negotiation Rejections by Envoy Proxy in a No-Fallback Scenario
* 6.4. Architectural Limitations of Official Istio Distributions (Missing Compiler Flags)
* 6.5. Alternative PQC Deployment Paths (e.g., the OQS-Envoy Project)

**7. Summary and Final Conclusions**

* 7.1. Verification of Research Hypotheses
* 7.2. Architectural Recommendations for Production Environments
* 7.3. Directions for Future Research

---

**A quick tip for writing in English:**
When describing your PQC failure in Chapter 6, use phrases like *"empirical evidence suggests..."* or *"the configuration was strictly isolated to prevent fallback mechanism..."*. This frames the lack of ML-KEM support not as a "bug in your code," but as a proven limitation of the current official Istio release (as of late 2024/early 2026).