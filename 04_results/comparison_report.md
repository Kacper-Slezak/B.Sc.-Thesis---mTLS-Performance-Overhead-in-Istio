# Performance Comparison Report
Generated for test run: `20260823_174659`

This report compares the performance of different mutual TLS configurations in Istio:

- **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)
- **mTLS 1.2 (AES-GCM)**: ECDHE-ECDSA-AES128-GCM-SHA256
- **mTLS 1.2 (ChaCha20)**: ECDHE-ECDSA-CHACHA20-POLY1305-SHA256
- **mTLS 1.2 (AES-CBC)**: ECDHE-ECDSA-AES128-SHA256 (CBC mode)

## TLS Verification (live sidecar stats, not just the applied CR)

- **mtls1.3-default**: no cipher_stats snapshot found for this run (run_all_test.sh must call capture_cipher_stats before/after this setup).
- **mtls1.2-gcm**: no cipher_stats snapshot found for this run (run_all_test.sh must call capture_cipher_stats before/after this setup).
- **mtls1.2-chacha**: no cipher_stats snapshot found for this run (run_all_test.sh must call capture_cipher_stats before/after this setup).
- **mtls1.2-cbc**: no cipher_stats snapshot found for this run (run_all_test.sh must call capture_cipher_stats before/after this setup).

*No cipher verification data found at all -- see run_all_test.sh changes to enable capture_cipher_stats.*


## Scenario: BASELINE
## Scenario: BASELINE-NOKEEPALIVE
## Scenario: PAYLOAD
## Scenario: PAYLOAD-NOKEEPALIVE
## Scenario: STRESS