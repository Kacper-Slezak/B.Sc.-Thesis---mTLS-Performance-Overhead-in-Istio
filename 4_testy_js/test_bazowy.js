import http from 'k6/http';
import { check } from 'k6';

// Konfiguracja testu
export const options = {
  scenarios: {
    bazowy_scenariusz: {
      executor: 'constant-arrival-rate',
      rate: 500,           // 500 zapytań
      timeUnit: '1s',      // na 1 sekundę
      duration: '30s',     // przez 30 sekund
      preAllocatedVUs: 10, // 10 wirtualnych użytkowników (wątków)
      maxVUs: 50,
    },
  },
};

// Kod wykonywany przez każdego wirtualnego użytkownika
export default function () {
  const res = http.get('http://httpbin:8000/get');
  
  // Weryfikacja, czy odpowiedź to zawsze 200 OK
  check(res, {
    'status to 200': (r) => r.status === 200,
  });
}