# Performance Comparison Report
Generated for test run: `20260920_194046`

This report compares the performance of different mutual TLS configurations in Istio:

- **Plaintext**: Zwykly ruch HTTP (brak mTLS)
- **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)
- **mTLS 1.2 (AES-GCM)**: ECDHE-ECDSA-AES128-GCM-SHA256
- **mTLS 1.2 (ChaCha20)**: ECDHE-ECDSA-CHACHA20-POLY1305-SHA256
- **mTLS 1.2 (AES-CBC)**: ECDHE-ECDSA-AES128-SHA256 (CBC mode)

- **mTLS 1.3 (Post-Quantum)**: X25519MLKEM768 (Hybrid Kyber Key Exchange)

## TLS Verification (live sidecar stats)

- **mtls1.3-default**: `TLS_AES_128_GCM_SHA256`=383039, `X25519`=383039
- **mtls1.2-gcm**: `ECDHE-RSA-AES128-GCM-SHA256`=625166, `X25519`=625166
- **mtls1.2-chacha**: `ECDHE-RSA-CHACHA20-POLY1305`=618729, `X25519`=618729
- **mtls1.2-cbc**: `ECDHE-RSA-AES128-SHA256`=606635, `X25519`=606635
- **mtls1.3-postquantum**: `TLS_AES_128_GCM_SHA256`=356054, `X25519MLKEM768`=356054


## Scenario: BASELINE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 1981.45 | - | 46.740 | - | 73.114 | 0.00 | 1101.6 | 0.5 | 40.9 |
| **mtls1.3-default** | 1958.77 | -1.14% | 47.210 | +1.01% | 73.802 | 0.57 | 1129.8 | 0.6 | 43.5 |
| **mtls1.2-gcm** | 1943.62 | -1.91% | 47.335 | +1.27% | 74.341 | 0.56 | 1178.4 | 0.6 | 40.3 |
| **mtls1.2-chacha** | 1953.95 | -1.39% | 47.283 | +1.16% | 73.908 | 23.21 | 1210.1 | 0.5 | 44.1 |
| **mtls1.2-cbc** | 1933.04 | -2.44% | 48.006 | +2.71% | 74.601 | 0.54 | 1167.7 | 0.5 | 42.6 |
| **mtls1.3-postquantum** | 1946.17 | -1.78% | 47.565 | +1.76% | 74.210 | 0.57 | 1178.8 | 0.6 | 43.7 |


## Scenario: BASELINE-NOKEEPALIVE
| Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 1887.26 | - | 48.374 | - | 75.474 | 0.00 | 1130.4 | 0.6 | 42.8 |
| **mtls1.3-default** | 768.93 | -59.26% | 119.729 | +147.51% | 188.980 | 607.79 | 1434.9 | 0.5 | 43.4 |
| **mtls1.2-gcm** | 1255.38 | -33.48% | 72.936 | +50.78% | 113.324 | 1004.37 | 1398.1 | 0.5 | 40.4 |
| **mtls1.2-chacha** | 1234.38 | -34.59% | 74.487 | +53.98% | 113.824 | 995.34 | 1360.6 | 0.6 | 43.7 |
| **mtls1.2-cbc** | 1222.77 | -35.21% | 75.080 | +55.21% | 114.659 | 957.13 | 1395.3 | 0.5 | 42.2 |
| **mtls1.3-postquantum** | 712.78 | -62.23% | 130.216 | +169.19% | 212.965 | 566.55 | 1423.6 | 0.5 | 44.5 |


## Scenario: PAYLOAD
*Brak danych dla tego scenariusza.*

## Scenario: PAYLOAD-NOKEEPALIVE
*Brak danych dla tego scenariusza.*

## Scenario: STRESS
*Brak danych dla tego scenariusza.*
