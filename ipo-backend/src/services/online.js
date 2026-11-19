import { config } from '../config.js';
import { audit } from './audit.js';
import { ONLINE_STATUSES } from '../lib/schemas.js';

const RANK = Object.fromEntries(ONLINE_STATUSES.map((s, i) => [s, i]));
const PREFIX = { gofood: 'GF', grab: 'GR', shopee: 'SP' };

const clean = (v, max = 200) => (v == null ? '' : String(v).replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max));
const safeId = (v) => clean(v, 80).replace(/[^A-Za-z0-9_-]/g, '');

export const normName = (s) =>
  clean(s, 200).toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
export const baseName = (s) => normName(String(s || '').replace(/\(.*?\)|\[.*?\]|\s[-–]\s.*$/g, ''));

/** Ubah envelope GoBiz menjadi bentuk internal. Mengembalikan null bila bukan event pesanan. */
export function normalizeGoFood(env) {
  const header = env?.header || {};
  const body = env?.body || {};
  const order = body.order;
  const eventName = clean(header.event_name, 80);
  if (!eventName.startsWith('gofood.order.') || !order || typeof order !== 'object') return null;
  const orderNumber = safeId(order.order_number);
  if (!orderNumber) return null;
  const items = (Array.isArray(order.order_items) ? order.order_items : []).slice(0, 100).map((it) => {
    const variants = (Array.isArray(it.variants) ? it.variants : []).map((v) => clean(v.name, 60)).filter(Boolean);
    const note = [clean(it.notes, 150), variants.length ? `Varian: ${variants.join(', ')}` : ''].filter(Boolean).join(' | ');
    return {
      partnerMenuId: clean(it.external_id || it.id, 120),
      name: clean(it.name, 160),
      qty: Math.min(999, Math.max(1, Math.trunc(Number(it.quantity)) || 1)),
      price: Math.max(0, Math.trunc(Number(it.price)) || 0),
      note,
    };
  });
  return {
    eventName,
    eventId: clean(header.event_id, 80),
    partnerOrderId: orderNumber,
    partnerStatus: clean(order.status, 40).toUpperCase(),
    orderType: body.service_type === 'gofood_pickup' ? 'pickup' : 'delivery',
    outletId: clean(body.outlet?.id, 60),
    externalOutletId: clean(body.outlet?.external_outlet_id, 60),
    customer: clean(body.customer?.name, 120),
    driverName: clean(body.driver?.name, 120),
    pin: clean(order.pin, 12),
    total: Math.max(0, Math.trunc(Number(order.order_total)) || 0),
    createdAt: Number.isNaN(Date.parse(order.created_at)) ? new Date().toISOString() : new Date(order.created_at).toISOString(),
    items,
  };
}

/** Status partner -> status kasir. Tidak pernah menutup/menyelesaikan otomatis. */
export function mapStatus(partnerStatus) {
  switch (partnerStatus) {
    case 'MERCHANT_ACCEPTED':
    case 'PREP_ORDER_NOW': return 'dibuat';
    case 'DRIVER_OTW_PICKUP':
    case 'DRIVER_ARRIVED':
    case 'PLACED':
    case 'COMPLETED': return 'siap';
    default: return 'baru';
  }
}

/** peta manual -> id sama -> nama persis -> nama dasar -> awalan unik */
export function matchProduct(item, products, mapRows) {
  const manual = mapRows.get(item.partnerMenuId);
  if (manual?.product_id && products.some((p) => p.id === manual.product_id)) return { productId: manual.product_id, auto: false };
  if (manual && !manual.auto_matched && !manual.product_id) return null; // pemilik sengaja mengosongkan
  const byId = products.find((p) => p.id === item.partnerMenuId);
  if (byId) return { productId: byId.id, auto: true };
  const n = normName(item.name);
  if (!n) return null;
  const exact = products.filter((p) => normName(p.name) === n);
  if (exact.length === 1) return { productId: exact[0].id, auto: true };
  const b = baseName(item.name);
  const base = products.filter((p) => baseName(p.name) === b);
  if (b && base.length === 1) return { productId: base[0].id, auto: true };
  if (b.length >= 4) {
    const pre = products.filter((p) => {
      const pb = baseName(p.name);
      return pb.startsWith(b) || (pb.length >= 4 && b.startsWith(pb));
    });
    if (pre.length === 1) return { productId: pre[0].id, auto: true };
  }
  return null;
}

async function queueAction(db, { source, orderId, partnerOrderId, orderType, action, status = 'queued', reasonCode = null, reasonText = null }) {
  await db.query(
    `INSERT INTO online_order_actions (source, order_id, partner_order_id, order_type, action, status, reason_code, reason_text)
     SELECT $1,$2,$3,$4,$5,$6,$7,$8
      WHERE NOT EXISTS (SELECT 1 FROM online_order_actions WHERE order_id=$2 AND action=$5 AND status IN ('queued','sent','failed'))`,
    [source, orderId, partnerOrderId, orderType, action, status, reasonCode, reasonText]);
}

/** Dipanggil saat kasir mengubah status pesanan online (lewat sync push). */
export async function storeTransition(db, { oldPayload, newPayload, deleted, actor }) {
  const src = newPayload?.source || oldPayload?.source;
  if (!src) return;
  const base = {
    source: src,
    orderId: (newPayload || oldPayload).id,
    partnerOrderId: (newPayload || oldPayload).partnerOrderId || null,
    orderType: (newPayload || oldPayload).orderType || null,
  };
  if (!base.partnerOrderId) return;
  const off = src !== 'gofood' ? { status: 'ignored' } : {};
  const oldS = oldPayload?.status;
  if (deleted) {
    // Aksi tolak hanya bila pesanan belum diterima (status lama 'baru'); selain itu tidak mengirim apa pun.
    if (oldS === 'baru') {
      const { rows } = await db.query(`SELECT payload->>'onlineRejectionMessage' AS msg FROM settings WHERE id='main'`);
      await queueAction(db, { ...base, ...off, action: 'reject', reasonCode: config.gofood.rejectReasonCode, reasonText: clean(oldPayload?.rejectReason || rows[0]?.msg || 'Mohon maaf stok habis', 200) });
      await audit(db, actor, 'online:reject', base.orderId, null);
    }
    return;
  }
  const newS = newPayload.status;
  if (oldS === 'baru' && RANK[newS] >= RANK.dibuat) {
    await queueAction(db, { ...base, ...off, action: 'accept' });
    await audit(db, actor, 'online:accept', base.orderId, null);
  }
  if ((oldS == null || RANK[oldS] < RANK.siap) && RANK[newS] >= RANK.siap) {
    if (oldS === 'baru') await queueAction(db, { ...base, ...off, action: 'accept' });
    await queueAction(db, { ...base, ...off, action: 'ready' });
    await audit(db, actor, 'online:ready', base.orderId, null);
  }
}

/** Proses event GoFood (dipanggil di dalam transaksi DB). Mengembalikan {status, note}. */
export async function ingestGoFood(db, ev) {
  const gf = config.gofood;
  if (gf.outletId && ev.outletId !== gf.outletId && ev.externalOutletId !== gf.outletId) {
    return { status: 'ignored', note: 'outlet tidak cocok' };
  }
  const id = `ONL-${PREFIX.gofood}-${ev.partnerOrderId}`.slice(0, 68);
  const cur = (await db.query('SELECT payload, deleted FROM online_orders WHERE id=$1 FOR UPDATE', [id])).rows[0];
  if (cur?.deleted) return { status: 'ignored', note: 'pesanan sudah ditutup' };

  if (ev.partnerStatus === 'CANCELLED') {
    if (!cur) return { status: 'ignored', note: 'batal untuk pesanan yang belum dikenal' };
    if (cur.payload.status === 'baru') {
      await db.query('UPDATE online_orders SET deleted=true, updated_at=now() WHERE id=$1', [id]);
      await audit(db, 'sistem', 'online:cancelled_by_partner', id, null);
      return { status: 'accepted', note: 'dibatalkan mitra' };
    }
    await db.query(`UPDATE online_orders SET payload = jsonb_set(payload,'{partnerStatus}','"CANCELLED"'), updated_at=now() WHERE id=$1`, [id]);
    await queueAction(db, { source: 'gofood', orderId: id, partnerOrderId: ev.partnerOrderId, orderType: ev.orderType, action: 'cancel-review', status: 'manual' });
    await audit(db, 'sistem', 'online:cancel_review', id, null);
    return { status: 'accepted', note: 'dibatalkan mitra, perlu ditinjau' };
  }

  const products = (await db.query('SELECT id, name FROM products WHERE deleted=false')).rows;
  const mapRows = new Map((await db.query(`SELECT * FROM online_menu_map WHERE source='gofood'`)).rows.map((r) => [r.partner_menu_id, r]));
  const items = [];
  const unmapped = [];
  for (const it of ev.items) {
    const m = matchProduct(it, products, mapRows);
    if (m) {
      items.push({ productId: m.productId, qty: it.qty, note: it.note });
      if (m.auto && it.partnerMenuId) {
        await db.query(
          `INSERT INTO online_menu_map (id, source, partner_menu_id, partner_menu_name, product_id, auto_matched)
           VALUES ($1,'gofood',$2,$3,$4,true)
           ON CONFLICT (source, partner_menu_id) DO UPDATE SET product_id=COALESCE(online_menu_map.product_id, EXCLUDED.product_id), partner_menu_name=EXCLUDED.partner_menu_name, updated_at=now()`,
          [`gofood:${it.partnerMenuId}`.slice(0, 140), it.partnerMenuId, it.name, m.productId]);
      }
    } else {
      unmapped.push({ partnerMenuId: it.partnerMenuId, name: it.name, qty: it.qty, price: it.price, note: it.note });
      if (it.partnerMenuId) {
        await db.query(
          `INSERT INTO online_menu_map (id, source, partner_menu_id, partner_menu_name) VALUES ($1,'gofood',$2,$3)
           ON CONFLICT (source, partner_menu_id) DO NOTHING`,
          [`gofood:${it.partnerMenuId}`.slice(0, 140), it.partnerMenuId, it.name]);
      }
    }
  }

  const prevStatus = cur?.payload?.status || 'baru';
  const mapped = mapStatus(ev.partnerStatus);
  const status = RANK[mapped] > RANK[prevStatus] ? mapped : prevStatus; // tidak pernah mundur
  const payload = {
    ...(cur?.payload || {}),
    id, source: 'gofood', partnerOrderId: ev.partnerOrderId,
    partnerOutletId: ev.outletId, externalOutletId: ev.externalOutletId,
    orderType: ev.orderType, code: `GF-${ev.partnerOrderId}`,
    customer: ev.customer, driverName: ev.driverName, driverPin: ev.pin,
    note: ev.items.map((i) => i.note).filter(Boolean).join(' ; ').slice(0, 500),
    status, partnerStatus: ev.partnerStatus, createdAt: cur?.payload?.createdAt || ev.createdAt,
    items, unmappedItems: unmapped, partnerTotal: ev.total,
  };
  await db.query(
    `INSERT INTO online_orders (id, payload, device_id) VALUES ($1,$2,'webhook')
     ON CONFLICT (id) DO UPDATE SET payload=EXCLUDED.payload, updated_at=now(), device_id='webhook'`,
    [id, JSON.stringify(payload)]);

  if (!cur && gf.autoAccept) {
    await queueAction(db, { source: 'gofood', orderId: id, partnerOrderId: ev.partnerOrderId, orderType: ev.orderType, action: 'accept' });
  }
  return { status: 'accepted', note: cur ? 'diperbarui' : 'pesanan baru', orderId: id, isNew: !cur };
}
