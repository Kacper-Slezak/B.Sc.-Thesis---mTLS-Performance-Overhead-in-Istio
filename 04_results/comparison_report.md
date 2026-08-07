# Performance Comparison Report
Generated for test run: `20260807_120708`

This report compares the performance of different mutual TLS configurations in Istio:

- **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)
- **mTLS 1.2 (AES-GCM)**: ECDHE-RSA-AES128-GCM-SHA256
- **mTLS 1.2 (ChaCha20)**: ECDHE-RSA-CHACHA20-POLY1305-SHA256
- **mTLS 1.2 (AES-CBC)**: ECDHE-RSA-AES128-SHA256 (CBC mode)

## TLS Verification (live sidecar stats, not just the applied CR)

- **mtls1.3-default**: `TLS_AES_128_GCM_SHA256`=166947
- **mtls1.2-gcm**: `ECDHE-RSA-AES256-GCM-SHA384`=174036
- **mtls1.2-chacha**: `ECDHE-RSA-CHACHA20-POLY1305`=173734
- **mtls1.2-cbc**: `ECDHE-RSA-AES128-SHA256`=170268


## Scenario: BASELINE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 1450.15 | - | 58.133 | - | 83.687 | 0.50 | 536.0 | 809.7 | 80.4 |
| **mtls1.2-gcm** | 1485.34 | +2.43% | 56.730 | -2.41% | 78.386 | 10.96 | 604.8 | 813.0 | 94.5 |
| **mtls1.2-chacha** | 1468.28 | +1.25% | 57.805 | -0.56% | 80.820 | 12.35 | 603.3 | 812.4 | 97.0 |
| **mtls1.2-cbc** | 1459.90 | +0.67% | 57.985 | -0.25% | 80.599 | 10.13 | 616.4 | 839.4 | 98.4 |


## Scenario: BASELINE-NOKEEPALIVE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 506.85 | - | 165.956 | - | 558.763 | 417.15 | 1537.9 | 412.2 | 85.3 |
| **mtls1.2-gcm** | 531.77 | +4.92% | 159.788 | -3.72% | 703.507 | 447.89 | 1381.3 | 386.4 | 95.3 |
| **mtls1.2-chacha** | 529.57 | +4.48% | 158.904 | -4.25% | 692.241 | 448.09 | 1476.5 | 409.1 | 98.8 |
| **mtls1.2-cbc** | 533.39 | +5.24% | 159.402 | -3.95% | 702.887 | 449.06 | 1446.9 | 398.9 | 100.8 |


## Scenario: PAYLOAD
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 478.69 | - | 174.936 | - | 234.990 | 0.04 | 349.0 | 834.8 | 62.8 |
| **mtls1.2-gcm** | 557.16 | +16.39% | 150.207 | -14.14% | 200.710 | 0.01 | 447.2 | 801.2 | 91.6 |
| **mtls1.2-chacha** | 560.51 | +17.09% | 150.601 | -13.91% | 198.798 | 0.01 | 487.5 | 854.9 | 94.9 |
| **mtls1.2-cbc** | 557.39 | +16.44% | 151.570 | -13.36% | 202.904 | 0.01 | 637.1 | 842.4 | 97.4 |


## Scenario: PAYLOAD-NOKEEPALIVE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 423.12 | - | 197.534 | - | 303.454 | 359.55 | 1291.4 | 721.3 | 95.2 |
| **mtls1.2-gcm** | 447.77 | +5.83% | 187.115 | -5.27% | 273.415 | 377.16 | 1231.1 | 732.1 | 98.1 |
| **mtls1.2-chacha** | 442.04 | +4.47% | 189.563 | -4.04% | 288.160 | 372.11 | 1291.6 | 750.0 | 100.9 |
| **mtls1.2-cbc** | 429.36 | +1.47% | 196.816 | -0.36% | 300.365 | 363.60 | 1349.8 | 714.1 | 101.5 |


## Scenario: STRESS
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **mtls1.3-default** | 1436.74 | - | 290.660 | - | 383.645 | 2.18 | 515.5 | 902.1 | 78.8 |
| **mtls1.2-gcm** | 1434.72 | -0.14% | 292.483 | +0.63% | 394.336 | 2.22 | 560.3 | 869.1 | 92.8 |
| **mtls1.2-chacha** | 1420.63 | -1.12% | 301.602 | +3.76% | 397.034 | 2.27 | 571.2 | 888.6 | 95.4 |
| **mtls1.2-cbc** | 1401.37 | -2.46% | 300.298 | +3.32% | 404.689 | 2.15 | 578.0 | 890.4 | 97.4 |

