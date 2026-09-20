import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

/**
 * Istio Service Mesh Cryptographic Overhead Benchmark
 * 
 * Architecture & Measurement Notes:
 * 1. Sidecar Architecture:
 *    - In Istio, the k6 load generator pod communicates with its local Envoy sidecar
 *      via localhost HTTP redirection (iptables).
 *    - Mutual TLS (mTLS) encapsulation and encryption occur strictly between the
 *      client-side Envoy proxy and the target server-side Envoy proxy.
 *    - Therefore, k6's internal `tls_handshaking` metric remains 0 (k6 communicates
 *      via plain HTTP locally). Actual handshake durations and cryptographic cipher
 *      counters are extracted directly from Envoy proxy telemetry (/stats and /stats/prometheus).
 * 
 * 2. Scenario Design:
 *    - `baseline`: Standard throughput and latency evaluation with GET requests (100 VUs).
 *    - `payload`: Evaluates bulk symmetric cipher encryption (AES-GCM, AES-CBC, ChaCha20)
 *      by streaming large JSON payloads (configured by PAYLOAD_SIZE_KB).
 *    - `stress`: Evaluates concurrency limits and saturation by ramping up to 500 VUs.
 *    - `handshake`: Dedicated constant-arrival-rate test with connection closure to isolate
 *      asymmetric handshake negotiation cost (ECDHE vs. Post-Quantum ML-KEM).
 */

const server_waiting_ms = new Trend('server_waiting_ms');
const upstream_latency = new Trend('upstream_latency_ms');
const success_rate = new Rate('success_rate');

const targetUrl = __ENV.TARGET_URL || 'http://httpbin.default.svc.cluster.local:8000';
const testType = __ENV.TEST_TYPE || 'baseline';
const disableKeepAlive = __ENV.DISABLE_KEEP_ALIVE === 'true';
const payloadSizeKB = Number(__ENV.PAYLOAD_SIZE_KB || 5000); // Default: ~5MB payload

// Pre-allocate payload memory once at startup
const heavyPayload = 'A'.repeat(1024 * payloadSizeKB);

function scenarioFor(type) {
  if (type === 'handshake') {
    // Constant arrival rate of new connections: ensures uniform handshake rate across setups
    return {
      handshake_test: {
        executor: 'constant-arrival-rate',
        rate: Number(__ENV.HANDSHAKE_RATE || 50), // New connections per second
        timeUnit: '1s',
        duration: '90s',
        preAllocatedVUs: 100,
        maxVUs: 300,
      },
    };
  }
  
  // Standard ramping-VUs for baseline, payload, and stress profiles
  const targetVUs = type === 'stress' ? 500 : 100;
  return {
    perf_test: {
      executor: 'ramping-vus',
      startVUs: 10,
      stages: [
        { duration: '30s', target: targetVUs }, // Warm-up stage
        { duration: '2m', target: targetVUs },  // Sustained load stage
        { duration: '30s', target: 0 },          // Ramp-down stage
      ],
    },
  };
}

export const options = {
  // Disable connection reuse for no-keepalive and handshake isolation scenarios
  noConnectionReuse: disableKeepAlive || testType === 'handshake',
  scenarios: scenarioFor(testType),
};

export default function () {
  const isConnectionClose = disableKeepAlive || testType === 'handshake';
  const headers = isConnectionClose ? { Connection: 'close' } : {};
  let response;

  if (testType === 'payload') {
    headers['Content-Type'] = 'application/json';
    response = http.post(`${targetUrl}/post`, JSON.stringify({ data: heavyPayload }), { headers });
  } else {
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
