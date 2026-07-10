import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    scenariusz_bazowy: {
      executor: 'constant-arrival-rate',
      rate: 500,           // Cel: 500 zapytań
      timeUnit: '1s',      // w ciągu 1 sekundy
      duration: '30s',     // Czas trwania testu: 30 sekund
      preAllocatedVUs: 10, // Początkowa liczba wątków
      maxVUs: 100,         // Maksymalna liczba wątków, jeśli serwer zacznie zwalniać
    },
  },
};

export default function () {
  const res = http.get('http://httpbin:8000/get');
  
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}