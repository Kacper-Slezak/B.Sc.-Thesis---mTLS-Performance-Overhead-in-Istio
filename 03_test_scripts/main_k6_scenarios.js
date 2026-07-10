import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const handshakeTime = new Trend('tls_handshake_duration');

const profiles = {
    '1_IoT_Base':      { vus: 10,  duration: '30s', payloadSize: 100,   keepAlive: true },
    '2_IoT_Scale':     { vus: 100, duration: '30s', payloadSize: 100,   keepAlive: true },
    '3_Bulk_Transfer': { vus: 10,  duration: '30s', payloadSize: 50000, keepAlive: true },
    '4_Bulk_Scale':    { vus: 100, duration: '30s', payloadSize: 50000, keepAlive: true },
    '5_Handshake_Base':{ vus: 10,  duration: '30s', payloadSize: 100,   keepAlive: false },
    '6_PQC_Stress':    { vus: 100, duration: '30s', payloadSize: 100,   keepAlive: false }
};

const profileName = __ENV.TEST_PROFILE || '1_IoT_Base';
const config = profiles[profileName];

const payload = 'A'.repeat(config.payloadSize);

export const options = {
    vus: config.vus,
    duration: config.duration,
    noConnectionReuse: !config.keepAlive, 
    tags: {
        test_profile: profileName
    }
};

export default function () {
    const url = 'http://httpbin.default.svc.cluster.local/post';
    
    const params = {
        headers: {
            'Content-Type': 'text/plain',
        },
    };

    if (!config.keepAlive) {
        params.headers['Connection'] = 'close';
    }

    const res = http.post(url, payload, params);

    check(res, {
        'status is 200': (r) => r.status === 200,
    });

    if (res.timings.tls_handshaking > 0) {
        handshakeTime.add(res.timings.tls_handshaking);
    }

    sleep(0.01); 
}