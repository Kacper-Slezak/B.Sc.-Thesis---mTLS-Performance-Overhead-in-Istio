# Test Trying (Eksploracyjne Baterie Testów i Próby Obciążeniowe)

Katalog ten gromadzi **pełne baterie testów obciążeniowych, skrypty eksploracyjne oraz wcześniejsze wersje próbne (test trials)**, które stanowiły etap badawczy przed wyodrębnieniem kluczowej dla pracy dyplomowej baterii testów podstawowych.

> [!NOTE]
> Główną, oficjalną baterią testów podstawowych pracy dyplomowej jest **[`run_basic_test.sh`](../run_basic_test.sh)** znajdujący się w głównym katalogu projektu.

---

## Zawartość katalogu

### 1. Skrypty testowe i pipeline'y
* **`run_all_test_v2.sh`** (oraz aliasy `run_all_test.sh`, `run_all_tests.sh`) – Pełna, zautomatyzowana bateria 6 profili obciążeniowych (`baseline`, `baseline-nokeepalive`, `payload`, `payload-nokeepalive`, `stress`, `handshake-nokeepalive`) testująca wszystkie konfiguracje kryptograficzne (Plaintext, mTLS 1.3 default, mTLS 1.2 GCM/GCM256/ChaCha/CBC, mTLS 1.3 PQC).
* **`start.sh`** – Pełny skrypt end-to-end: inicjalizacja klastra (`01_scripts/setup_cluster.sh`), oczekiwanie na pody, uruchomienie `run_all_test_v2.sh`, wygenerowanie raportów i uruchomienie wizualizacji w Grafanie.
* **`test.sh`** – Diagnostyczny skrypt profilowania CPU sidecara Envoy przy wyłączonym Keep-Alive (wymuszenie ciągłego nawiązywania połączeń mTLS 1.2).

### 2. Archiwum starszych wersji (`Archive/`)
* **`run_all_test_v1.sh`** – Wcześniejsza wersja pełnej baterii testowej (wrzesień 2026).
* **`run_all_test_old.sh`** – Pierwotna implementacja sekwencyjnego uruchamiania testów obciążeniowych.
* **`one_liner.sh`** – Wczesny skrypt pomocniczy do szybkiego odpalania testów.
