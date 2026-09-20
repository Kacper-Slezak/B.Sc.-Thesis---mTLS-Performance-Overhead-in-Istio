# Performance Comparison Report
Generated for test run: `20260918_004151`

This report compares the performance of different mutual TLS configurations in Istio:

- **Plaintext**: Zwykly ruch HTTP (brak mTLS)
- **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)
- **mTLS 1.2 (AES-GCM)**: ECDHE-ECDSA-AES128-GCM-SHA256
- **mTLS 1.2 (ChaCha20)**: ECDHE-ECDSA-CHACHA20-POLY1305-SHA256
- **mTLS 1.2 (AES-CBC)**: ECDHE-ECDSA-AES128-SHA256 (CBC mode)

- **mTLS 1.3 (Post-Quantum)**: X25519MLKEM768 (Hybrid Kyber Key Exchange)

## TLS Verification (live sidecar stats)

- **mtls1.3-default**: `TLS_AES_128_GCM_SHA256`=1065224, `X25519`=1065224
- **mtls1.2-gcm**: `ECDHE-RSA-AES128-GCM-SHA256`=1262799, `X25519`=1262799
- **mtls1.2-chacha**: `ECDHE-RSA-CHACHA20-POLY1305`=1237049, `X25519`=1237049
- **mtls1.2-cbc**: `ECDHE-RSA-AES128-SHA256`=1205250, `X25519`=1205250
- **mtls1.3-postquantum**: `TLS_AES_128_GCM_SHA256`=1054522, `X25519MLKEM768`=1054522


## Scenario: BASELINE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 2241.07 | - | 40.820 | - | 67.730 | 0.00 | 506.2 | 0.3 | 77.9 |
| **mtls1.3-default** | 2179.10 | -2.76% | 42.221 | +3.43% | 69.134 | 100.32 | 676.1 | 0.4 | 94.5 |
| **mtls1.2-gcm** | 2178.30 | -2.80% | 42.356 | +3.76% | 69.506 | 8.25 | 584.7 | 0.4 | 95.0 |
| **mtls1.2-chacha** | 2178.43 | -2.79% | 42.120 | +3.18% | 69.149 | 7.71 | 583.8 | 0.4 | 94.7 |
| **mtls1.2-cbc** | 2181.70 | -2.65% | 42.176 | +3.32% | 69.255 | 98.45 | 637.8 | 0.4 | 95.0 |
| **mtls1.3-postquantum** | 2244.17 | +0.14% | 40.872 | +0.13% | 67.695 | 33.96 | 552.5 | 0.3 | 85.3 |


## Scenario: BASELINE-NOKEEPALIVE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 2236.78 | - | 40.665 | - | 67.581 | 0.00 | 433.7 | 0.3 | 65.8 |
| **mtls1.3-default** | 1622.69 | -27.45% | 56.268 | +38.37% | 92.420 | 1312.87 | 1309.6 | 0.4 | 94.4 |
| **mtls1.2-gcm** | 1976.51 | -11.64% | 46.454 | +14.24% | 76.801 | 1606.59 | 1003.2 | 0.4 | 95.5 |
| **mtls1.2-chacha** | 1977.65 | -11.58% | 46.178 | +13.56% | 77.361 | 1621.37 | 994.2 | 0.4 | 93.2 |
| **mtls1.2-cbc** | 1966.42 | -12.09% | 46.566 | +14.51% | 77.877 | 1615.25 | 1011.2 | 0.4 | 94.7 |
| **mtls1.3-postquantum** | 1608.24 | -28.10% | 56.702 | +39.44% | 92.276 | 1316.17 | 1252.8 | 0.4 | 92.7 |


## Scenario: PAYLOAD
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 282.05 | - | 56.324 | - | 130.687 | 0.00 | 456.0 | 0.5 | 65.7 |
| **mtls1.3-default** | 240.97 | -14.56% | 267.012 | +374.06% | 628.467 | 197.73 | 816.4 | 0.7 | 112.3 |
| **mtls1.2-gcm** | 247.40 | -12.29% | 208.755 | +270.63% | 532.469 | 233.74 | 790.8 | 0.7 | 112.3 |
| **mtls1.2-chacha** | 236.42 | -16.18% | 286.384 | +408.46% | 686.938 | 193.37 | 843.2 | 0.8 | 112.0 |
| **mtls1.2-cbc** | 207.98 | -26.26% | 357.754 | +535.17% | 878.654 | 197.23 | 846.9 | 0.6 | 106.9 |
| **mtls1.3-postquantum** | 266.16 | -5.63% | 249.085 | +342.23% | 591.647 | 214.44 | 802.4 | 0.5 | 104.5 |


## Scenario: PAYLOAD-NOKEEPALIVE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 281.73 | - | 57.933 | - | 132.728 | 0.00 | 454.8 | 0.5 | 82.3 |
| **mtls1.3-default** | 240.28 | -14.71% | 273.081 | +371.37% | 620.640 | 186.53 | 830.0 | 0.6 | 110.9 |
| **mtls1.2-gcm** | 246.79 | -12.40% | 176.962 | +205.46% | 445.878 | 285.84 | 694.7 | 0.7 | 109.1 |
| **mtls1.2-chacha** | 238.50 | -15.35% | 281.835 | +386.48% | 664.387 | 277.82 | 832.4 | 0.7 | 113.0 |
| **mtls1.2-cbc** | 209.80 | -25.53% | 352.356 | +508.21% | 838.190 | 161.29 | 762.9 | 0.5 | 104.9 |
| **mtls1.3-postquantum** | 266.41 | -5.44% | 247.068 | +326.47% | 564.726 | 238.35 | 884.0 | 0.5 | 104.5 |


## Scenario: STRESS
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 9155.38 | - | 49.540 | - | 77.409 | 0.00 | 756.8 | 0.3 | 66.0 |
| **mtls1.3-default** | 7820.08 | -14.58% | 58.242 | +17.57% | 102.256 | 31.33 | 1533.4 | 0.4 | 95.2 |
| **mtls1.2-gcm** | 7723.90 | -15.64% | 59.281 | +19.66% | 104.237 | 34.33 | 1568.8 | 0.4 | 95.2 |
| **mtls1.2-chacha** | 7734.53 | -15.52% | 58.656 | +18.40% | 102.868 | 30.25 | 1581.3 | 0.5 | 94.4 |
| **mtls1.2-cbc** | 7497.46 | -18.11% | 60.802 | +22.73% | 107.653 | 10.15 | 1424.6 | 0.4 | 95.3 |
| **mtls1.3-postquantum** | 8722.39 | -4.73% | 51.509 | +3.97% | 79.770 | 1.32 | 906.4 | 0.3 | 89.3 |

