# Performance Comparison Report
Generated for test run: `20260718_161506`

This report compares the performance of different mutual TLS configurations in Istio:

- **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)
- **mTLS 1.2 (AES-GCM)**: ECDHE-ECDSA-AES128-GCM-SHA256
- **mTLS 1.2 (ChaCha20)**: ECDHE-ECDSA-CHACHA20-POLY1305-SHA256
- **mTLS 1.2 (AES-CBC)**: ECDHE-ECDSA-AES128-SHA256 (CBC mode)

## Scenario: BASELINE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | Handshake Avg (ms) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 549.70 | - | 1.715 | - | 2.309 | 0.000 | 294.7 | 244.3 | 32.4 |
| **mtls1.2-gcm** | 550.00 | +0.05% | 1.610 | -6.11% | 2.201 | 0.000 | 154.7 | 257.3 | 34.5 |
| **mtls1.2-chacha** | 549.83 | +0.02% | 1.649 | -3.80% | 2.241 | 0.000 | 250.7 | 266.5 | 36.9 |
| **mtls1.2-cbc** | 550.02 | +0.06% | 1.670 | -2.59% | 2.303 | 0.000 | 235.4 | 226.8 | 37.5 |


## Scenario: BASELINE-NOKEEPALIVE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | Handshake Avg (ms) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 550.02 | - | 1.789 | - | 2.622 | 0.000 | 240.7 | 272.7 | 33.9 |
| **mtls1.2-gcm** | 550.02 | +0.00% | 1.864 | +4.21% | 2.722 | 0.000 | 313.2 | 261.5 | 35.2 |
| **mtls1.2-chacha** | 550.02 | +0.00% | 1.722 | -3.72% | 2.349 | 0.000 | 231.7 | 250.3 | 35.7 |
| **mtls1.2-cbc** | 549.58 | -0.08% | 1.685 | -5.82% | 2.334 | 0.000 | 221.8 | 287.7 | 36.2 |


## Scenario: PAYLOAD
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | Handshake Avg (ms) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 110.00 | - | 5.433 | - | 7.162 | 0.000 | 116.2 | 604.9 | 33.3 |
| **mtls1.2-gcm** | 110.00 | +0.00% | 5.459 | +0.49% | 7.170 | 0.000 | 102.5 | 572.0 | 35.0 |
| **mtls1.2-chacha** | 110.00 | -0.00% | 5.519 | +1.59% | 7.246 | 0.000 | 124.7 | 616.3 | 35.9 |
| **mtls1.2-cbc** | 110.00 | +0.00% | 5.489 | +1.03% | 7.255 | 0.000 | 107.7 | 685.3 | 36.6 |


## Scenario: PAYLOAD-NOKEEPALIVE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | Handshake Avg (ms) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 110.01 | - | 5.787 | - | 7.500 | 0.000 | 117.9 | 579.4 | 34.4 |
| **mtls1.2-gcm** | 108.83 | -1.07% | 5.801 | +0.24% | 7.438 | 0.000 | 108.4 | 560.2 | 35.7 |
| **mtls1.2-chacha** | 110.00 | -0.00% | 5.780 | -0.12% | 7.520 | 0.000 | 132.9 | 534.0 | 37.3 |
| **mtls1.2-cbc** | 110.00 | -0.00% | 5.870 | +1.44% | 7.683 | 0.000 | 123.2 | 625.4 | 37.0 |


## Scenario: STRESS
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | Handshake Avg (ms) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 852.33 | - | 1.740 | - | 2.487 | 0.000 | 442.1 | 408.4 | 33.4 |
| **mtls1.2-gcm** | 852.39 | +0.01% | 1.711 | -1.70% | 2.455 | 0.000 | 191.5 | 465.3 | 36.1 |
| **mtls1.2-chacha** | 852.45 | +0.01% | 1.722 | -1.02% | 2.471 | 0.000 | 407.9 | 478.5 | 35.9 |
| **mtls1.2-cbc** | 852.33 | -0.00% | 1.712 | -1.61% | 2.421 | 0.000 | 396.1 | 250.9 | 36.3 |

