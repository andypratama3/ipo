// Integrasi penuh ke PostgreSQL sungguhan. Jalankan: TEST_DATABASE_URL=postgresql://... npm run selftest
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const DB = process.env.TEST_DATABASE_URL;
const skip = !DB && 'TEST_DATABASE_URL belum diisi';
const SECRET = 'whsec-test-secret-1234567890';
let server, base, closePool, tokens = {};

const api = async (method, path, { token, body, headers } = {}) => {
  const res = await fetch(base + path, {
    method,
    headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null; try { json = await res.json(); } catch { /* kosong */ }
  return { status: res.status, json };
};
const sign = (raw) => crypto.createHmac('sha256', SECRET).update(raw).digest('hex');
const hook = (event, orderNo, extra = {}, { eventId = crypto.randomUUID(), badSig = false } = {}) => {
  const raw = JSON.stringify({
    header: { event_name: event, event_id: eventId, version: 1, timestamp: new Date().toISOString() },
    body: { customer: { id: 'c', name: 'Dina' }, driver: { name: '' }, service_type: 'gofood', outlet: { id: 'G1', external_outlet_id: 'o1' },
      order: { status: event.split('.').pop().toUpperCase(), pin: '1234', order_number: orderNo, order_total: 36000,
        order_items: [{ quantity: 2, price: 18000, notes: 'pedas', name: 'Pangsit Original', id: 'u1', external_id: 'pangsit-original', variants: [] }],
        created_at: new Date().toISOString(), ...extra } },
  });
  return fetch(`${base}/api/webhooks/gofood`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Go-Signature': badSig ? 'deadbeef' : sign(raw) }, body: raw });
};

before(async () => {
  if (skip) return;
  Object.assign(process.env, {
    DATABASE_URL: DB, JWT_SECRET: 'jwt-secret-for-tests-aaaaaaaaaaaaaaaaaaaaaaaaaaaa'.replace('secret', 'k3y'),
    GOFOOD_NOTIFICATION_SECRET: SECRET, GOFOOD_OUTLET_ID: 'G1', CRON_SECRET: 'cron-secret-1234567890', NODE_ENV: 'test',
  });
  const { migrate } = await import('../scripts/migrate.js');
  const { seed } = await import('../scripts/seed.js');
  const db = await import('../src/db.js');
  closePool = db.closePool;
  await migrate(() => {});
  await db.query('TRUNCATE users, products, categories, settings, transactions, transaction_items, pending_orders, online_orders, stock_movements, audit_log, online_menu_map, webhook_events, online_order_actions, rate_limits RESTART IDENTITY CASCADE');
  await seed({ SEED_OWNER_PASSWORD: 'Pemilik-Kuat-2026', SEED_CASHIER_PASSWORD: 'Kasir-Kuat-2026' }, () => {});
  const { default: app } = await import('../src/index.js');
  await new Promise((r) => { server = app.listen(0, r); });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => { if (server) await new Promise((r) => server.close(r)); if (closePool) await closePool(); });

test('health 200 & tidak membocorkan konfigurasi', { skip }, async () => {
  const r = await api('GET', '/api/health');
  assert.equal(r.status, 200); assert.equal(r.json.db, 'up');
  assert.deepEqual(Object.keys(r.json).sort(), ['db', 'ok', 'time']);
});

test('auth: login salah, rate limit, login benar, token palsu/alg none ditolak', { skip }, async () => {
  assert.equal((await api('POST', '/api/auth/login', { body: { username: 'pemilik', password: 'salah-salah' } })).status, 401);
  assert.equal((await api('POST', '/api/auth/login', { body: { username: 'tidakada', password: 'salah-salah' } })).status, 401);
  const o = await api('POST', '/api/auth/login', { body: { username: 'pemilik', password: 'Pemilik-Kuat-2026' } });
  const k = await api('POST', '/api/auth/login', { body: { username: 'kasir', password: 'Kasir-Kuat-2026' } });
  assert.equal(o.status, 200); assert.equal(k.json.user.role, 'Kasir');
  tokens = { owner: o.json.token, cashier: k.json.token };
  assert.equal((await api('GET', '/api/auth/me', { token: tokens.owner })).json.user.username, 'pemilik');
  assert.equal((await api('GET', '/api/auth/me')).status, 401);
  assert.equal((await api('GET', '/api/auth/me', { token: 'aaaa.bbbb.cccc' })).status, 401);
  const none = `${Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url')}.${Buffer.from('{"sub":"1","tv":0}').toString('base64url')}.`;
  assert.equal((await api('GET', '/api/auth/me', { token: none })).status, 401);
  // 8 gagal per (ip,user) lalu 429
  let last;
  for (let i = 0; i < 9; i++) last = await api('POST', '/api/auth/login', { body: { username: 'kasir', password: 'salah-salah' } });
  assert.equal(last.status, 429);
  assert.equal((await api('POST', '/api/auth/login', { body: { username: 'kasir', password: 'Kasir-Kuat-2026' } })).status, 429);
});

test('RBAC: kasir tidak boleh push katalog/kelola user/hapus transaksi', { skip }, async () => {
  const prod = { table: 'products', rows: [{ id: 'pangsit-original', payload: { name: 'Pangsit Original', price: 18000, stock: 10 } }] };
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.cashier, body: prod })).status, 403);
  assert.equal((await api('GET', '/api/users', { token: tokens.cashier })).status, 403);
  assert.equal((await api('DELETE', '/api/orders/MPJ-20261119-00001', { token: tokens.cashier })).status, 403);
  assert.equal((await api('GET', '/api/sync/tables', { token: tokens.cashier })).json.tables.length, 6);
});

test('sync push/pull: katalog, validasi, tabel orders ditolak, tombstone, kursor', { skip }, async () => {
  const rows = [
    { id: 'pangsit-original', payload: { name: 'Pangsit Original', category: 'Mie Pangsit Jakarta', price: 18000, stock: 10, emoji: '🥟' } },
    { id: 'es-teh', payload: { name: 'Es Teh', price: 5000, stock: null } },
  ];
  const p = await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'products', rows, deviceId: 'dev-1' } });
  assert.equal(p.status, 200); assert.equal(p.json.accepted, 2);
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'products', rows: [{ id: 'x', payload: { name: 'Bad', price: -5 } }] } })).status, 400);
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'orders', rows: [{ id: 'x', payload: {} }] } })).json.error, 'unknown_table');
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'users', rows: [{ id: 'x', payload: {} }] } })).json.error, 'unknown_table');
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: '__proto__', rows: [{ id: 'x', payload: {} }] } })).json.error, 'unknown_table');
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'settings', rows: [{ id: 'main', payload: { businessName: 'Mie Pangsit', taxRate: 11 } }] } })).status, 200);
  const pull = await api('GET', '/api/sync/pull?table=products', { token: tokens.cashier });
  assert.equal(pull.json.rows.length, 2);
  const again = await api('GET', `/api/sync/pull?table=products&since=${encodeURIComponent(pull.json.cursor.since)}&sinceId=${pull.json.cursor.sinceId}`, { token: tokens.cashier });
  assert.equal(again.json.rows.length, 0);
  assert.equal((await api('GET', '/api/sync/pull?table=products&since=bukan-tanggal', { token: tokens.cashier })).status, 400);
  assert.equal((await api('GET', "/api/sync/pull?table=products';DROP TABLE users;--", { token: tokens.cashier })).status, 400);
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'categories', rows: [{ id: 'nonexist', deleted: true }] } })).status, 200);
});

test('transaksi: harga dihitung ulang server, stok turun, idempoten, validasi', { skip }, async () => {
  const order = {
    id: 'MPJ-20261119-11111', clientTxnId: crypto.randomUUID(), createdAt: new Date().toISOString(), orderType: 'dine-in', tableNumber: '3',
    items: [{ productId: 'pangsit-original', name: 'HARGA PALSU', price: 1, qty: 2 }, { productId: 'es-teh', name: 'Es Teh', price: 99999, qty: 1 }],
    discount: 1000, payment: 'cash', paidAmount: 50000,
  };
  const r = await api('POST', '/api/orders', { token: tokens.cashier, body: { order, deviceId: 'dev-1' } });
  assert.equal(r.status, 201, JSON.stringify(r.json));
  assert.equal(r.json.order.subtotal, 41000); assert.equal(r.json.order.total, 40000); assert.equal(r.json.order.changeAmount, 10000);
  assert.equal(r.json.order.items[0].name, 'Pangsit Original'); assert.equal(r.json.order.taxRate, 11);
  const dup = await api('POST', '/api/orders', { token: tokens.cashier, body: { order } });
  assert.equal(dup.status, 200); assert.equal(dup.json.duplicate, true);
  const dup2 = await api('POST', '/api/orders', { token: tokens.cashier, body: { order: { ...order, id: 'MPJ-20261119-22222' } } }); // clientTxnId sama
  assert.equal(dup2.json.duplicate, true);
  // race: 5 permintaan kembar bersamaan => tepat 1 baris
  const o2 = { ...order, id: 'MPJ-20261119-33333', clientTxnId: crypto.randomUUID() };
  const rs = await Promise.all(Array.from({ length: 5 }, () => api('POST', '/api/orders', { token: tokens.cashier, body: { order: o2 } })));
  assert.equal(rs.filter((x) => x.json?.duplicate === false).length, 1); assert.ok(rs.every((x) => x.status < 300));
  const prods = await api('GET', '/api/sync/pull?table=products', { token: tokens.cashier });
  const po = prods.json.rows.find((x) => x.id === 'pangsit-original');
  assert.equal(po.payload.stock, 6); // 10 - 2 - 2 (dua transaksi unik)
  const et = prods.json.rows.find((x) => x.id === 'es-teh');
  assert.equal(et.payload.stock, null); // tanpa batas tidak berubah
  const bad = await api('POST', '/api/orders', { token: tokens.cashier, body: { order: { ...order, id: 'x', clientTxnId: crypto.randomUUID() } } });
  assert.equal(bad.status, 400);
  const pull = await api('GET', '/api/sync/pull?table=orders', { token: tokens.cashier });
  assert.equal(pull.json.rows.length, 2); assert.equal(pull.json.rows[0].payload.items.length, 2);
});

test('stok tidak boleh negatif & konflik tercatat', { skip }, async () => {
  const o = { id: 'MPJ-20261119-44444', clientTxnId: crypto.randomUUID(), createdAt: new Date().toISOString(), items: [{ productId: 'pangsit-original', name: 'x', price: 1, qty: 50 }], payment: 'qris' };
  assert.equal((await api('POST', '/api/orders', { token: tokens.cashier, body: { order: o } })).status, 201);
  const { query } = await import('../src/db.js');
  assert.equal((await query(`SELECT stock FROM products WHERE id='pangsit-original'`)).rows[0].stock, 0);
  assert.equal((await query(`SELECT count(*)::int n FROM audit_log WHERE action='stock.conflict'`)).rows[0].n, 1);
});

test('hapus transaksi: hanya Pemilik, soft delete, stok TIDAK kembali, tombstone di pull', { skip }, async () => {
  const d = await api('DELETE', '/api/orders/MPJ-20261119-11111', { token: tokens.owner });
  assert.equal(d.status, 200); assert.equal(d.json.stockRestored, false);
  assert.equal((await api('DELETE', '/api/orders/MPJ-20261119-11111', { token: tokens.owner })).status, 404);
  const { query } = await import('../src/db.js');
  assert.equal((await query(`SELECT stock FROM products WHERE id='pangsit-original'`)).rows[0].stock, 0);
  const pull = await api('GET', '/api/sync/pull?table=orders', { token: tokens.owner });
  const t = pull.json.rows.find((x) => x.id === 'MPJ-20261119-11111');
  assert.equal(t.deleted, true); assert.deepEqual(t.payload, { id: 'MPJ-20261119-11111' });
});

test('webhook: tanda tangan salah ditolak & dicatat; benar diterima; duplikat tidak menggandakan', { skip }, async () => {
  const { query } = await import('../src/db.js');
  const bad = await hook('gofood.order.awaiting_merchant_acceptance', 'F-1', {}, { badSig: true });
  assert.equal(bad.status, 401);
  const rej = (await query(`SELECT signature_ok, status, raw FROM webhook_events WHERE status='rejected' ORDER BY id DESC LIMIT 1`)).rows[0];
  assert.equal(rej.signature_ok, false); assert.equal(rej.raw, null);

  const eid = crypto.randomUUID();
  const ok = await hook('gofood.order.awaiting_merchant_acceptance', 'F-2174', {}, { eventId: eid });
  assert.equal(ok.status, 200); assert.equal((await ok.json()).status, 'accepted');
  const dup = await hook('gofood.order.awaiting_merchant_acceptance', 'F-2174', {}, { eventId: eid });
  assert.equal((await dup.json()).status, 'duplicate');
  assert.equal((await query(`SELECT count(*)::int n FROM online_orders WHERE id='ONL-GF-F-2174'`)).rows[0].n, 1);
  assert.equal((await query(`SELECT count(*)::int n FROM webhook_events WHERE status='duplicate'`)).rows[0].n, 1);
  const o = (await query(`SELECT payload FROM online_orders WHERE id='ONL-GF-F-2174'`)).rows[0].payload;
  assert.equal(o.status, 'baru'); assert.equal(o.items[0].productId, 'pangsit-original'); assert.equal(o.unmappedItems.length, 0);
  assert.equal((await fetch(`${base}/api/webhooks/grab`, { method: 'POST', body: '{}' })).status, 404);
  assert.equal((await fetch(`${base}/api/webhooks/gofood`, { method: 'POST', headers: { 'X-Go-Signature': sign('') } , body: '' })).status, 400);
  // outlet lain diabaikan
  const raw = JSON.stringify({ header: { event_name: 'gofood.order.created', event_id: 'zz1' }, body: { outlet: { id: 'LAIN' }, service_type: 'gofood', order: { order_number: 'F-9', order_items: [], status: 'CREATED' } } });
  const other = await fetch(`${base}/api/webhooks/gofood`, { method: 'POST', headers: { 'X-Go-Signature': sign(raw), 'Content-Type': 'application/json' }, body: raw });
  assert.equal((await other.json()).status, 'ignored');
});

test('status online: tidak mundur oleh webhook; transisi kasir mengantrekan aksi (tanpa ganda)', { skip }, async () => {
  const { query } = await import('../src/db.js');
  const cur = (await query(`SELECT payload FROM online_orders WHERE id='ONL-GF-F-2174'`)).rows[0].payload;
  const up = { ...cur, status: 'dibuat' };
  const push = () => api('POST', '/api/sync/push', { token: tokens.cashier, body: { table: 'online_orders', rows: [{ id: cur.id, payload: up }], deviceId: 'dev-1' } });
  assert.equal((await push()).status, 200); await push();
  let acts = (await query(`SELECT action, status FROM online_order_actions WHERE order_id=$1`, [cur.id])).rows;
  assert.deepEqual(acts.map((a) => a.action), ['accept']); // GoFood belum dikonfigurasi => tetap 'queued'
  await hook('gofood.order.awaiting_merchant_acceptance', 'F-2174'); // webhook lama datang terlambat
  assert.equal((await query(`SELECT payload->>'status' s FROM online_orders WHERE id=$1`, [cur.id])).rows[0].s, 'dibuat');
  await api('POST', '/api/sync/push', { token: tokens.cashier, body: { table: 'online_orders', rows: [{ id: cur.id, payload: { ...cur, status: 'siap' } }] } });
  acts = (await query(`SELECT action FROM online_order_actions WHERE order_id=$1 ORDER BY id`, [cur.id])).rows.map((a) => a.action);
  assert.deepEqual(acts, ['accept', 'ready']);
  // tolak pesanan baru (status lama 'baru') => reject; pesanan yang sudah diterima => tidak mengirim apa pun
  await hook('gofood.order.awaiting_merchant_acceptance', 'F-3000');
  await api('POST', '/api/sync/push', { token: tokens.cashier, body: { table: 'online_orders', rows: [{ id: 'ONL-GF-F-3000', deleted: true }] } });
  await api('POST', '/api/sync/push', { token: tokens.cashier, body: { table: 'online_orders', rows: [{ id: cur.id, deleted: true }] } });
  const all = (await query(`SELECT order_id, action FROM online_order_actions WHERE action='reject'`)).rows;
  assert.deepEqual(all, [{ order_id: 'ONL-GF-F-3000', action: 'reject' }]);
  // pesanan yang sudah ditutup tidak dihidupkan lagi oleh webhook susulan
  await hook('gofood.order.merchant_accepted', 'F-3000');
  assert.equal((await query(`SELECT deleted FROM online_orders WHERE id='ONL-GF-F-3000'`)).rows[0].deleted, true);
});

test('pengguna: buat, pemilik terakhir terlindungi, ganti sandi mencabut token lama', { skip }, async () => {
  assert.equal((await api('POST', '/api/users', { token: tokens.owner, body: { username: 'Kasir2', displayName: 'Kasir 2', role: 'Kasir', password: '1234' } })).status, 400);
  const c = await api('POST', '/api/users', { token: tokens.owner, body: { username: 'Kasir2', displayName: 'Kasir 2', role: 'Kasir', password: 'Kasir2-Kuat-2026' } });
  assert.equal(c.status, 201); assert.equal(c.json.user.username, 'kasir2'); assert.equal(c.json.user.passwordHash, undefined);
  assert.equal((await api('POST', '/api/users', { token: tokens.owner, body: { username: 'kasir2', displayName: 'x', role: 'Kasir', password: 'Kasir2-Kuat-2026' } })).status, 409);
  const me = await api('GET', '/api/auth/me', { token: tokens.owner });
  const last = await api('PUT', `/api/users/${me.json.user.id}`, { token: tokens.owner, body: { active: false } });
  assert.equal(last.status, 409); assert.equal(last.json.error, 'last_owner');
  assert.equal((await api('PUT', `/api/users/${me.json.user.id}`, { token: tokens.owner, body: { role: 'Kasir' } })).status, 409);
  const login = await api('POST', '/api/auth/login', { body: { username: 'kasir2', password: 'Kasir2-Kuat-2026' } });
  const oldTok = login.json.token;
  const ch = await api('POST', '/api/auth/change-password', { token: oldTok, body: { currentPassword: 'Kasir2-Kuat-2026', newPassword: 'Kasir2-Baru-2026' } });
  assert.equal(ch.status, 200);
  assert.equal((await api('GET', '/api/auth/me', { token: oldTok })).status, 401); // token lama mati
  assert.equal((await api('GET', '/api/auth/me', { token: ch.json.token })).status, 200);
  await api('PUT', `/api/users/${c.json.user.id}`, { token: tokens.owner, body: { active: false } });
  assert.equal((await api('GET', '/api/auth/me', { token: ch.json.token })).status, 401); // nonaktif => langsung mati
});

test('cron: butuh CRON_SECRET; online/config tidak membocorkan rahasia', { skip }, async () => {
  assert.equal((await api('GET', '/api/cron/maintenance')).status, 401);
  assert.equal((await api('GET', '/api/cron/maintenance', { headers: { Authorization: 'Bearer salah' } })).status, 401);
  const ok = await api('GET', '/api/cron/maintenance', { headers: { Authorization: 'Bearer cron-secret-1234567890' } });
  assert.equal(ok.status, 200);
  const cfg = await api('GET', '/api/online/config', { token: tokens.owner });
  const s = JSON.stringify(cfg.json);
  assert.ok(!s.includes(SECRET) && !s.includes('clientSecret'));
  const ev = await api('GET', '/api/online/webhooks', { token: tokens.owner });
  assert.ok(ev.json.events.length > 0); assert.equal(ev.json.events[0].raw, undefined);
});

test('keamanan HTTP: header, JSON rusak, content-type, ukuran, 404', { skip }, async () => {
  const r = await fetch(`${base}/api/health`);
  assert.equal(r.headers.get('x-powered-by'), null);
  assert.equal(r.headers.get('cache-control'), 'no-store');
  assert.ok(r.headers.get('strict-transport-security'));
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  const bad = await fetch(`${base}/api/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{rusak' });
  assert.equal(bad.status, 400);
  const ct = await fetch(`${base}/api/auth/login`, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: 'x' });
  assert.equal(ct.status, 415);
  const big = await fetch(`${base}/api/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ a: 'x'.repeat(3 * 1024 * 1024) }) });
  assert.equal(big.status, 413);
  assert.equal((await api('GET', '/api/tidak-ada')).status, 404);
  const cors = await fetch(`${base}/api/health`, { headers: { Origin: 'https://jahat.example' } });
  assert.equal(cors.headers.get('access-control-allow-origin'), null);
});
