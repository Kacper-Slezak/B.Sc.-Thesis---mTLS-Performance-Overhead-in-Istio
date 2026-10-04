# Exploratory Benchmarks and Test Trials (`test_trying/`)

This directory contains full benchmark batteries, exploratory load testing scripts, and historical test trials developed during the research project prior to isolating the core baseline thesis benchmark suite.

Note: The official benchmark suite for the thesis is [`run_basic_test.sh`](../run_basic_test.sh) located in the project root directory.

---

## Directory Contents

### 1. Test Scripts and Pipelines
* `run_all_test_v2.sh` (with aliases `run_all_test.sh`, `run_all_tests.sh`): Full automated benchmark suite covering 6 load profiles (`baseline`, `baseline-nokeepalive`, `payload`, `payload-nokeepalive`, `stress`, `handshake-nokeepalive`) across all cryptographic configurations (Plaintext, mTLS 1.3 default, mTLS 1.2 GCM/GCM256/ChaCha/CBC, mTLS 1.3 PQC).
* `start.sh`: End-to-end exploratory pipeline script that provisions the cluster (`01_scripts/setup_cluster.sh`), waits for pods, executes `run_all_test_v2.sh`, generates reports, and opens Grafana.
* `test.sh`: Diagnostic CPU profiling script for Envoy sidecars with Keep-Alive disabled (forcing repeated TLS 1.2 handshakes).

### 2. Archived Versions (`Archive/`)
* `run_all_test_v1.sh`: Earlier revision of the comprehensive test battery.
* `run_all_test_old.sh`: Initial sequential benchmark runner implementation.
* `one_liner.sh`: Early convenience script for testing.
