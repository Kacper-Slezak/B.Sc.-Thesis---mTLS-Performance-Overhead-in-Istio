import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

// ==========================================================================
// ZMIANY WZGLEDEM ORYGINALU I DLACZEGO:
//
// !!! WAZNA POPRAWKA (v3): usunieto metryki tls_handshake_ms/tcp_connecting_ms
// mierzone przez k6 (byly w v2). POWOD: w architekturze Istio sidecar k6
// laczy sie z lokalnym Envoyem po ZWYKLYM, PLAINTEXT HTTP (ruch jest
// przekierowywany przez iptables do portu 15001 outbound). To dopiero
// Envoy-klient nawiazuje mTLS z Envoyem-serwerem po drugiej stronie - CALY
// handshake dzieje sie miedzy dwoma sidecarami, calkowicie niewidocznie dla
// procesu k6. Dlatego response.timings.tls_handshaking w k6 bedzie ZAWSZE
// rowne 0 w tym scenariuszu, niezaleznie od configu cipher/curve - to nie
// jest blad pomiaru, tylko fakt architektoniczny (k6 nigdy nie robi TLS
// samo). Realny czas handshake'u trzeba mierzyc PO STRONIE ENVOYA, przez
// histogram 'ssl.handshake' w jego /stats - to teraz robi bash
// (run_all_test_patched.sh, funkcja get_ssl_handshake_sum_count), zapisujac
// wynik do 04_results/Summary/handshake_latency.csv, ktory stats_compare.py
// odczytuje niezaleznie od wynikow k6.
//
// 1. NOWY TEST_TYPE: "handshake"
//    Dedykowany scenariusz izolujacy KOSZT SAMEGO HANDSHAKE'U, niezalezny
//    od ramping-vus (ktory miesza rozgrzewanie/wygaszanie z pomiarem).
//    Uzywa constant-arrival-rate - stala, kontrolowana liczba NOWYCH
//    polaczen/sekunde (nie VUs), kazde z Connection: close i minimalnym
//    payloadem. To generuje ruch, na podstawie ktorego bash liczy delte
//    histogramu ssl.handshake z Envoya - sam k6 tu tylko "produkuje"
//    handshake'y, nie mierzy ich czasu.
//
// 2. PAYLOAD_SIZE_KB jako zmienna env (domyslnie 5000 KB = ~5MB zamiast
//    100KB). Przy 100KB narzut samego AES-GCM/ChaCha20/CBC ginie w szumie
//    sieciowym na wspolczesnym CPU z AES-NI. Przy kilku MB bulk-cipher
//    throughput ma szanse sie zaznaczyc. Rozmiar mozna zmienic bez edycji
//    kodu: PAYLOAD_SIZE_KB=2000 k6 run ...
//
// 3. server_waiting_ms (response.timings.waiting) zostaje - to jest czas
//    oczekiwania na odpowiedz serwera PO wyslaniu requestu, mierzony od
//    strony k6->local-envoy. Uzyteczne jako kontrolna metryka "czy appka
//    httpbin nie zwalnia niezaleznie od TLS", ale TEZ nie mierzy TLS.
// ==========================================================================

const server_waiting_ms = new Trend('server_waiting_ms');
const upstream_latency = new Trend('upstream_latency_ms');
const success_rate = new Rate('success_rate');

const targetUrl = __ENV.TARGET_URL || 'http://httpbin.default.svc.cluster.local:8000';
const testType = __ENV.TEST_TYPE || 'baseline';
const disableKeepAlive = __ENV.DISABLE_KEEP_ALIVE === 'true';
const payloadSizeKB = Number(__ENV.PAYLOAD_SIZE_KB || 5000); // domyslnie ~5MB, nie 100KB

const heavyPayload = 'A'.repeat(1024 * payloadSizeKB);

function scenarioFor(type) {
  if (type === 'handshake') {
    // Stala liczba nowych polaczen/sekunde, niezaleznie od tego jak dlugo
    // trwa pojedynczy request - to jest kluczowe zeby porownywac
    // porownywalne obciazenie handshake'ami miedzy setupami. Bash mierzy
    // rzeczywisty koszt handshake'u z /stats Envoya w tym samym oknie
    // czasowym co ten wykonanie tego scenariusza.
    return {
      handshake_test: {
        executor: 'constant-arrival-rate',
        rate: Number(__ENV.HANDSHAKE_RATE || 50), // nowych polaczen/s
        timeUnit: '1s',
        duration: '90s',
        preAllocatedVUs: 100,
        maxVUs: 300,
      },
    };
  }
  return {
    perf_test: {
      executor: 'ramping-vus',
      startVUs: 10,
      stages: [
        { duration: '30s', target: type === 'stress' ? 500 : 100 }, // Rozgrzewka
        { duration: '2m', target: type === 'stress' ? 500 : 100 },  // Glowne uderzenie
        { duration: '30s', target: 0 },                              // Wygaszanie
      ],
    },
  };
}

export const options = {
  noConnectionReuse: disableKeepAlive || testType === 'handshake',
  scenarios: scenarioFor(testType),
};

export default function () {
  const headers = (disableKeepAlive || testType === 'handshake') ? { Connection: 'close' } : {};
  let response;

  if (testType === 'payload') {
    // Duzy payload w obie strony: wysylamy heavyPayload (TX), pobieramy
    // odpowiedz podobnej wielkosci (RX) - obie strony sa osobno szyfrowane.
    headers['Content-Type'] = 'application/json';
    response = http.post(`${targetUrl}/post`, JSON.stringify({ data: heavyPayload }), { headers });
  } else {
    // baseline / stress / handshake - lekki GET
    response = http.get(`${targetUrl}/get`, { headers });
  }

  success_rate.add(response.status === 200);

  if (response.timings && typeof response.timings.waiting === 'number') {
    server_waiting_ms.add(response.timings.waiting);
  }

  const upstreamHeader = response.headers['X-Upstream-Latency-Ms'];
  if (upstreamHeader) {
    upstream_latency.add(Number(upstreamHeader));
  }

  check(response, {
    'status is 200': (r) => r.status === 200,
  });
}

export function handleSummary(data) {
  return {
    '/tmp/summary.json': JSON.stringify(data, null, 2),
  };
}