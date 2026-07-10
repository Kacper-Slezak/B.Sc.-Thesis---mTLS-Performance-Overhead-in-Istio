import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

// We measure precisely the response time from the upstream itself (Istio Overhead)
const upstream_latency = new Trend('upstream_latency_ms');
const success_rate = new Rate('success_rate');

// Configuration via environment variables
const cfg = {
  rate: Number(__ENV.RPS || 500),
  duration: __ENV.DURATION || '30s',
  // Port 8000 added
  targetUrl: __ENV.TARGET_URL || 'http://httpbin.default.svc.cluster.local:8000/get', 
};

export const options = {
  scenarios: {
    perf_test: {
      executor: 'constant-arrival-rate',
      rate: cfg.rate,
      timeUnit: '1s',
      duration: cfg.duration,
      preAllocatedVUs: 20,
      maxVUs: 200,
    },
  },
};

export default function () {
  const params = {
    headers: { 'Content-Type': 'application/json' },
  };

  // Changed http.post to http.get for /get endpoint
  const response = http.get(cfg.targetUrl, params);

  // We measure response time and extract Istio latency from headers
  const upstreamHeader = response.headers['X-Upstream-Latency-Ms'];
  if (upstreamHeader) {
    upstream_latency.add(Number(upstreamHeader));
  }

  success_rate.add(response.status === 200);

  check(response, {
    'status is 200': (r) => r.status === 200,
  });
}

export function handleSummary(data) {
  return {
    stdout: `
--- DIPLOMA PERFORMANCE SUMMARY ---
Test Duration: ${cfg.duration}
Target Rate:   ${cfg.rate} req/s
Success Rate:  ${(data.metrics.success_rate?.values?.rate * 100 || 0).toFixed(2)}%
Avg Latency:   ${(data.metrics.http_req_duration?.values?.avg || 0).toFixed(2)} ms
P95 Latency:   ${(data.metrics.http_req_duration?.values?.['p(95)'] || 0).toFixed(2)} ms
Upstream Avg:  ${(data.metrics.upstream_latency_ms?.values?.avg || 0).toFixed(2)} ms
-----------------------------------
`,
    '/tmp/summary.json': JSON.stringify(data, null, 2),
  };
}
