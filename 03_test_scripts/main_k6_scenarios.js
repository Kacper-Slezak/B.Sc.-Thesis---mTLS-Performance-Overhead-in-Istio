import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const upstream_latency = new Trend('upstream_latency_ms');
const success_rate = new Rate('success_rate');

const targetUrl = __ENV.TARGET_URL || 'http://httpbin.default.svc.cluster.local:8000';
const testType = __ENV.TEST_TYPE || 'baseline';

// Generate 100KB payload for bulk encryption testing
const heavyPayload = "A".repeat(1024 * 100);

export const options = {
  scenarios: {
    perf_test: {
      executor: testType === 'stress' ? 'ramping-arrival-rate' : 'constant-arrival-rate',
      timeUnit: '1s',
      preAllocatedVUs: 20,
      maxVUs: testType === 'stress' ? 500 : 200,
      ...(testType === 'stress' 
        ? {
            // Options specific to ramping-arrival-rate
            startRate: 50,
            stages: [
              { target: 1500, duration: '1m' }
            ]
          }
        : {
            // Options specific to constant-arrival-rate
            rate: testType === 'payload' ? 100 : 500,
            duration: '30s'
          }
      )
    },
  },
};

export default function () {
  let response;

  if (testType === 'payload') {
    response = http.post(`${targetUrl}/post`, JSON.stringify({ data: heavyPayload }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } else {
    response = http.get(`${targetUrl}/get`);
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