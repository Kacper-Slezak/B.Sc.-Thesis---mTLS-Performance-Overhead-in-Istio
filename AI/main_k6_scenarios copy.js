import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const upstream_latency = new Trend('upstream_latency_ms');
const success_rate = new Rate('success_rate');

const targetUrl = __ENV.TARGET_URL || 'http://httpbin.default.svc.cluster.local:8000';
const testType = __ENV.TEST_TYPE || 'baseline';
const disableKeepAlive = __ENV.DISABLE_KEEP_ALIVE === 'true';

const heavyPayload = "A".repeat(1024 * 100);

export const options = {
  // Wyłączamy Keep-Alive po stronie k6 -> lokalny Envoy
  noConnectionReuse: disableKeepAlive,
  scenarios: {
    perf_test: {
      executor: 'ramping-vus',
      startVUs: 10,
      stages: [
        { duration: '30s', target: testType === 'stress' ? 500 : 100 }, // Rozgrzewka
        { duration: '2m', target: testType === 'stress' ? 500 : 100 },  // Główne uderzenie
        { duration: '30s', target: 0 },                                 // Wygaszanie
      ],
    },
  },
};

export default function () {
  const headers = disableKeepAlive ? { 'Connection': 'close' } : {};
  let response;

  if (testType === 'payload') {
    headers['Content-Type'] = 'application/json';
    response = http.post(`${targetUrl}/post`, JSON.stringify({ data: heavyPayload }), { headers });
  } else {
    response = http.get(`${targetUrl}/get`, { headers });
  }

  success_rate.add(response.status === 200);
  
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