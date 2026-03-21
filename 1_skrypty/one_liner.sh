$ MSYS_NO_PATHCONV=1 kubectl cp "default/${K6_POD}:wyniki_lekki_mtls13_raw.json" ./3_wyniki/wynik_raw_lekki_mtls13.json -c k6

$ MSYS_NO_PATHCONV=1 kubectl cp "default/${K6_POD}:podsumowanie_lekki_mtls13.json" ./3_wyniki/podsumowanie_lekki_mtls13.json -c k6

$ cat 4_testy_js/test_lekki.js | kubectl exec -i $K6_POD -c k6 -- k6 run --out json=wyniki_lekki_mtls13_raw.json --summary-export=podsumowanie_lekki_mtls13.json -

$ MSYS_NO_PATHCONV=1 kubectl cp "default/${K6_POD}:wyniki_ciezki_mtls13_raw.json" ./3_wyniki/wynik_raw_ciezki_mtls13.json -c k6

$ MSYS_NO_PATHCONV=1 kubectl cp "default/${K6_POD}:podsumowanie_ciezki_mtls13.json" ./3_wyniki/podsumowanie_ciezki_mtls13.json -c k6