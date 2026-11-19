import { Router } from 'express';
import { config } from '../config.js';
import { query } from '../db.js';
import { ah, notFound, badRequest } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { menuMapSchema } from '../lib/schemas.js';
import { requireAuth, requireOwner } from '../middleware/auth.js';
import { audit } from '../services/audit.js';
import { listSubscriptions, processAction, processQueue, subscribeAll } from '../services/gofood.js';

const r = Router();
r.use(requireAuth);

const lim = (v, d = 50) => Math.min(Math.max(Number.parseInt(typeof v === 'string' ? v : '', 10) || d, 1), 200);

// Status konfigurasi tanpa rahasia (hanya boolean/URL publik).
r.get('/config', requireOwner, (req, res) => {
  const g = config.gofood;
  res.json({
    gofood: {
      apiReady: g.apiReady, notificationSecretSet: Boolean(g.notificationSecret), webhookUrl: g.webhookUrl || null,
      autoAccept: g.autoAccept, rejectReasonCode: g.rejectReasonCode, apiBase: g.apiBase, outletIdSet: Boolean(g.outletId),
    },
    grab: { supported: false }, shopee: { supported: false },
  });
});

r.get('/orders', ah(async (req, res) => {
  const { rows } = await query(`SELECT id, payload, updated_at FROM online_orders WHERE deleted = false ORDER BY updated_at DESC LIMIT $1`, [lim(req.query.limit, 100)]);
  res.json({ orders: rows.map((x) => ({ ...x.payload, updatedAt: x.updated_at })) });
}));

r.get('/menu-map', ah(async (req, res) => {
  const { rows } = await query(
    `SELECT m.id, m.source, m.partner_menu_id, m.partner_menu_name, m.product_id, m.auto_matched, p.name AS product_name
       FROM online_menu_map m LEFT JOIN products p ON p.id = m.product_id ORDER BY m.source, m.partner_menu_name LIMIT 500`);
  res.json({ items: rows });
}));

r.put('/menu-map', requireOwner, ah(async (req, res) => {
  const d = parse(menuMapSchema, req.body, 'Peta menu');
  if (d.productId) {
    const p = await query('SELECT 1 FROM products WHERE id=$1 AND deleted=false', [d.productId]);
    if (!p.rows[0]) throw badRequest('Produk tidak ditemukan.', 'product_not_found');
  }
  const { rows } = await query(
    `INSERT INTO online_menu_map (id, source, partner_menu_id, partner_menu_name, product_id, auto_matched)
     VALUES ($1,$2,$3,$4,$5,false)
     ON CONFLICT (source, partner_menu_id) DO UPDATE SET product_id=EXCLUDED.product_id,
       partner_menu_name=COALESCE(EXCLUDED.partner_menu_name, online_menu_map.partner_menu_name), auto_matched=false, updated_at=now()
     RETURNING *`,
    [`${d.source}:${d.partnerMenuId}`.slice(0, 140), d.source, d.partnerMenuId, d.partnerMenuName || null, d.productId]);
  await audit({ query }, req.user.username, 'online.menu_map', rows[0].id, { productId: d.productId });
  res.json({ item: rows[0] });
}));

r.get('/actions', ah(async (req, res) => {
  const { rows } = await query(
    `SELECT id, source, order_id, partner_order_id, order_type, action, status, attempts, reason_code, reason_text, error, created_at, updated_at
       FROM online_order_actions ORDER BY id DESC LIMIT $1`, [lim(req.query.limit)]);
  res.json({ actions: rows });
}));

r.post('/actions/process', requireOwner, ah(async (req, res) => res.json({ results: await processQueue(20) })));

r.post('/actions/:id/retry', ah(async (req, res) => {
  if (!/^\d{1,18}$/.test(req.params.id)) throw badRequest('ID tidak valid.');
  const a = await query('SELECT status FROM online_order_actions WHERE id=$1', [req.params.id]);
  if (!a.rows[0]) throw notFound('Aksi tidak ditemukan.');
  // 'manual' (gagal permanen/ditinjau) boleh dicoba ulang oleh pemilik saja.
  if (a.rows[0].status === 'manual') {
    if (req.user.role !== 'Pemilik') throw badRequest('Hanya Pemilik yang boleh mengulang aksi manual.', 'owner_only');
    await query(`UPDATE online_order_actions SET status='queued', attempts=0, error=NULL, updated_at=now() WHERE id=$1`, [req.params.id]);
  }
  res.json({ result: await processAction(req.params.id) });
}));

r.get('/webhooks', requireOwner, ah(async (req, res) => {
  const { rows } = await query(
    `SELECT id, source, event_type, entity_id, signature_ok, status, note, created_at
       FROM webhook_events ORDER BY id DESC LIMIT $1`, [lim(req.query.limit)]); // raw TIDAK dikembalikan
  res.json({ events: rows });
}));

r.post('/gofood/cek', requireOwner, ah(async (req, res) => {
  const s = await listSubscriptions();
  res.json({ ok: s.ok, httpStatus: s.status, subscriptions: s.data?.data?.subscriptions?.length ?? null });
}));

r.post('/gofood/langganan', requireOwner, ah(async (req, res) => {
  const results = await subscribeAll();
  await audit({ query }, req.user.username, 'online.gofood_subscribe', null, { count: results.length });
  res.json({ results });
}));

export default r;
