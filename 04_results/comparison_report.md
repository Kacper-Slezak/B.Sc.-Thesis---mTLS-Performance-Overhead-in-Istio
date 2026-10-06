# Performance Comparison Report
Generated for test run: `20261004_214614`

This report compares the performance of different mutual TLS configurations in Istio:

- **Plaintext**: Plain HTTP traffic (no mTLS)
- **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)
- **mTLS 1.2 (AES-GCM)**: ECDHE-ECDSA-AES128-GCM-SHA256
- **mTLS 1.2 (ChaCha20)**: ECDHE-ECDSA-CHACHA20-POLY1305-SHA256
- **mTLS 1.2 (AES-CBC)**: ECDHE-ECDSA-AES128-SHA256 (CBC mode)

- **mTLS 1.3 (Post-Quantum)**: X25519MLKEM768 (Hybrid Kyber Key Exchange)

## TLS Verification (live sidecar stats)

- **mtls1.3-default**: `TLS_AES_128_GCM_SHA256`=863572, `X25519`=863572
- **mtls1.2-gcm**: `ECDHE-RSA-AES128-GCM-SHA256`=1053049, `X25519`=1053049
- **mtls1.2-chacha**: `ECDHE-RSA-CHACHA20-POLY1305`=953950, `X25519`=953950
- **mtls1.2-cbc**: `ECDHE-RSA-AES128-SHA256`=1048091, `X25519`=1048091
- **mtls1.3-postquantum**: `TLS_AES_128_GCM_SHA256`=875732, `X25519MLKEM768`=875732


## Scenario: BASELINE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshake (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 2198.07 | - | 40.521 | - | 67.638 | - | 0.00 | 478.4 | 0.3 | 41.7 |
| **mtls1.3-default** | 2176.45 | -0.98% | 40.960 | +1.08% | 67.928 | - | 0.54 | 572.0 | 0.3 | 42.3 |
| **mtls1.2-gcm** | 2191.57 | -0.30% | 40.523 | +0.00% | 67.679 | - | 92.56 | 522.8 | 0.3 | 41.9 |
| **mtls1.2-chacha** | 2206.51 | +0.38% | 40.513 | -0.02% | 67.622 | - | 0.57 | 465.6 | 0.3 | 43.8 |
| **mtls1.2-cbc** | 2225.83 | +1.26% | 40.539 | +0.04% | 67.582 | - | 89.44 | 524.9 | 0.3 | 44.1 |
| **mtls1.3-postquantum** | 2214.71 | +0.76% | 40.650 | +0.32% | 67.676 | - | 0.58 | 450.1 | 0.3 | 44.3 |


## Scenario: BASELINE-NOKEEPALIVE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshake (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 2155.00 | - | 41.132 | - | 67.980 | - | 0.00 | 587.5 | 0.3 | 41.8 |
| **mtls1.3-default** | 1594.51 | -26.01% | 55.673 | +35.35% | 86.156 | - | 1283.73 | 1305.5 | 0.4 | 43.5 |
| **mtls1.2-gcm** | 2063.85 | -4.23% | 42.775 | +3.99% | 69.727 | - | 1671.68 | 875.6 | 0.3 | 43.1 |
| **mtls1.2-chacha** | 1485.86 | -31.05% | 59.799 | +45.38% | 93.096 | - | 1219.26 | 1306.7 | 0.3 | 44.2 |
| **mtls1.2-cbc** | 2055.33 | -4.63% | 43.297 | +5.26% | 69.970 | - | 1713.59 | 895.3 | 0.3 | 44.9 |
| **mtls1.3-postquantum** | 1741.11 | -19.21% | 51.358 | +24.86% | 79.457 | - | 1427.10 | 1286.6 | 0.3 | 45.1 |


## Scenario: PAYLOAD
*No data available for this scenario.*

## Scenario: PAYLOAD-NOKEEPALIVE
*No data available for this scenario.*

## Scenario: STRESS
*No data available for this scenario.*
