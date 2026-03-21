# Praca Inżynierska: Badanie narzutu wydajnościowego kryptografii mTLS w środowisku Istio

## 1. Struktura repozytorium

Wszystkie skrypty i wyniki są zorganizowane w następujący sposób:

* `1_skrypty/` - Skrypty bash automatyzujące stawianie klastra (k3d) i instalację narzędzi (Istio, Prometheus, Grafana).
* `2_yaml_mainfest/` - Konfiguracje Kubernetes/Istio (np. wymuszanie wersji TLS, polityki autoryzacji).
* `3_wyniki/` - Wyeksportowane raporty z narzędzia K6 (pliki JSON).
* `4_testy_js/` - Skrypty testowe dla narzędzia K6 (scenariusze obciążeniowe).

## 2. Instrukcja odtworzenia środowiska badawczego

Aby powtórzyć badania od zera, należy:

1. Upewnić się, że uruchomiony jest Docker Desktop.
2. Otworzyć terminal (Git Bash).
3. Uruchomić skrypt startowy:

   ```bash
   ./1_skrypty/setup_cluster.sh
   ```

4. Zapisać nazwę wygenerowanego Poda K6 do zmiennej:

   ```bash
   K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
   ```

## 3. Dziennik pomiarów i testów

### Etap 1: Środowisko bazowe (Domyślny mTLS 1.3)

**Cel:** Zmierzenie czystego narzutu klastra dla domyślnej, najsilniejszej konfiguracji kryptograficznej (AES-GCM).

* **Test lekki** (Dużo zapytań, mały payload):
  * Skrypt: `4_testy_js/test_lekki.js` (500 QPS / 30s)
  * Wynik: `3_wyniki/podsumowanie_lekki_mtls13.json`
* **Test ciężki** (Mniej zapytań, duży payload 50 KB):
  * Skrypt: `4_testy_js/test_ciezki.js` (200 QPS / 60s)
  * Wynik: `3_wyniki/podsumowanie_ciezki_mtls13.json`

### Etap 2: Odporność na manipulację (Próba wymuszenia TLS 1.2 i słabych szyfrów)

**Cel:** Zbadanie zachowania klastra przy próbie obniżenia standardów kryptograficznych (tzw. downgrade attack) poprzez wymuszenie protokołu TLS 1.2 oraz przestarzałego szyfru.

#### Próba 1: Użycie standardowego API Istio (Nieudana)

W pierwszej kolejności podjęto próbę rekonfiguracji za pomocą standardowego zasobu `DestinationRule`.

**Zastosowany manifest YAML:**
`2_yaml_manifest\wymuszenie_mtls12.yaml`

##### Wiadomość błędu

```bash
$ kubectl apply -f 2_yaml_mainfest/wymuszenie_mtls12.yaml
peerauthentication.security.istio.io/strict-mtls created
Error from server (BadRequest): error when creating "2_yaml_mainfest/wymuszenie_mtls12.yaml": DestinationRule in version "v1alpha3" cannot be handled as a DestinationRule: strict decoding error: unknown field "spec.trafficPolicy.tls.cipherSuites", unknown field "spec.trafficPolicy.tls.maxProtocolVersion", unknown field "spec.trafficPolicy.tls.minProtocolVersion"
```

**Wniosek z Próby 1:** Powyższy błąd jest dowodem na wbudowaną odporność warstwy *control plane* Istio (Istiod) na błędy konfiguracyjne obniżające bezpieczeństwo. Zespół rozwijający Istio celowo zablokował możliwość swobodnej edycji pół `cipherSuites` oraz `ProtocolVersion` w standardowym API na poziomie `DestinationRule`, aby zapobiec przypadkowemu lub celowemu osłabieniu szyfrowania w Service Meshu.

#### Próba 2: Bezpośrednie wstrzyknięcie konfiguracji do proxy (EnvoyFilter)

W związku z brakiem możliwości edycji szyfrów przez wysokopoziomowe API Istio, podjęto decyzję o użyciu zasobu `EnvoyFilter`. Pozwala on na bezpośrednią ingerencję w natywną konfigurację (tzw. *config patches*) serwerów proxy Envoy działających jako side-cary, omijając restrykcje walidacyjne API Istio.

**Zastosowany manifest YAML (wymuszający TLS 1.2 i słaby szyfr AES128-SHA na serwerze):**
`2_yaml_manifest\envoyfilter_downgrade_mtls12.yaml`

**Wynik testu dla Próby 2:** Test narzędziem K6 (skrypt lekki) zakończył się 100% wskaźnikiem sukcesu (`status is 200`) oraz opóźnieniem rzędu 1.65ms. Oznacza to, że atak się nie powiódł, a system nie obniżył standardu bezpieczeństwa.
Plik z wynikiem: `3_wyniki/podsumowanie_lekki_tls12_odrzucone.json`

**Weryfikacja za pomocą istioctl:**
Aby zrozumieć, dlaczego EnvoyFilter nie zadziałał, wykonano zrzut konfiguracji nasłuchującej (listeners) z serwera `httpbin`:
`istioctl proxy-config listeners $HTTPBIN_POD --port 15006 -o json | grep "tls_maximum_protocol_version"`
Wynik komendy był pusty.

```
kacpe@ViBookS14 MINGW64 ~/Documents/Ważne/Projekty/Praca-In-ynierska (main)
$ istioctl proxy-config listeners $HTTPBIN_POD --port 15006 -o json | grep -A 10 "tls_maximum_protocol_version"

kacpe@ViBookS14 MINGW64 ~/Documents/Ważne/Projekty/Praca-In-ynierska (main)
$ 
```

**Wniosek z Próby 2:** Wewnętrzne mechanizmy bezpieczeństwa Istio chronią porty wejściowe i po cichu odrzucają łatki konfiguracyjne obniżające bezpieczeństwo.

#### Próba 3: Zmiana wektora ataku - nałożenie restrykcji na Klienta (K6)

Zdecydowano się zablokować klientowi możliwość korzystania z silnej kryptografii na ruchu wychodzącym (`SIDECAR_OUTBOUND`).

**Zastosowany manifest YAML:**
`2_yaml_mainfest/zhakowany_klient_k6.yaml`

```
kacpe@ViBookS14 MINGW64 ~/Documents/Ważne/Projekty/Praca-In-ynierska (main)
$ kubectl apply -f 2_yaml_mainfest/zmiena_klient_mtls12.yaml 
Warning: EnvoyFilter exposes internal implementation details that may change at any time. Prefer other APIs if possible, and exercise extreme caution, especially around upgrades.
envoyfilter.networking.istio.io/hack-k6-client created
```

**Wynik testu dla Próby 3:**
Test zakończył się całkowitym niepowodzeniem (0% statusów 200 OK, 100% zapytań zakończonych błędem).

```text
  █ TOTAL RESULTS
    checks_total.......: 14979   496.005612/s
    checks_succeeded...: 0.00%   0 out of 14979
    checks_failed......: 100.00% 14979 out of 14979
    ✗ status is 200
```

*(Plik z wynikiem: `3_wyniki/podsumowanie_lekki_zhakowany_klient.json`)*

**Wniosek końcowy z Etapu 2:**
Atak polegający na wymuszeniu słabszej kryptografii (downgrade do TLS 1.2 i szyfru AES128-SHA) na kliencie zakończył się niepowodzeniem połączenia z serwerem.
Eksperyment udowodnił, że side-cary Envoya w architekturze Istio wykazują bardzo wysoką odporność na manipulację konfiguracją kryptograficzną. Domyślne certyfikaty i mechanizmy weryfikacji tożsamości (SPIFFE) skutecznie odrzucają połączenia od klientów, którzy próbują użyć nieautoryzowanych, słabszych algorytmów szyfrujących.

### Etap 3: Scenariusz Edge/IoT – Wymuszenie TLS 1.2 na poziomie klastra

**Cel:** Legalne obniżenie standardu kryptograficznego klastra do TLS 1.2 (z użyciem EnvoyFilter blokującego negocjację w górę) i zbadanie wpływu tego zabiegu na wydajność sieciową (Latency).

**Wynik Testu Lekkiego (K6):**

* Liczba zapytań: 15000 (100% status 200 OK)
* Opóźnienie średnie (`avg`): **1.75 ms**
* Opóźnienie 90. percentyla (`p90`): **2.25 ms**
*(Plik z podsumowaniem: `3_wyniki/podsumowanie_scenariusz3_prawdziwy.json`)*
*(Dowód konfiguracji proxy: `dowod_tls.json` z parametrem `"tlsMaximumProtocolVersion": "TLSV1_2"`)*

**Wnioski:**
Zgodnie z początkowymi założeniami z "Planu Działania", wymuszenie przestarzałego standardu TLS 1.2 **zwiększyło** średnie opóźnienie sieciowe (z 1.65 ms na 1.75 ms, co stanowi wzrost o około 6%).
Ten wzrost jest bezpośrednim wynikiem różnic architektonicznych protokołów – TLS 1.2 wymaga pełnych dwóch rund negocjacji (2-RTT) do nawiązania bezpiecznego połączenia, podczas gdy zoptymalizowany TLS 1.3 załatwia to w jednym kroku (1-RTT). Potwierdza to hipotezę, że w zastosowaniach IoT, gdzie sieć może być niestabilna, TLS 1.2 powoduje zauważalny narzut czasowy.

```
kacpe@ViBookS14 MINGW64 ~/Documents/Ważne/Projekty/Praca-In-ynierska (main)
$ HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")

kacpe@ViBookS14 MINGW64 ~/Documents/Ważne/Projekty/Praca-In-ynierska (main)
$ for i in {1..25}; do echo "Pomiary CPU:"; kubectl top pod $HTTPBIN_POD --containers | grep istio-proxy; sleep 3; done
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   7m           33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   76m          33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   76m          33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   76m          33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   76m          33Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   162m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   162m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   162m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   162m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   162m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   160m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   160m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   160m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   160m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   160m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   158m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   158m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   158m         34Mi
Pomiary CPU:
httpbin-7b549f7859-5rxw9   istio-proxy   158m         34Mi

kacpe@ViBookS14 MINGW64 ~/Documents/Ważne/Projekty/Praca-In-ynierska (main)
```

### Podsumowanie Etapu 2 i 3: Analiza wydajnościowa TLS 1.2 vs 1.3

Wykonano testy porównawcze przy użyciu dużego ładunku danych (50 KB payload). Wyniki pomiarów zużycia zasobów przez kontener `istio-proxy` wykazały:

* **TLS 1.3 (Baseline):** Szczytowe zużycie CPU na poziomie **158m**, stabilizacja przy **149m**.
* **TLS 1.2 (IoT Downgrade):** Szczytowe zużycie CPU na poziomie **162m**, stabilizacja przy **158m**.

**Wnioski badawcze:**
Wbrew wstępnej hipotezie, nowocześniejszy protokół TLS 1.3 okazał się bardziej efektywny procesorowo (o ok. 5.7% mniejsze zużycie CPU przy stabilnym ruchu). Potwierdza to wysoką optymalizację stosu kryptograficznego w nowoczesnych wersjach Envoya oraz korzyści płynące ze skróconego mechanizmu uzgadniania kluczy (Handshake). TLS 1.2 wykazał natomiast nieznacznie mniejsze zapotrzebowanie na pamięć RAM (~10% różnicy).
