import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

// ─── CONFIG ──────────────────────────────────────────────────────────────────
const BASE_URL  = 'https://iukxnbifojobmerspvxn.supabase.co';
const ANON_KEY  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml1a3huYmlmb2pvYm1lcnNwdnhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyMzAxOTgsImV4cCI6MjA4NjgwNjE5OH0.-go5he8W7NmSaJJYbkj8rHoYST0SBTuk4yZdIC7EIJg';

const HEADERS = {
  'apikey':        ANON_KEY,
  'Authorization': `Bearer ${ANON_KEY}`,
  'Content-Type':  'application/json',
  'Accept':        'application/json',
};

// ─── LOAD STAGES (ramp up → hold → ramp down) ────────────────────────────────
export const options = {
  stages: [
    { duration: '30s', target: 20  },  // ramp up to 20 users
    { duration: '1m',  target: 50  },  // hold at 50 (realistic campus peak)
    { duration: '30s', target: 100 },  // stress spike
    { duration: '30s', target: 0   },  // ramp down
  ],
  thresholds: {
    http_req_duration:          ['p(95)<1500'],  // 95% of requests under 1.5s
    http_req_failed:            ['rate<0.05'],   // less than 5% failures
    'feed_load_time':           ['p(95)<1200'],
    'notifications_load_time':  ['p(95)<800'],
    'dsa_problems_load_time':   ['p(95)<1000'],
  },
};

// ─── CUSTOM METRICS ───────────────────────────────────────────────────────────
const feedLoadTime          = new Trend('feed_load_time');
const notifLoadTime         = new Trend('notifications_load_time');
const dsaLoadTime           = new Trend('dsa_problems_load_time');
const errorRate             = new Rate('errors');
const requestCount          = new Counter('requests_total');

// ─── HELPERS ─────────────────────────────────────────────────────────────────
function get(path, params = '') {
  const res = http.get(`${BASE_URL}/rest/v1/${path}${params}`, { headers: HEADERS });
  requestCount.add(1);
  return res;
}

// ─── MAIN VIRTUAL USER FLOW ───────────────────────────────────────────────────
export default function () {
  // 1. Load buzz feed (most frequent operation)
  {
    const start = Date.now();
    const res = get('buzz_posts', '?select=id,content,user_id,created_at,like_count,comment_count&order=created_at.desc&limit=20');
    feedLoadTime.add(Date.now() - start);
    const ok = check(res, {
      'feed 200':     (r) => r.status === 200,
      'feed has data': (r) => r.body.length > 2,
    });
    if (!ok) errorRate.add(1);
    else errorRate.add(0);
  }

  sleep(0.5);

  // 2. Load notifications
  {
    const start = Date.now();
    const res = get('notifications', '?select=id,type,data,created_at,read_at&order=created_at.desc&limit=30');
    notifLoadTime.add(Date.now() - start);
    check(res, { 'notifications 200': (r) => r.status === 200 });
  }

  sleep(0.3);

  // 3. Load DSA problems list
  {
    const start = Date.now();
    const res = get('dsa_problems', '?select=id,title,difficulty,topics&order=created_at.desc&limit=20');
    dsaLoadTime.add(Date.now() - start);
    check(res, { 'dsa_problems 200': (r) => r.status === 200 });
  }

  sleep(0.3);

  // 4. Load profiles (for Radar/discovery)
  {
    const res = get('profiles', '?select=id,username,emoji,bio,branch,year&limit=30');
    check(res, { 'profiles 200': (r) => r.status === 200 });
  }

  sleep(0.5);

  // 5. Load chatter inbox (conversation list)
  {
    const res = get('conversation_members', '?select=conversation_id,last_read_at&limit=20');
    check(res, { 'conversations 200 or 401': (r) => r.status === 200 || r.status === 401 });
    // 401 is expected for unauthenticated — RLS working correctly
  }

  sleep(1);
}

// ─── SUMMARY REPORT ──────────────────────────────────────────────────────────
export function handleSummary(data) {
  const p95feed  = data.metrics['feed_load_time']?.values?.['p(95)']?.toFixed(0) ?? 'N/A';
  const p95notif = data.metrics['notifications_load_time']?.values?.['p(95)']?.toFixed(0) ?? 'N/A';
  const p95dsa   = data.metrics['dsa_problems_load_time']?.values?.['p(95)']?.toFixed(0) ?? 'N/A';
  const p95total = data.metrics['http_req_duration']?.values?.['p(95)']?.toFixed(0) ?? 'N/A';
  const errRate  = (data.metrics['http_req_failed']?.values?.rate * 100)?.toFixed(2) ?? 'N/A';
  const total    = data.metrics['requests_total']?.values?.count ?? 'N/A';

  const summary = `
════════════════════════════════════════
  CampusMytra Load Test Results
════════════════════════════════════════
  Total requests:          ${total}
  Error rate:              ${errRate}%

  p95 latency (all):       ${p95total}ms
  p95 feed load:           ${p95feed}ms
  p95 notifications:       ${p95notif}ms
  p95 DSA problems:        ${p95dsa}ms
════════════════════════════════════════
`;
  console.log(summary);
  return { 'summary.txt': summary };
}
