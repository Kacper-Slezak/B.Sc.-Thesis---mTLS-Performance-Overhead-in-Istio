import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    scenariusz_kryptograficzny: {
      executor: 'constant-arrival-rate',
      rate: 200,           // Cel: 200 zapytań
      timeUnit: '1s',      // w ciągu 1 sekundy
      duration: '60s',     // Czas trwania testu: 60 sekund
      preAllocatedVUs: 20, 
      maxVUs: 200,         // Więcej zapasowych wątków, bo pobieramy duże pliki
    },
  },
};

export default function () {
  // Endpoint /bytes/50000 generuje równe 50 KB losowych danych
  const res = http.get('http://httpbin:8000/bytes/50000');
  
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}