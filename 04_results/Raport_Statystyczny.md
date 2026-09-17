# Raport Statystyczny Porównania Wydajności mTLS

**Katalog wyników:** `04_results/Summary`
**Baseline:** `plaintext`


### SCENARIUSZ: `baseline`

| Setup | n | RPS mean | RPS CI95 | CV% | avg_ms mean | p95_ms mean | TLS_hs mean(ms) | vs baseline |
|---|---|---|---|---|---|---|---|---|
| **mtls1.2-cbc** | 5 | 2360.2 | [1902.4, 2599.6] | 19.4% | 38.10 | 51.26 | n/a | RPS -15.91% (p=0.076) [szum statystyczny] |
| **mtls1.2-chacha** | 5 | 2788.7 | [2624.4, 2952.9] | 6.7% | 32.80 | 45.82 | n/a | RPS -0.64% (p=0.754) [szum statystyczny] |
| **mtls1.2-gcm** | 2 | 2630.3 | [2628.1, 2632.4] | 0.1% | 34.94 | 53.29 | n/a | RPS -6.29% (p=0.245) [szum statystyczny] |
| **mtls1.3-default** | 5 | 2699.8 | [2530.4, 2869.3] | 7.5% | 33.79 | 48.64 | n/a | RPS -3.81% (p=0.347) [szum statystyczny] |
| **mtls1.3-postquantum** | 5 | 2620.2 | [2609.3, 2630.6] | 0.5% | 34.87 | 53.20 | n/a | RPS -6.65% (p=0.117) [szum statystyczny] |
| **plaintext** | 5 | 2806.7 | [2654.9, 2958.6] | 6.2% | 32.82 | 42.42 | n/a | **-- (baseline) --** |


> ⚠️ **UWAGA:** Setup `mtls1.2-gcm` ma n=2 < 3. Za mało powtórzeń do poprawnej oceny statystycznej.

---

### SCENARIUSZ: `baseline-nokeepalive`

| Setup | n | RPS mean | RPS CI95 | CV% | avg_ms mean | p95_ms mean | TLS_hs mean(ms) | vs baseline |
|---|---|---|---|---|---|---|---|---|
| **mtls1.2-cbc** | 5 | 616.8 | [607.0, 627.8] | 1.9% | 145.79 | 615.64 | n/a | RPS -73.64% (p=0.009) [**ISTOTNE**] |
| **mtls1.2-chacha** | 5 | 622.4 | [608.7, 636.1] | 2.6% | 144.61 | 611.49 | n/a | RPS -73.40% (p=0.009) [**ISTOTNE**] |
| **mtls1.2-gcm** | 2 | 604.9 | [599.8, 610.0] | 0.8% | 148.90 | 655.23 | n/a | RPS -74.14% (p=0.053) [szum statystyczny] |
| **mtls1.3-default** | 5 | 606.3 | [595.0, 618.6] | 2.3% | 148.11 | 620.91 | n/a | RPS -74.09% (p=0.009) [**ISTOTNE**] |
| **mtls1.3-postquantum** | 5 | 594.2 | [592.2, 596.2] | 0.4% | 151.52 | 655.45 | n/a | RPS -74.60% (p=0.009) [**ISTOTNE**] |
| **plaintext** | 5 | 2339.6 | [1870.8, 2674.4] | 19.6% | 39.76 | 50.93 | n/a | **-- (baseline) --** |


> ⚠️ **UWAGA:** Setup `mtls1.2-gcm` ma n=2 < 3. Za mało powtórzeń do poprawnej oceny statystycznej.

---

### SCENARIUSZ: `handshake-nokeepalive`

| Setup | n | RPS mean | RPS CI95 | CV% | avg_ms mean | p95_ms mean | TLS_hs mean(ms) | vs baseline |
|---|---|---|---|---|---|---|---|---|
| **mtls1.2-cbc** | 5 | 609.6 | [604.7, 616.9] | 1.2% | 147.51 | 646.06 | n/a | za malo probek (n<2) |
| **mtls1.2-chacha** | 5 | 634.3 | [631.3, 637.8] | 0.6% | 141.76 | 569.41 | n/a | za malo probek (n<2) |
| **mtls1.2-gcm** | 2 | 611.3 | [608.9, 613.7] | 0.4% | 147.39 | 643.98 | n/a | za malo probek (n<2) |
| **mtls1.3-default** | 5 | 600.8 | [590.9, 610.6] | 1.9% | 149.53 | 640.35 | n/a | za malo probek (n<2) |
| **mtls1.3-postquantum** | 5 | 597.1 | [593.5, 600.9] | 0.7% | 150.61 | 645.70 | n/a | za malo probek (n<2) |
| **plaintext** | 5 | 2614.9 | [2453.2, 2776.5] | 7.4% | 34.93 | 50.90 | n/a | **-- (baseline) --** |


> ⚠️ **UWAGA:** Setup `mtls1.2-gcm` ma n=2 < 3. Za mało powtórzeń do poprawnej oceny statystycznej.

---

### SCENARIUSZ: `payload`

| Setup | n | RPS mean | RPS CI95 | CV% | avg_ms mean | p95_ms mean | TLS_hs mean(ms) | vs baseline |
|---|---|---|---|---|---|---|---|---|
| **mtls1.2-cbc** | 5 | 799.2 | [728.4, 848.7] | 8.9% | 113.21 | 164.68 | n/a | RPS -5.90% (p=0.465) [szum statystyczny] |
| **mtls1.2-chacha** | 5 | 928.4 | [889.5, 951.8] | 4.1% | 97.38 | 131.34 | n/a | RPS +9.31% (p=0.117) [szum statystyczny] |
| **mtls1.2-gcm** | 3 | 847.4 | [839.1, 853.5] | 0.7% | 106.81 | 180.16 | n/a | RPS -0.23% (p=0.881) [szum statystyczny] |
| **mtls1.3-default** | 5 | 887.6 | [846.5, 930.9] | 5.6% | 101.85 | 156.09 | n/a | RPS +4.50% (p=0.347) [szum statystyczny] |
| **mtls1.3-postquantum** | 5 | 864.7 | [846.6, 898.3] | 3.9% | 104.60 | 168.78 | n/a | RPS +1.80% (p=0.465) [szum statystyczny] |
| **plaintext** | 5 | 849.4 | [805.0, 901.8] | 6.8% | 107.07 | 152.36 | n/a | **-- (baseline) --** |

---

### SCENARIUSZ: `payload-nokeepalive`

| Setup | n | RPS mean | RPS CI95 | CV% | avg_ms mean | p95_ms mean | TLS_hs mean(ms) | vs baseline |
|---|---|---|---|---|---|---|---|---|
| **mtls1.2-cbc** | 5 | 536.7 | [525.4, 547.9] | 2.2% | 166.37 | 353.48 | n/a | RPS -37.13% (p=0.009) [**ISTOTNE**] |
| **mtls1.2-chacha** | 5 | 559.4 | [549.6, 565.0] | 1.8% | 160.41 | 523.37 | n/a | RPS -34.47% (p=0.009) [**ISTOTNE**] |
| **mtls1.2-gcm** | 3 | 543.5 | [541.9, 544.6] | 0.2% | 165.46 | 483.80 | n/a | RPS -36.33% (p=0.025) [**ISTOTNE**] |
| **mtls1.3-default** | 5 | 542.4 | [534.5, 551.0] | 1.8% | 164.80 | 403.13 | n/a | RPS -36.46% (p=0.009) [**ISTOTNE**] |
| **mtls1.3-postquantum** | 5 | 536.6 | [531.9, 544.6] | 1.5% | 167.27 | 356.38 | n/a | RPS -37.14% (p=0.009) [**ISTOTNE**] |
| **plaintext** | 5 | 853.7 | [795.0, 912.3] | 8.0% | 106.14 | 144.80 | n/a | **-- (baseline) --** |

---

### SCENARIUSZ: `stress`

| Setup | n | RPS mean | RPS CI95 | CV% | avg_ms mean | p95_ms mean | TLS_hs mean(ms) | vs baseline |
|---|---|---|---|---|---|---|---|---|
| **mtls1.2-cbc** | 5 | 2442.5 | [2428.0, 2454.9] | 0.6% | 182.83 | 267.93 | n/a | RPS -8.57% (p=0.009) [**ISTOTNE**] |
| **mtls1.2-chacha** | 5 | 2663.1 | [2538.3, 2743.5] | 4.6% | 169.15 | 231.11 | n/a | RPS -0.31% (p=0.754) [szum statystyczny] |
| **mtls1.2-gcm** | 2 | 2438.1 | [2412.2, 2464.0] | 1.1% | 184.59 | 284.70 | n/a | RPS -8.74% (p=0.053) [szum statystyczny] |
| **mtls1.3-default** | 5 | 2515.8 | [2436.1, 2628.8] | 4.6% | 178.83 | 270.36 | n/a | RPS -5.83% (p=0.076) [szum statystyczny] |
| **mtls1.3-postquantum** | 5 | 2445.6 | [2425.6, 2460.8] | 0.9% | 183.91 | 283.70 | n/a | RPS -8.45% (p=0.009) [**ISTOTNE**] |
| **plaintext** | 5 | 2671.5 | [2553.8, 2785.2] | 5.1% | 169.06 | 237.99 | n/a | **-- (baseline) --** |


> ⚠️ **UWAGA:** Setup `mtls1.2-gcm` ma n=2 < 3. Za mało powtórzeń do poprawnej oceny statystycznej.

---
