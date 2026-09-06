# Performance Comparison Report
Generated for test run: `20260901_090914`

This report compares the performance of different mutual TLS configurations in Istio:

- **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)
- **mTLS 1.2 (AES-GCM)**: ECDHE-ECDSA-AES128-GCM-SHA256
- **mTLS 1.2 (ChaCha20)**: ECDHE-ECDSA-CHACHA20-POLY1305-SHA256
- **mTLS 1.2 (AES-CBC)**: ECDHE-ECDSA-AES128-SHA256 (CBC mode)

- **mTLS 1.3 (Post-Quantum)**: X25519MLKEM768 (Hybrid Kyber Key Exchange)

## TLS Verification (live sidecar stats, not just the applied CR)

- **mtls1.3-default**: `TLS_AES_128_GCM_SHA256`=497068, `X25519`=497068
- **mtls1.2-gcm**: `ECDHE-RSA-AES128-GCM-SHA256`=504734, `X25519`=504734
- **mtls1.2-chacha**: `ECDHE-RSA-CHACHA20-POLY1305`=507812, `X25519`=507812
- **mtls1.2-cbc**: `ECDHE-RSA-AES128-SHA256`=505418, `X25519`=505418
- **mtls1.3-postquantum**: `TLS_AES_128_GCM_SHA256`=496022, `X25519MLKEM768`=496022


## Scenario: BASELINE
## Scenario: BASELINE-NOKEEPALIVE
## Scenario: PAYLOAD
## Scenario: PAYLOAD-NOKEEPALIVE
## Scenario: STRESS