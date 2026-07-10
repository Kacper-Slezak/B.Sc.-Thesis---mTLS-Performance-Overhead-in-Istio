# ==========================================
# 0. ZMIENNE ŚRODOWISKOWE (Zrób to na start nowej sesji terminala)
# ==========================================
K6_POD=$(kubectl get pods -l app=k6 -o jsonpath="{.items[0].metadata.name}")
HTTPBIN_POD=$(kubectl get pods -l app=httpbin -o jsonpath="{.items[0].metadata.name}")

# ==========================================
# MONITOROWANIE CPU (Odpal w DRUGIM oknie terminala)
# ==========================================
for i in {1..25}; do echo "Pomiary CPU:"; kubectl top pod $HTTPBIN_POD --containers | grep istio-proxy; sleep 3; done

# ==========================================
# SCENARIUSZE TESTOWE K6 (Odpalaj w PIERWSZYM oknie)
# Profile do wyboru: 1_IoT_Base, 2_IoT_Scale, 3_Bulk_Transfer, 4_Bulk_Scale, 5_Handshake_Base, 6_PQC_Stress
# ==========================================

# PRZYKŁAD DLA SCENARIUSZA 1 (Zmień TEST_PROFILE i nazwy plików na inne dla kolejnych)

# 1. Odpalenie testu:
cat 03_test_scripts/main_k6_scenarios.js | kubectl exec -i $K6_POD -c k6 -- sh -c "TEST_PROFILE='1_IoT_Base' k6 run --out json=raw_1_IoT_Base.json --summary-export=summary_1_IoT_Base.json -"

# 2. Skopiowanie podsumowania do folderu na komputerze (Git Bash / WSL):
MSYS_NO_PATHCONV=1 kubectl cp "default/${K6_POD}:summary_1_IoT_Base.json" ./04_results/summary_1_IoT_Base.json -c k6

# 3. Skopiowanie pełnego, surowego pliku JSON (jeśli potrzebujesz wyciągnąć wykresy):
MSYS_NO_PATHCONV=1 kubectl cp "default/${K6_POD}:raw_1_IoT_Base.json" ./04_results/raw_1_IoT_Base.json -c k6


# ==========================================
# ZARZĄDZANIE MANIFESTAMI (Przełączanie eksperymentów)
# ==========================================

# Aplikacja starego, SPRAWDZONEGO filtra TLS 1.2:
kubectl apply -f 02_manifests/sc3_tls12_downgrade.yaml

# Sprawdzenie, czy filtr wpadł do klastra:
kubectl get envoyfilter

# Ściągnięcie dowodu obniżenia TLS do pamięci Envoya:
istioctl proxy-config cluster $K6_POD --fqdn httpbin.default.svc.cluster.local -o json > ./04_results/dowod_tls12.json

# Usunięcie filtra (Powrót do czystego TLS 1.3):
kubectl delete envoyfilter force-max-tls12-client