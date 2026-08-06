# Performance Comparison Report
Generated for test run: `20260806_194355`

This report compares the performance of different mutual TLS configurations in Istio:

- **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)
- **mTLS 1.2 (AES-GCM)**: ECDHE-ECDSA-AES128-GCM-SHA256
- **mTLS 1.2 (ChaCha20)**: ECDHE-ECDSA-CHACHA20-POLY1305-SHA256
- **mTLS 1.2 (AES-CBC)**: ECDHE-ECDSA-AES128-SHA256 (CBC mode)

## TLS Verification (live sidecar stats, not just the applied CR)

- **mtls1.3-default**: `TLS_AES_128_GCM_SHA256`=170105
- **mtls1.2-gcm**: `ECDHE-RSA-AES256-GCM-SHA384`=176295
- **mtls1.2-chacha**: `ECDHE-RSA-AES256-GCM-SHA384`=177368
- **mtls1.2-cbc**: `ECDHE-RSA-AES256-GCM-SHA384`=153067


## Scenario: BASELINE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 7699.48 | - | 11.788 | - | 19.582 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-gcm** | 7408.58 | -3.78% | 12.321 | +4.52% | 19.873 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-chacha** | 7350.81 | -4.53% | 12.437 | +5.51% | 20.137 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-cbc** | 7268.27 | -5.60% | 12.584 | +6.75% | 20.226 | 0.00 | 0.0 | 0.0 | 0.0 |


## Scenario: BASELINE-NOKEEPALIVE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 550.45 | - | 164.339 | - | 397.744 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-gcm** | 565.83 | +2.79% | 160.163 | -2.54% | 782.664 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-chacha** | 569.01 | +3.37% | 160.409 | -2.39% | 779.338 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-cbc** | 422.93 | -23.17% | 214.622 | +30.60% | 500.174 | 0.00 | 0.0 | 0.0 | 0.0 |


## Scenario: PAYLOAD
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 1729.31 | - | 50.721 | - | 125.648 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-gcm** | 1772.96 | +2.52% | 49.658 | -2.10% | 121.506 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-chacha** | 1724.13 | -0.30% | 51.134 | +0.81% | 121.917 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-cbc** | 1752.36 | +1.33% | 50.463 | -0.51% | 121.360 | 0.00 | 0.0 | 0.0 | 0.0 |


## Scenario: PAYLOAD-NOKEEPALIVE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 484.00 | - | 187.117 | - | 370.366 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-gcm** | 508.22 | +5.00% | 178.055 | -4.84% | 349.373 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-chacha** | 511.62 | +5.71% | 177.175 | -5.31% | 348.302 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-cbc** | 509.42 | +5.25% | 177.598 | -5.09% | 352.294 | 0.00 | 0.0 | 0.0 | 0.0 |


## Scenario: STRESS
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 8787.45 | - | 51.765 | - | 81.843 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-gcm** | 8798.78 | +0.13% | 51.870 | +0.20% | 81.982 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-chacha** | 8893.67 | +1.21% | 51.317 | -0.87% | 81.761 | 0.00 | 0.0 | 0.0 | 0.0 |
| **mtls1.2-cbc** | 8709.60 | -0.89% | 52.413 | +1.25% | 85.136 | 0.00 | 0.0 | 0.0 | 0.0 |

