import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    cryptographic_scenario: {
      executor: 'constant-arrival-rate',
      rate: 200,           // Target: 200 requests
      timeUnit: '1s',      // per 1 second
      duration: '60s',     // Test duration: 60 seconds
      preAllocatedVUs: 20, 
      maxVUs: 200,         // More backup threads because we download large files
    },
  },
};

export default function () {
  // Endpoint /bytes/50000 generates exactly 50 KB of random data
  const res = http.get('http://httpbin:8000/bytes/50000');
  
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}