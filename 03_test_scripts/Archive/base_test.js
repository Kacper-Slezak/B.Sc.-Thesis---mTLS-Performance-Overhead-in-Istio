import http from 'k6/http';
import { check } from 'k6';

// Test configuration
export const options = {
  scenarios: {
    base_scenario: {
      executor: 'constant-arrival-rate',
      rate: 500,           // 500 requests
      timeUnit: '1s',      // per 1 second
      duration: '30s',     // for 30 seconds
      preAllocatedVUs: 10, // 10 virtual users (threads)
      maxVUs: 50,
    },
  },
};

// Code executed by each virtual user
export default function () {
  const res = http.get('http://httpbin:8000/get');
  
  // Verification if the response is always 200 OK
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}