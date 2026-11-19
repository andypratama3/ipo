import { tx } from '../db.js';
import { badRequest } from '../lib/errors.js';
import { PAYMENTS } from '../lib/schemas.js';
import { audit } from './audit.js';

const MAX_INT = 2_147_483_647;
const TS = `to_char(%s AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;
export const tsSql = (col) => TS.replace('%s', col);

/** Hitung ulang total. Murni (mudah diuji): harga resmi menggantikan harga klien. */
export function computeTotals({ items, discount, payment, paidAmount }) {
  let subtotal = 0;
  const lines = items.map((it) => {
    const total = it.price * it.qty;
    subtotal += total;
    return { ...it, total };
  });
  if (subtotal > MAX_INT) throw badRequest('Total pesanan terlalu besar.', 'total_too_large');
  const disc = Math.min(Math.max(Number(discount) || 0, 0), subtotal);
  const total = subtotal - disc;
  const pay = PAYMENTS.includes(payment) ? payment : 'cash';
  let paid = total;
  let change = 0;
  if (pay === 'cash') {
    paid = Math.max(Number(paidAmount) || 0, total);
    change = paid - total;
  }
  return { lines, subtotal, discount: disc, total, payment: pay, paidAmount: paid, changeAmount: change };
}

export function orderDateFromId(id, createdAt) {
  const m = /^[A-Z]+-(\d{4})(\d{2})(\d{2})-/.exec(id);
  if (m) {
    const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
    if (d.getUTCFullYear() === +m[1] && d.getUTCMonth() === +m[2] - 1 && d.getUTCDate() === +m[3]) {
      return `${m[1]}-${m[2]}-${m[3]}`;
    }
  }
  return new Date(createdAt).toISOString().slice(0, 10);
}

export function buildPayload(t, items) {
  return {
    id: t.id,
    clientTxnId: t.client_txn_id,
    createdAt: t.created_iso,
    items: items.map((i) => ({ productId: i.product_id, name: i.name, price: i.price, qty: i.qty, total: i.total, note: i.note || '' })),
    orderType: t.order_type,
    tableNumber: t.table_number || '',
    subtotal: t.subtotal,
    discount: t.discount,
    total: t.total,
    taxRate: Number(t.tax_rate),
    taxIncluded: true,
    payment: t.payment,
    paidAmount: t.paid_amount,
    changeAmount: t.change_amount,
    status: t.status,
    cashier: t.cashier || '',
    note: t.note || '',
  };
}

async function loadExisting(db, id, clientTxnId) {
  const { rows } = await db.query(
    `SELECT *, ${tsSql('created_at')} AS created_iso FROM transactions WHERE id = $1 OR client_txn_id = $2 LIMIT 1`,
    [id, clientTxnId],
  );
  if (!rows[0]) return null;
  const items = await db.query('SELECT * FROM transaction_items WHERE transaction_id = $1 ORDER BY id', [rows[0].id]);
  return buildPayload(rows[0], items.rows);
}

export async function createOrder(input, user) {
  const o = input.order;
  const deviceId = input.deviceId || null;
  const created = new Date(o.createdAt);
  if (created.getTime() > Date.now() + 24 * 3600 * 1000) throw badRequest('Tanggal transaksi di masa depan.', 'bad_date');

  try {
    return await tx(async (db) => {
      const dup = await loadExisting(db, o.id, o.clientTxnId);
      if (dup) return { duplicate: true, order: dup };

      const ids = [...new Set(o.items.map((i) => i.productId).filter(Boolean))].sort();
      const prod = new Map();
      if (ids.length) {
        const r = await db.query(
          'SELECT id, name, price, stock FROM products WHERE id = ANY($1::text[]) AND deleted = false ORDER BY id FOR UPDATE',
          [ids],
        );
        r.rows.forEach((p) => prod.set(p.id, p));
      }
      const unverified = [];
      const items = o.items.map((it) => {
        const p = it.productId ? prod.get(it.productId) : null;
        if (!p) { unverified.push(it.productId || it.name); return { ...it, productId: it.productId || null }; }
        return { ...it, name: p.name, price: p.price };
      });

      const s = await db.query(`SELECT payload->'taxRate' AS tax FROM settings WHERE id = 'main' AND deleted = false`);
      const taxRaw = Number(s.rows[0]?.tax);
      const taxRate = Number.isFinite(taxRaw) ? Math.min(100, Math.max(0, taxRaw)) : 0;

      const c = computeTotals({ items, discount: o.discount, payment: o.payment, paidAmount: o.paidAmount });
      const orderDate = orderDateFromId(o.id, o.createdAt);

      await db.query(
        `INSERT INTO transactions (id, client_txn_id, created_at, order_date, order_type, table_number, subtotal, discount,
           tax_rate, total, payment, paid_amount, change_amount, status, cashier, note, device_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'paid',$14,$15,$16)`,
        [o.id, o.clientTxnId, created.toISOString(), orderDate, o.orderType || null, o.tableNumber || null, c.subtotal,
          c.discount, taxRate, c.total, c.payment, c.paidAmount, c.changeAmount, o.cashier || user.displayName, o.note || null, deviceId],
      );
      for (const l of c.lines) {
        await db.query(
          'INSERT INTO transaction_items (transaction_id, product_id, name, price, qty, total, note) VALUES ($1,$2,$3,$4,$5,$6,$7)',
          [o.id, l.productId || null, l.name, l.price, l.qty, l.total, l.note || null],
        );
      }

      // Stok: hanya produk bertipe stok terbatas; minimum 0; kunci baris sudah diambil (FOR UPDATE).
      const need = new Map();
      c.lines.forEach((l) => { if (l.productId && prod.get(l.productId)?.stock != null) need.set(l.productId, (need.get(l.productId) || 0) + l.qty); });
      for (const [pid, qty] of need) {
        const before = prod.get(pid).stock;
        const after = Math.max(before - qty, 0);
        if (before < qty) await audit(db, user.username, 'stock.conflict', pid, { before, qty, order: o.id });
        await db.query(
          `UPDATE products SET stock = $2, payload = jsonb_set(payload, '{stock}', to_jsonb($2::int)), updated_at = now() WHERE id = $1`,
          [pid, after],
        );
        await db.query(`INSERT INTO stock_movements (product_id, qty, reason, ref, device_id) VALUES ($1,$2,'sale',$3,$4)`, [pid, -(before - after), o.id, deviceId]);
      }
      if (unverified.length) await audit(db, user.username, 'order.item_unverified', o.id, { items: unverified.slice(0, 20) });
      await audit(db, user.username, 'order.created', o.id, { total: c.total, payment: c.payment });

      return { duplicate: false, order: await loadExisting(db, o.id, o.clientTxnId) };
    });
  } catch (e) {
    if (e.code === '23505') { // balapan: permintaan kembar masuk bersamaan
      return tx(async (db) => ({ duplicate: true, order: await loadExisting(db, o.id, o.clientTxnId) }));
    }
    throw e;
  }
}

export async function deleteOrder(id, user) {
  return tx(async (db) => {
    const r = await db.query('UPDATE transactions SET deleted = true, updated_at = now() WHERE id = $1 AND deleted = false RETURNING id', [id]);
    if (!r.rows[0]) return false;
    await audit(db, user.username, 'order.deleted', id, null); // stok SENGAJA tidak dikembalikan
    return true;
  });
}

export async function pullOrders(db, { since, sinceId, limit }) {
  const params = [limit + 1];
  let where = '';
  if (since) { params.push(since, sinceId || ''); where = `WHERE (updated_at, id) > ($2::timestamptz, $3::text)`; }
  const r = await db.query(
    `SELECT *, ${tsSql('created_at')} AS created_iso, ${tsSql('updated_at')} AS updated_iso
       FROM transactions ${where} ORDER BY updated_at, id LIMIT $1`, params);
  const hasMore = r.rows.length > limit;
  const rows = r.rows.slice(0, limit);
  const items = rows.length
    ? (await db.query('SELECT * FROM transaction_items WHERE transaction_id = ANY($1::text[]) ORDER BY id', [rows.filter((t) => !t.deleted).map((t) => t.id)])).rows
    : [];
  const by = new Map();
  items.forEach((i) => by.set(i.transaction_id, [...(by.get(i.transaction_id) || []), i]));
  return {
    rows: rows.map((t) => ({
      id: t.id, deleted: t.deleted, updatedAt: t.updated_iso,
      payload: t.deleted ? { id: t.id } : buildPayload(t, by.get(t.id) || []),
    })),
    hasMore,
  };
}
