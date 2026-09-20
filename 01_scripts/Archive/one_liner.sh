$ MSYS_NO_PATHCONV=1 kubectl cp "default/${K6_POD}:raw_result_light_mtls1_3.json" ./04_results/Archive/raw_result_light_mtls1_3.json -c k6

$ MSYS_NO_PATHCONV=1 kubectl cp "default/${K6_POD}:summary_light_mtls1_3.json" ./04_results/Archive/summary_light_mtls1_3.json -c k6

$ cat 03_test_scripts/Archive/light_test.js | kubectl exec -i $K6_POD -c k6 -- k6 run --out json=raw_result_light_mtls1_3.json --summary-export=summary_light_mtls1_3.json -

$ MSYS_NO_PATHCONV=1 kubectl cp "default/${K6_POD}:raw_result_heavy_mtls1_3.json" ./04_results/Archive/raw_result_heavy_mtls1_3.json -c k6

$ MSYS_NO_PATHCONV=1 kubectl cp "default/${K6_POD}:summary_heavy_mtls1_3.json" ./04_results/Archive/summary_heavy_mtls1_3.json -c k6