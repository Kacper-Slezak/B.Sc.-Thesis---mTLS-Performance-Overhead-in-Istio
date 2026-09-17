    # Performance Comparison Report
    Generated for test run: `20260911_170350`

    This report compares the performance of different mutual TLS configurations in Istio:

    - **Plaintext**: Zwykly ruch HTTP (brak mTLS)
    - **mTLS 1.3 (Default)**: TLS_AES_256_GCM_SHA384 (Default Istio cipher suite)
    - **mTLS 1.2 (AES-GCM)**: ECDHE-ECDSA-AES128-GCM-SHA256
    - **mTLS 1.2 (ChaCha20)**: ECDHE-ECDSA-CHACHA20-POLY1305-SHA256
    - **mTLS 1.2 (AES-CBC)**: ECDHE-ECDSA-AES128-SHA256 (CBC mode)

    - **mTLS 1.3 (Post-Quantum)**: X25519MLKEM768 (Hybrid Kyber Key Exchange)

    ## TLS Verification (live sidecar stats)

    - **mtls1.3-default**: `TLS_AES_128_GCM_SHA256`=1456589, `X25519`=1456589
    - **mtls1.2-gcm**: Brak nowych handshake'ów lub brakuje zrzutu /stats (test mógł zostać przerwany skrótem ^C).
    - **mtls1.2-chacha**: `ECDHE-RSA-CHACHA20-POLY1305`=1512018, `X25519`=1512018
    - **mtls1.2-cbc**: `ECDHE-RSA-AES128-SHA256`=1475672, `X25519`=1475672
    - **mtls1.3-postquantum**: `TLS_AES_128_GCM_SHA256`=1438955, `X25519`=1438955


    ## Scenario: BASELINE
    | Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
    | **plaintext** | 2657.68 | - | 34.517 | - | 40.554 | 0.00 | 550.9 | 659.6 | 98.5 |
    | **mtls1.3-default** | 2564.15 | -3.52% | 35.373 | +2.48% | 56.245 | 0.00 | 688.2 | 845.4 | 96.3 |
    | **mtls1.2-gcm** | 2632.44 | -0.95% | 34.836 | +0.92% | 52.888 | 0.54 | 703.1 | 846.2 | 99.5 |
    | **mtls1.2-chacha** | 2983.39 | +12.26% | 30.484 | -11.68% | 38.711 | 25.09 | 840.5 | 776.5 | 96.8 |
    | **mtls1.2-cbc** | 1445.46 | -45.61% | 50.540 | +46.42% | 39.892 | 0.00 | 389.1 | 455.5 | 80.4 |
    | **mtls1.3-postquantum** | 2620.45 | -1.40% | 34.815 | +0.86% | 53.431 | 0.58 | 685.6 | 871.3 | 99.4 |


    ## Scenario: BASELINE-NOKEEPALIVE
    | Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
    | **plaintext** | 1461.23 | - | 55.739 | - | 43.331 | 0.00 | 388.5 | 458.8 | 98.4 |
    | **mtls1.3-default** | 596.95 | -59.15% | 150.437 | +169.90% | 655.333 | 495.59 | 1538.6 | 385.2 | 100.1 |
    | **mtls1.2-gcm** | 610.03 | -58.25% | 147.350 | +164.36% | 650.859 | 498.94 | 1489.7 | 303.2 | 103.4 |
    | **mtls1.2-chacha** | 640.77 | -56.15% | 140.492 | +152.05% | 558.370 | 543.20 | 1547.3 | 269.6 | 102.6 |
    | **mtls1.2-cbc** | 635.79 | -56.49% | 145.563 | +161.15% | 571.107 | 598.09 | 1624.0 | 241.5 | 69.9 |
    | **mtls1.3-postquantum** | 592.18 | -59.47% | 151.890 | +172.50% | 641.045 | 544.51 | 1635.6 | 366.4 | 103.8 |


    ## Scenario: PAYLOAD
    | Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
    | **plaintext** | 803.80 | - | 112.645 | - | 141.269 | 0.00 | 349.6 | 795.2 | 99.5 |
    | **mtls1.3-default** | 851.10 | +5.88% | 105.816 | -6.06% | 180.450 | 27.51 | 673.7 | 813.3 | 99.0 |
    | **mtls1.2-gcm** | 839.07 | +4.39% | 107.833 | -4.27% | 181.275 | 29.36 | 648.0 | 811.9 | 100.7 |
    | **mtls1.2-chacha** | 939.28 | +16.86% | 96.055 | -14.73% | 121.664 | 0.00 | 562.8 | 843.7 | 97.7 |
    | **mtls1.2-cbc** | 797.73 | -0.75% | 112.309 | -0.30% | 139.779 | 23.24 | 744.1 | 715.2 | 62.8 |
    | **mtls1.3-postquantum** | 847.60 | +5.45% | 106.465 | -5.49% | 180.345 | 25.25 | 666.5 | 827.1 | 99.5 |


    ## Scenario: PAYLOAD-NOKEEPALIVE
    | Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
    | **plaintext** | 787.22 | - | 114.713 | - | 147.482 | 0.00 | 361.4 | 804.5 | 100.2 |
    | **mtls1.3-default** | 534.26 | -32.13% | 167.192 | +45.75% | 291.962 | 448.27 | 1431.1 | 587.8 | 101.9 |
    | **mtls1.2-gcm** | 544.05 | -30.89% | 164.307 | +43.23% | 470.745 | 435.66 | 1348.5 | 588.5 | 104.9 |
    | **mtls1.2-chacha** | 564.11 | -28.34% | 158.295 | +37.99% | 582.474 | 457.78 | 1390.4 | 545.2 | 101.1 |
    | **mtls1.2-cbc** | 555.52 | -29.43% | 161.619 | +40.89% | 550.152 | 426.99 | 1289.1 | 622.0 | 87.4 |
    | **mtls1.3-postquantum** | 530.66 | -32.59% | 169.462 | +47.73% | 316.010 | 421.18 | 1305.0 | 632.1 | 104.1 |


    ## Scenario: STRESS
    | Setup | RPS | RPS Diff | Latency Avg (ms) | Latency Diff | Latency P95 (ms) | TLS Handshakes (rate/s) | Proxy CPU (m) | App CPU (m) | Proxy Mem (MB) |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
    | **plaintext** | 2781.66 | - | 161.977 | - | 213.183 | 0.00 | 699.2 | 873.0 | 99.8 |
    | **mtls1.3-default** | 2408.25 | -13.42% | 186.276 | +15.00% | 288.434 | 50.16 | 884.0 | 877.9 | 98.3 |
    | **mtls1.2-gcm** | 2463.96 | -11.42% | 182.785 | +12.85% | 283.965 | 47.72 | 896.3 | 830.4 | 101.4 |
    | **mtls1.2-chacha** | 2726.23 | -1.99% | 164.918 | +1.82% | 218.874 | 48.57 | 901.0 | 855.9 | 98.7 |
    | **mtls1.2-cbc** | 2434.71 | -12.47% | 181.037 | +11.77% | 211.605 | 2.31 | 662.8 | 764.4 | 77.9 |
    | **mtls1.3-postquantum** | 2467.74 | -11.29% | 182.272 | +12.53% | 281.790 | 2.41 | 746.0 | 896.7 | 98.4 |


    ====================================================================================================
    SCENARIUSZ: baseline
    ====================================================================================================
    setup                     n    RPS mean              RPS CI95    CV%   avg_ms mean   p95_ms mean   TLS_hs mean(ms)                 vs baseline
    ----------------------------------------------------------------------------------------------------------------------------------------------
    mtls1.2-cbc               5      2360.2      [1902.4, 2599.6]  19.4%         38.10         51.26               n/a  RPS -15.91% p=0.076 [brak podstaw (szum)]
    mtls1.2-chacha            5      2788.7      [2624.4, 2952.9]   6.7%         32.80         45.82               n/a  RPS -0.64% p=0.754 [brak podstaw (szum)]
    mtls1.2-gcm               2      2630.3      [2628.1, 2632.4]   0.1%         34.94         53.29               n/a  RPS -6.29% p=0.245 [brak podstaw (szum)]
        UWAGA: n=2 < 3 - za malo powtorzen zeby cokolwiek sensownie wnioskowac o tym setupie/scenariuszu.
    mtls1.3-default           5      2699.8      [2530.4, 2869.3]   7.5%         33.79         48.64               n/a  RPS -3.81% p=0.347 [brak podstaw (szum)]
    mtls1.3-postquantum       5      2620.2      [2609.3, 2630.6]   0.5%         34.87         53.20               n/a  RPS -6.65% p=0.117 [brak podstaw (szum)]
    plaintext                 5      2806.7      [2654.9, 2958.6]   6.2%         32.82         42.42               n/a  -- (baseline) --

    ====================================================================================================
    SCENARIUSZ: baseline-nokeepalive
    ====================================================================================================
    setup                     n    RPS mean              RPS CI95    CV%   avg_ms mean   p95_ms mean   TLS_hs mean(ms)                 vs baseline
    ----------------------------------------------------------------------------------------------------------------------------------------------
    mtls1.2-cbc               5       616.8        [607.0, 627.8]   1.9%        145.79        615.64               n/a  RPS -73.64% p=0.009 [ISTOTNE]
    mtls1.2-chacha            5       622.4        [608.7, 636.1]   2.6%        144.61        611.49               n/a  RPS -73.40% p=0.009 [ISTOTNE]
    mtls1.2-gcm               2       604.9        [599.8, 610.0]   0.8%        148.90        655.23               n/a  RPS -74.14% p=0.053 [brak podstaw (szum)]
        UWAGA: n=2 < 3 - za malo powtorzen zeby cokolwiek sensownie wnioskowac o tym setupie/scenariuszu.
    mtls1.3-default           5       606.3        [595.0, 618.6]   2.3%        148.11        620.91               n/a  RPS -74.09% p=0.009 [ISTOTNE]
    mtls1.3-postquantum       5       594.2        [592.2, 596.2]   0.4%        151.52        655.45               n/a  RPS -74.60% p=0.009 [ISTOTNE]
    plaintext                 5      2339.6      [1870.8, 2674.4]  19.6%         39.76         50.93               n/a  -- (baseline) --

    ====================================================================================================
    SCENARIUSZ: handshake-nokeepalive
    ====================================================================================================
    setup                     n    RPS mean              RPS CI95    CV%   avg_ms mean   p95_ms mean   TLS_hs mean(ms)                 vs baseline
    ----------------------------------------------------------------------------------------------------------------------------------------------
    mtls1.2-cbc               5       609.6        [604.7, 616.9]   1.2%        147.51        646.06               n/a  za malo probek (n<2)
    mtls1.2-chacha            5       634.3        [631.3, 637.8]   0.6%        141.76        569.41               n/a  za malo probek (n<2)
    mtls1.2-gcm               2       611.3        [608.9, 613.7]   0.4%        147.39        643.98               n/a  za malo probek (n<2)
        UWAGA: n=2 < 3 - za malo powtorzen zeby cokolwiek sensownie wnioskowac o tym setupie/scenariuszu.
    mtls1.3-default           5       600.8        [590.9, 610.6]   1.9%        149.53        640.35               n/a  za malo probek (n<2)
    mtls1.3-postquantum       5       597.1        [593.5, 600.9]   0.7%        150.61        645.70               n/a  za malo probek (n<2)
    plaintext                 5      2614.9      [2453.2, 2776.5]   7.4%         34.93         50.90               n/a  -- (baseline) --

    ====================================================================================================
    SCENARIUSZ: payload
    ====================================================================================================
    setup                     n    RPS mean              RPS CI95    CV%   avg_ms mean   p95_ms mean   TLS_hs mean(ms)                 vs baseline
    ----------------------------------------------------------------------------------------------------------------------------------------------
    mtls1.2-cbc               5       799.2        [728.4, 848.7]   8.9%        113.21        164.68               n/a  RPS -5.90% p=0.465 [brak podstaw (szum)]
    mtls1.2-chacha            5       928.4        [889.5, 951.8]   4.1%         97.38        131.34               n/a  RPS +9.31% p=0.117 [brak podstaw (szum)]
    mtls1.2-gcm               3       847.4        [839.1, 853.5]   0.7%        106.81        180.16               n/a  RPS -0.23% p=0.881 [brak podstaw (szum)]
    mtls1.3-default           5       887.6        [846.5, 930.9]   5.6%        101.85        156.09               n/a  RPS +4.50% p=0.347 [brak podstaw (szum)]
    mtls1.3-postquantum       5       864.7        [846.6, 898.3]   3.9%        104.60        168.78               n/a  RPS +1.80% p=0.465 [brak podstaw (szum)]
    plaintext                 5       849.4        [805.0, 901.8]   6.8%        107.07        152.36               n/a  -- (baseline) --

    ====================================================================================================
    SCENARIUSZ: payload-nokeepalive
    ====================================================================================================
    setup                     n    RPS mean              RPS CI95    CV%   avg_ms mean   p95_ms mean   TLS_hs mean(ms)                 vs baseline
    ----------------------------------------------------------------------------------------------------------------------------------------------
    mtls1.2-cbc               5       536.7        [525.4, 547.9]   2.2%        166.37        353.48               n/a  RPS -37.13% p=0.009 [ISTOTNE]
    mtls1.2-chacha            5       559.4        [549.6, 565.0]   1.8%        160.41        523.37               n/a  RPS -34.47% p=0.009 [ISTOTNE]
    mtls1.2-gcm               3       543.5        [541.9, 544.6]   0.2%        165.46        483.80               n/a  RPS -36.33% p=0.025 [ISTOTNE]
    mtls1.3-default           5       542.4        [534.5, 551.0]   1.8%        164.80        403.13               n/a  RPS -36.46% p=0.009 [ISTOTNE]
    mtls1.3-postquantum       5       536.6        [531.9, 544.6]   1.5%        167.27        356.38               n/a  RPS -37.14% p=0.009 [ISTOTNE]
    plaintext                 5       853.7        [795.0, 912.3]   8.0%        106.14        144.80               n/a  -- (baseline) --

    ====================================================================================================
    SCENARIUSZ: stress
    ====================================================================================================
    setup                     n    RPS mean              RPS CI95    CV%   avg_ms mean   p95_ms mean   TLS_hs mean(ms)                 vs baseline
    ----------------------------------------------------------------------------------------------------------------------------------------------
    mtls1.2-cbc               5      2442.5      [2428.0, 2454.9]   0.6%        182.83        267.93               n/a  RPS -8.57% p=0.009 [ISTOTNE]
    mtls1.2-chacha            5      2663.1      [2538.3, 2743.5]   4.6%        169.15        231.11               n/a  RPS -0.31% p=0.754 [brak podstaw (szum)]
    mtls1.2-gcm               2      2438.1      [2412.2, 2464.0]   1.1%        184.59        284.70               n/a  RPS -8.74% p=0.053 [brak podstaw (szum)]
        UWAGA: n=2 < 3 - za malo powtorzen zeby cokolwiek sensownie wnioskowac o tym setupie/scenariuszu.
    mtls1.3-default           5      2515.8      [2436.1, 2628.8]   4.6%        178.83        270.36               n/a  RPS -5.83% p=0.076 [brak podstaw (szum)]
    mtls1.3-postquantum       5      2445.6      [2425.6, 2460.8]   0.9%        183.91        283.70               n/a  RPS -8.45% p=0.009 [ISTOTNE]
    plaintext                 5      2671.5      [2553.8, 2785.2]   5.1%        169.06        237.99               n/a  -- (baseline) --
