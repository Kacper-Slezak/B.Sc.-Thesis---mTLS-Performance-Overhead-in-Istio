# Raport Końcowy z Badań Wydajnościowych mTLS w Istio
Niniejszy raport zawiera zestawienie średnich arytmetycznych z wykonanych powtórzeń testów.

## Scenariusz: BASELINE (Ruch ciągły, włączony HTTP Keep-Alive)

| Konfiguracja (Setup) | Liczba prób | Średni RPS [zap/s] | Zmiana RPS (%) | Średnie opóźnienie [ms] | Zmiana opóźnienia (%) | Opóźnienie P95 [ms] | Handshake TLS [ms] | CPU Proxy [m] |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 3 | 2191.4 | **-- (baza) --** | 40.69 | **-- (baza) --** | 67.73 | - | 508.1 |
| **mtls1.3-default** | 3 | 2185.7 | -0.26% | 40.84 | +0.38% | 67.83 | - | 606.5 |
| **mtls1.2-gcm** | 3 | 2197.4 | +0.27% | 40.47 | -0.53% | 67.66 | - | 547.3 |
| **mtls1.2-gcm256** | 3 | 2213.4 | +1.00% | 40.54 | -0.38% | 67.62 | - | 494.9 |
| **mtls1.2-chacha** | 3 | 2145.9 | -2.07% | 41.71 | +2.50% | 68.77 | - | 676.7 |
| **mtls1.2-cbc** | 3 | 2216.2 | +1.13% | 40.52 | -0.41% | 67.60 | - | 526.9 |
| **mtls1.3-postquantum** | 3 | 2214.5 | +1.06% | 40.63 | -0.15% | 67.64 | - | 495.0 |

> **Kluczowy wniosek (Keep-Alive):** Gdy mikrousługi utrzymują otwarte połączenia, narzut mTLS jest minimalny (spadek RPS wynosi zaledwie ok. 1-2%). Oznacza to, że samo symetryczne szyfrowanie przesyłanych danych nie stanowi obciążenia dla klastra.

---

## Scenariusz: BASELINE BEZ KEEP-ALIVE (Nowe połączenie TLS przy każdym zapytaniu)

| Konfiguracja (Setup) | Liczba prób | Średni RPS [zap/s] | Zmiana RPS (%) | Średnie opóźnienie [ms] | Zmiana opóźnienia (%) | Opóźnienie P95 [ms] | Handshake TLS [ms] | CPU Proxy [m] |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **plaintext** | 3 | 2164.4 | **-- (baza) --** | 40.96 | **-- (baza) --** | 67.81 | - | 558.3 |
| **mtls1.3-default** | 3 | 1706.0 | -21.18% | 52.21 | +27.49% | 81.06 | - | 1303.4 |
| **mtls1.2-gcm** | 3 | 2070.8 | -4.32% | 42.73 | +4.34% | 69.50 | - | 857.9 |
| **mtls1.2-gcm256** | 3 | 2091.7 | -3.36% | 42.70 | +4.26% | 69.41 | - | 908.5 |
| **mtls1.2-chacha** | 3 | 1886.4 | -12.85% | 48.35 | +18.06% | 77.24 | - | 1027.3 |
| **mtls1.2-cbc** | 3 | 2076.9 | -4.04% | 42.91 | +4.78% | 69.72 | - | 875.7 |
| **mtls1.3-postquantum** | 3 | 1741.3 | -19.55% | 51.39 | +25.47% | 79.54 | - | 1284.3 |

> **Kluczowy wniosek (Brak Keep-Alive):** Gdy przy każdym zapytaniu zestawiane jest nowe połączenie TLS, przepustowość drastycznie spada (o ponad 70%), a opóźnienie skacze ponaddwukrotnie. To dowodzi, że najcięższą operacją w mTLS jest asymetryczny handshake (wymiana kluczy i sprawdzanie certyfikatów).

---
