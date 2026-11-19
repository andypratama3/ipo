import { config } from '../config.js';
import { query } from '../db.js';
import { AppError } from '../lib/errors.js';

const TIMEOUT_MS = 10_000;
let tokenCache = { token: null, exp: 0 };

function assertReady() {
  if (!config.gofood.apiReady) {
    throw new AppError(503, 'gofood_not_configured', 'Kredensial GoFood belum diisi di server.');
  }
}

export async function getToken() {
  assertReady();
  if (tokenCache.token && Date.now() < tokenCache.exp - 30_000) return tokenCache.token;
  const body = new URLSearchParams({
    client_id: config.gofood.clientId,
    client_secret: config.gofood.clientSecret,
    grant_type: 'client_credentials',
    scope: config.gofood.scope,
  });
  const res = await fetch(config.gofood.authUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
    body,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`GoBiz auth HTTP ${res.status}`);
  const j = await res.json();
  if (!j.access_token) throw new Error('GoBiz auth: token kosong');
  tokenCache = { token: j.access_token, exp: Date.now() + (Number(j.expires_in) || 300) * 1000 };
  return tokenCache.token;
}

async function call(method, path, body) {
  const token = await getToken();
  const res = await fetch(`${config.gofood.apiBase}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  let data = null;
  try { data = await res.json(); } catch { /* body kosong */ }
  if (res.status === 401) tokenCache = { token: null, exp: 0 };
  return { status: res.status, ok: res.ok, data };
}

const seg = (v) => encodeURIComponent(String(v));

/** Kirim satu aksi antrean ke GoBiz. Endpoint sesuai dokumentasi developer.gobiz.com. */
export async function sendAction(a) {
  const outlet = seg(config.gofood.outletId);
  const type = a.order_type === 'pickup' ? 'pickup' : 'delivery';
  const id = seg(a.partner_order_id);
  const base = `/integrations/gofood/outlets/${outlet}/v1/orders/${type}/${id}`;
  if (a.action === 'accept') return call('PUT', `${base}/accepted`);
  if (a.action === 'ready') return call('PUT', `${base}/food-prepared`);
  if (a.action === 'reject') {
    const text = String(a.reason_text || 'Mohon maaf stok habis').padEnd(3, '.').slice(0, 200);
    return call('PUT', `${base}/cancelled`, {
      cancel_reason_code: a.reason_code || config.gofood.rejectReasonCode,
      cancel_reason_description: text,
    });
  }
  throw new Error(`Aksi tidak didukung: ${a.action}`);
}

export async function listSubscriptions() {
  const r = await call('GET', `/integrations/partner/outlets/${seg(config.gofood.outletId)}/v1/notification-subscriptions`);
  return r;
}

export const SUBSCRIBE_EVENTS = [
  'gofood.order.created',
  'gofood.order.awaiting_merchant_acceptance',
  'gofood.order.merchant_accepted',
  'gofood.order.prep_order_now',
  'gofood.order.driver_otw_pickup',
  'gofood.order.driver_arrived',
  'gofood.order.completed',
  'gofood.order.cancelled',
];

export async function subscribeAll() {
  if (!/^https:\/\//i.test(config.gofood.webhookUrl)) {
    throw new AppError(400, 'webhook_url_invalid', 'GOFOOD_WEBHOOK_URL wajib HTTPS publik.');
  }
  const existing = await listSubscriptions();
  const have = new Set((existing.data?.data?.subscriptions || []).filter((s) => s.url === config.gofood.webhookUrl).map((s) => s.event));
  const results = [];
  for (const event of SUBSCRIBE_EVENTS) {
    if (have.has(event)) { results.push({ event, status: 'sudah ada' }); continue; }
    const r = await call('POST', `/integrations/partner/outlets/${seg(config.gofood.outletId)}/v1/notification-subscriptions`, {
      event, url: config.gofood.webhookUrl, active: true,
    });
    results.push({ event, status: r.ok ? 'dibuat' : `gagal (HTTP ${r.status})` });
  }
  return results;
}

const MAX_ATTEMPTS = 5;

/** Klaim (lease) lalu kirim satu aksi. Aman dipanggil bersamaan dari cron & retry manual. */
export async function processAction(id) {
  const claim = await query(
    `UPDATE online_order_actions SET locked_until = now() + interval '60 seconds', updated_at = now()
      WHERE id = $1 AND status IN ('queued','failed') AND (locked_until IS NULL OR locked_until < now())
      RETURNING *`, [id]);
  const a = claim.rows[0];
  if (!a) return { id, skipped: true };
  if (a.source !== 'gofood') {
    await query(`UPDATE online_order_actions SET status='ignored', error='Adapter belum tersedia', locked_until=NULL, updated_at=now() WHERE id=$1`, [id]);
    return { id, status: 'ignored' };
  }
  if (!config.gofood.apiReady) {
    await query(`UPDATE online_order_actions SET locked_until=NULL, error='Kredensial GoFood belum diisi', updated_at=now() WHERE id=$1`, [id]);
    return { id, status: 'queued', note: 'kredensial belum ada' };
  }
  const attempts = a.attempts + 1;
  try {
    const r = await sendAction(a);
    if (r.ok) {
      await query(`UPDATE online_order_actions SET status='sent', attempts=$2, error=NULL, locked_until=NULL, updated_at=now() WHERE id=$1`, [id, attempts]);
      return { id, status: 'sent' };
    }
    const permanent = [400, 403, 404, 406].includes(r.status);
    const next = permanent || attempts >= MAX_ATTEMPTS ? 'manual' : 'failed';
    await query(`UPDATE online_order_actions SET status=$3, attempts=$2, error=$4, locked_until=NULL, updated_at=now() WHERE id=$1`,
      [id, attempts, next, `HTTP ${r.status}`]);
    return { id, status: next, http: r.status };
  } catch (e) {
    const next = attempts >= MAX_ATTEMPTS ? 'manual' : 'failed';
    await query(`UPDATE online_order_actions SET status=$3, attempts=$2, error=$4, locked_until=NULL, updated_at=now() WHERE id=$1`,
      [id, attempts, next, String(e.message).slice(0, 200)]);
    return { id, status: next };
  }
}

/** Kirim antrean (dipanggil cron). Backoff: tunggu attempts * 2 menit sebelum mencoba lagi. */
export async function processQueue(limit = 20) {
  const { rows } = await query(
    `SELECT id FROM online_order_actions
      WHERE status IN ('queued','failed') AND attempts < $2
        AND updated_at <= now() - (attempts * interval '2 minutes')
      ORDER BY created_at LIMIT $1`, [limit, MAX_ATTEMPTS]);
  const out = [];
  for (const r of rows) out.push(await processAction(r.id));
  return out;
}
