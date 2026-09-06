### Tabela Scenariuszy Testowych

Podzieliliśmy testy na dwie osie: **Konfiguracja Infrastruktury** (jaki szyfr i protokół działa na klastrze) oraz **Profil Ruchu** (jakie obciążenie generuje K6).

| ID | Infrastructure Setup | K6 Traffic Profile (`TEST_TYPE`) | Description |
| --- | --- | --- | --- |
| 1A | mTLS 1.3 (Istio Default) | `baseline` | Stały ruch 500 zapytań GET/s przez 30 sekund. Pomiar bazowego opóźnienia. |
| 1B | mTLS 1.3 (Istio Default) | `payload` | Stały ruch 100 zapytań POST/s z pakietem 100KB przez 30 sekund. Pomiar narzutu przy szyfrowaniu dużych bloków danych (bulk encryption). |
| 1C | mTLS 1.3 (Istio Default) | `stress` | Płynny wzrost ruchu od 50 do 1500 zapytań/s. Badanie punktu załamania wydajności. |
| 2A | mTLS 1.2 (Forced AES128-SHA) | `baseline` | Jak w 1A, ale z wymuszonym starym protokołem i szyfrem za pomocą EnvoyFilter. |
| 2B | mTLS 1.2 (Forced AES128-SHA) | `payload` | Jak w 1B, badanie wydajności szyfru AES128-SHA przy dużych pakietach. |
| 2C | mTLS 1.2 (Forced AES128-SHA) | `stress` | Jak w 1C, badanie maksymalnej przepustowości dla starszego szyfru. |

---

### Instrukcja Uruchamiania (Krok po Kroku)

1. **Inicjalizacja Klastra:** Uruchamiasz swój stary skrypt `setup_cluster.sh` tylko raz na początku dnia pracy, aby postawić Kubernetes, Istio, pody K6 i Httpbin. Czekasz, aż wszystko będzie w stanie `Running`.
2. **Weryfikacja Grafany:** Wykonujesz przekierowanie portów (port-forward), aby mieć podgląd na żywo.
3. **Uruchomienie Testów:** Odpalasz nowy skrypt `run_all_tests.sh`. Skrypt ten automatycznie:
* Tworzy odpowiednie foldery (`Summary`, `RawLogs`).
* Puszcza ruch `baseline`, `payload` i `stress` dla domyślnego mTLS 1.3.
* Nakłada konfigurację mTLS 1.2.
* Czeka na propagację konfiguracji wewnątrz proxy Envoy.
* Puszcza te same trzy profile ruchu dla mTLS 1.2.
* Pobiera wszystkie logi K6 i zapisuje je z unikalnymi datami w nazwach.





---

### Prometheus i Grafana: Weryfikacja i Zapis Danych


1. **Podgląd na żywo w Grafanie:**
* Uruchom komendę: `kubectl port-forward svc/grafana 3000:3000 -n istio-system`
* Otwórz przeglądarkę i wejdź na `http://localhost:3000`.
* Przejdź do domyślnego dashboardu **Istio Workload Dashboard**. Zobaczysz tam wskaźniki RPS (Requests Per Second) oraz opóźnienia.


2. **Kluczowe metryki do analizy (Prometheus):**
* Pamiętaj, że dla K6 etap negocjacji szyfrów i narzut Envoy nie jest bezpośrednio widoczny w czasach żądań, zjawisko to przejawia się tylko we wzroście `http_req_duration`.


* Aby zobaczyć realny koszt szyfrowania, w Grafanie (zakładka "Explore") wpisz zapytanie: `container_cpu_usage_seconds_total{container="istio-proxy", pod=~"httpbin.*"}`. Pokaże to zużycie procesora przez kontener szyfrujący Envoy.


3. **Jak zapisać dane z Grafany do analizy:**
* **Eksport CSV:** Na dowolnym wykresie w Grafanie kliknij jego tytuł, wybierz "Inspect" -> "Data". Zobaczysz tam opcję "Download CSV". To najlepszy sposób, aby wyciągnąć szeregi czasowe użycia CPU i nałożyć je później na wykresy razem z wynikami z K6.
* **Raporty PDF:** Możesz użyć wtyczki do Grafany, aby wygenerować statyczny plik PDF z całego dashboardu tuż po zakończeniu danego testu.

