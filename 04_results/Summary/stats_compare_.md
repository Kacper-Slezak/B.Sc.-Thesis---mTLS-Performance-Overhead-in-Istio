# mTLS Performance Statistical Comparison Report

**Results Directory:** `04_results/Summary`  
**CPU/RAM Metrics Directory:** `04_results/Metrics`  
**Baseline:** `plaintext`

## Live Negotiated TLS Verification (before/after telemetry evidence)

Verified using Envoy counters `ssl.ciphers.*` / `ssl.curves.*` from admin port 15000 - a counter increase during the test window confirms that this cipher/curve was negotiated in practice, rather than merely configured in YAML.

| Setup | Expected | Delta Detected? | Status |
|---|---|---|---|
| **mtls1.2-gcm** | cipher contains `AES128-GCM` | YES | PASS |
| **mtls1.2-gcm256** | cipher contains `AES256-GCM` | YES | PASS |
| **mtls1.2-chacha** | cipher contains `CHACHA20` | YES | PASS |
| **mtls1.2-cbc** | cipher contains `AES128-SHA256` | YES | PASS |
| **mtls1.2-ccm** | - | - | WARNING: 'before' file not found |
| **mtls1.3-postquantum** | curve contains `MLKEM` | YES | PASS |

> WARNING: At least one setup did not verify the expected TLS configuration in the latest run. Performance results for that setup should not be included in the thesis until investigated.

### SCENARIO: `baseline`

*Comparative metric for this scenario: **RPS** (measuring maximum throughput. Higher RPS is better).*

| Setup | n | RPS mean | avg_ms mean | p95_ms mean | CI95* | CV%* | Proxy CPU(m) | Proxy Mem(MB) | vs baseline |
|---|---|---|---|---|---|---|---|---|---|
| **mtls1.2-cbc** | 3 | 1935.5 | 47.85 | 74.49 | [1932.7, 1940.8] | 0.2% | 1209.3 | 43.5 | RPS -1.72% (p=0.100) [statistical noise] |
| **mtls1.2-chacha** | 3 | 1948.0 | 47.43 | 74.08 | [1935.8, 1954.4] | 0.4% | 1177.9 | 43.6 | RPS -1.08% (p=0.400) [statistical noise] |
| **mtls1.2-gcm** | 3 | 1947.2 | 47.27 | 74.29 | [1938.2, 1959.8] | 0.5% | 1134.8 | 41.5 | RPS -1.12% (p=0.200) [statistical noise] |
| **mtls1.2-gcm256** | 3 | 2076.6 | 44.89 | 71.56 | [1951.4, 2261.4] | 6.4% | 911.8 | 40.8 | RPS +5.45% (p=0.400) [statistical noise] |
| **mtls1.3-default** | 3 | 1941.3 | 47.66 | 74.41 | [1929.2, 1958.8] | 0.7% | 1172.2 | 43.2 | RPS -1.42% (p=0.200) [statistical noise] |
| **mtls1.3-postquantum** | 3 | 1747.9 | 54.61 | 83.47 | [1345.0, 1952.4] | 16.3% | 1342.8 | 43.7 | RPS -11.24% (p=0.200) [statistical noise] |
| **plaintext** | 3 | 1969.3 | 47.06 | 72.84 | [1947.2, 1981.4] | 0.8% | 1098.4 | 41.2 | **-- (baseline) --** |

---

### SCENARIO: `baseline-nokeepalive`

*Comparative metric for this scenario: **RPS** (measuring maximum throughput. Higher RPS is better).*

| Setup | n | RPS mean | avg_ms mean | p95_ms mean | CI95* | CV%* | Proxy CPU(m) | Proxy Mem(MB) | vs baseline |
|---|---|---|---|---|---|---|---|---|---|
| **mtls1.2-cbc** | 3 | 1216.4 | 75.52 | 115.17 | [1210.9, 1222.8] | 0.4% | 1413.1 | 43.0 | RPS -35.61% (p=0.100) [statistical noise] |
| **mtls1.2-chacha** | 3 | 1237.8 | 74.13 | 112.09 | [1229.1, 1250.0] | 0.7% | 1381.9 | 43.3 | RPS -34.47% (p=0.100) [statistical noise] |
| **mtls1.2-gcm** | 3 | 1253.2 | 73.08 | 112.28 | [1250.1, 1255.4] | 0.2% | 1375.7 | 41.5 | RPS -33.65% (p=0.100) [statistical noise] |
| **mtls1.2-gcm256** | 3 | 1792.1 | 54.38 | 85.44 | [1228.3, 2075.3] | 22.2% | 1098.0 | 49.3 | RPS -5.13% (p=0.700) [statistical noise] |
| **mtls1.3-default** | 3 | 768.0 | 119.92 | 189.53 | [761.6, 773.5] | 0.6% | 1451.2 | 43.2 | RPS -59.34% (p=0.100) [statistical noise] |
| **mtls1.3-postquantum** | 3 | 713.6 | 129.40 | 212.69 | [712.6, 715.4] | 0.2% | 1428.5 | 43.7 | RPS -62.22% (p=0.100) [statistical noise] |
| **plaintext** | 3 | 1889.0 | 48.44 | 75.24 | [1884.4, 1895.3] | 0.2% | 1114.1 | 42.0 | **-- (baseline) --** |

---

*A total of 12 significance tests (Mann-Whitney U) were conducted in this report, each at alpha=0.05 without multiple comparison correction. With this number of tests, one should statistically expect approximately 0.6 false positives purely by chance - this is worth noting in the thesis methodology limitations, or applying a Bonferroni correction (alpha_corrected = 0.05 / 12 = 0.0042).*
