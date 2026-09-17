# Pełny Raport Statystyczny (RPS, CPU, Latency)
**Timestamp:** `20260911_170350`
**Baseline:** `mtls1.3-default`

### SCENARIUSZ: `baseline`

| Setup | n | RPS mean | Proxy CPU (m) | Latency Avg (ms) | Δ RPS | Δ CPU | Δ Latency |
|---|---|---|---|---|---|---|---|
| **mtls1.3-default** | 5 | 2699.8 | 742.8 | 33.79 | - (baza) | - (baza) | - (baza) |
| **mtls1.2-gcm** | 2 | 2630.3 | 754.9 | 34.94 | -2.6% (szum) | +1.6% (szum) | +3.4% (szum) |
| **mtls1.2-chacha** | 5 | 2788.7 | 757.6 | 32.80 | +3.3% (szum) | +2.0% (szum) | -2.9% (szum) |
| **mtls1.2-cbc** | 5 | 2360.2 | 663.8 | 38.10 | -12.6% (szum) | -10.6% (szum) | +12.8% (szum) |
| **mtls1.3-postquantum** | 5 | 2620.2 | 781.8 | 34.87 | -3.0% (szum) | +5.3% (szum) | +3.2% (szum) |

---

### SCENARIUSZ: `baseline-nokeepalive`

| Setup | n | RPS mean | Proxy CPU (m) | Latency Avg (ms) | Δ RPS | Δ CPU | Δ Latency |
|---|---|---|---|---|---|---|---|
| **mtls1.3-default** | 5 | 606.3 | 1653.1 | 148.11 | - (baza) | - (baza) | - (baza) |
| **mtls1.2-gcm** | 2 | 604.9 | 1420.4 | 148.90 | -0.2% (szum) | -14.1% (szum) | +0.5% (szum) |
| **mtls1.2-chacha** | 5 | 622.4 | 1532.9 | 144.61 | +2.7% (szum) | -7.3% (szum) | -2.4% (szum) |
| **mtls1.2-cbc** | 5 | 616.8 | 1553.4 | 145.79 | +1.7% (szum) | -6.0% (szum) | -1.6% (szum) |
| **mtls1.3-postquantum** | 5 | 594.2 | 1564.5 | 151.52 | -2.0% (szum) | -5.4% (szum) | +2.3% (szum) |

---

### SCENARIUSZ: `payload`

| Setup | n | RPS mean | Proxy CPU (m) | Latency Avg (ms) | Δ RPS | Δ CPU | Δ Latency |
|---|---|---|---|---|---|---|---|
| **mtls1.3-default** | 5 | 887.6 | 605.8 | 101.85 | - (baza) | - (baza) | - (baza) |
| **mtls1.2-gcm** | 3 | 847.4 | 669.4 | 106.81 | -4.5% (szum) | +10.5% (szum) | +4.9% (szum) |
| **mtls1.2-chacha** | 5 | 928.4 | 704.9 | 97.38 | +4.6% (szum) | +16.4% (szum) | -4.4% (szum) |
| **mtls1.2-cbc** | 5 | 799.2 | 733.0 | 113.21 | -10.0% (szum) | +21.0% (szum) | +11.2% (szum) |
| **mtls1.3-postquantum** | 5 | 864.7 | 665.3 | 104.60 | -2.6% (szum) | +9.8% (szum) | +2.7% (szum) |

---

### SCENARIUSZ: `payload-nokeepalive`

| Setup | n | RPS mean | Proxy CPU (m) | Latency Avg (ms) | Δ RPS | Δ CPU | Δ Latency |
|---|---|---|---|---|---|---|---|
| **mtls1.3-default** | 5 | 542.4 | 1374.3 | 164.80 | - (baza) | - (baza) | - (baza) |
| **mtls1.2-gcm** | 3 | 543.5 | 1372.3 | 165.46 | +0.2% (szum) | -0.1% (szum) | +0.4% (szum) |
| **mtls1.2-chacha** | 5 | 559.4 | 1386.7 | 160.41 | +3.1% (**ISTOTNE**) | +0.9% (szum) | -2.7% (szum) |
| **mtls1.2-cbc** | 5 | 536.7 | 1396.1 | 166.37 | -1.0% (szum) | +1.6% (szum) | +1.0% (szum) |
| **mtls1.3-postquantum** | 5 | 536.6 | 1374.5 | 167.27 | -1.1% (szum) | +0.0% (szum) | +1.5% (szum) |

---

### SCENARIUSZ: `stress`

| Setup | n | RPS mean | Proxy CPU (m) | Latency Avg (ms) | Δ RPS | Δ CPU | Δ Latency |
|---|---|---|---|---|---|---|---|
| **mtls1.3-default** | 5 | 2515.8 | 842.0 | 178.83 | - (baza) | - (baza) | - (baza) |
| **mtls1.2-gcm** | 2 | 2438.1 | 883.6 | 184.59 | -3.1% (szum) | +4.9% (szum) | +3.2% (szum) |
| **mtls1.2-chacha** | 5 | 2663.1 | 855.4 | 169.15 | +5.9% (szum) | +1.6% (szum) | -5.4% (szum) |
| **mtls1.2-cbc** | 5 | 2442.5 | 820.3 | 182.83 | -2.9% (szum) | -2.6% (szum) | +2.2% (szum) |
| **mtls1.3-postquantum** | 5 | 2445.6 | 773.0 | 183.91 | -2.8% (szum) | -8.2% (szum) | +2.8% (szum) |

---

