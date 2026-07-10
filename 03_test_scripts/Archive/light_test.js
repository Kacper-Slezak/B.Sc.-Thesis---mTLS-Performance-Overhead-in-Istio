import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    base_scenario: {
      executor: 'constant-arrival-rate',
      rate: 500,           // Target: 500 requests
      timeUnit: '1s',      // per 1 second
      duration: '30s',     // Test duration: 30 seconds
      preAllocatedVUs: 10, // Initial number of threads
      maxVUs: 100,         // Maximum number of threads if the server starts slowing down
    },
  },
};

export default function () {
  const res = http.get('http://httpbin:8000/get');
  
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}