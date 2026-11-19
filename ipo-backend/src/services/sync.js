import { tx } from '../db.js';
import { badRequest, forbidden } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import {
  productSchema, categorySchema, settingsSchema, pendingOrderSchema, onlineOrderSchema,
  jsonSize, MAX_PAYLOAD_BYTES,
} from '../lib/schemas.js';
import { audit } from './audit.js';
import { pullOrders, tsSql } from './orders.js';
import { storeTransition } from './online.js';

// Nama tabel TIDAK pernah berasal dari input: hanya dari Map statis ini (daftar putih).
const TABLES = new Map([
  ['products',       { sql: 'products',       owner: true,  schema: productSchema }],
  ['categories',     { sql: 'categories',     owner: true,  schema: categorySchema }],
  ['settings',       { sql: 'settings',       owner: true,  schema: settingsSchema }],
  ['pending_orders', { sql: 'pending_orders', owner: false, schema: pendingOrderSchema }],
  ['online_orders',  { sql: 'online_orders',  owner: false, schema: onlineOrderSchema }],
]);

export const CLIENT_TABLES = ['products', 'categories', 'settings', 'orders', 'pending_orders', 'online_orders'];
export const isPullable = (t) => TABLES.has(t) || t === 'orders';

export async function pushRows({ table, rows, deviceId }, user) {
  const def = TABLES.get(table); // 'orders' & nama lain -> undefined -> ditolak
  if (!def) throw badRequest('Tabel tidak dikenal.', 'unknown_table');
  if (def.owner && user.role !== 'Pemilik') throw forbidden('Hanya Pemilik yang boleh mengubah data ini.');

  // Validasi SEMUA baris dulu (atomik: satu salah, tidak ada yang tersimpan).
  const prepared = rows.map((row, idx) => {
    const rowId = table === 'settings' ? 'main' : row.id;
    if (row.deleted) return { id: rowId, deleted: true };
    if (!row.payload) throw badRequest(`Baris ${idx}: payload wajib.`, 'validation_error', { rowId: row.id });
    if (jsonSize(row.payload) > MAX_PAYLOAD_BYTES) throw badRequest(`Baris ${idx}: payload terlalu besar.`, 'payload_too_large', { rowId: row.id });
    const candidate = table === 'settings' ? row.payload : { ...row.payload, id: row.payload.id ?? row.id };
    if (table !== 'settings' && candidate.id !== row.id) throw badRequest(`Baris ${idx}: id payload tidak sama dengan id baris.`, 'id_mismatch', { rowId: row.id });
    let data;
    try { data = parse(def.schema, candidate, `Baris ${idx}`); }
    catch (e) { e.extra = { ...(e.extra || {}), rowId: row.id }; throw e; }
    return { id: rowId, deleted: false, data };
  });

  return tx(async (db) => {
    const ids = prepared.map((p) => p.id);
    const old = new Map((await db.query(`SELECT id, payload, deleted${table === 'products' ? ', stock' : ''} FROM ${def.sql} WHERE id = ANY($1::text[]) FOR UPDATE`, [ids])).rows.map((r) => [r.id, r]));

    for (const p of prepared) {
      const prev = old.get(p.id);
      if (p.deleted) {
        // Tombstone = UPDATE saja (tidak membuat baris baru untuk id yang tidak ada).
        if (!prev || prev.deleted) continue;
        await db.query(`UPDATE ${def.sql} SET deleted = true, updated_at = now(), device_id = $2 WHERE id = $1`, [p.id, deviceId || null]);
        if (table === 'online_orders') await storeTransition(db, { oldPayload: prev.payload, newPayload: null, deleted: true, actor: user.username });
        continue;
      }
      if (table === 'products') {
        const d = p.data;
        await db.query(
          `INSERT INTO products (id, name, category_id, price, stock, available, description, emoji, payload, device_id)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
           ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, category_id=EXCLUDED.category_id, price=EXCLUDED.price,
             stock=EXCLUDED.stock, available=EXCLUDED.available, description=EXCLUDED.description, emoji=EXCLUDED.emoji,
             payload=EXCLUDED.payload, deleted=false, updated_at=now(), device_id=EXCLUDED.device_id`,
          [d.id, d.name, d.category || null, d.price, d.stock, d.available, d.description || null, d.emoji || null, JSON.stringify(d), deviceId || null]);
        if (prev && !prev.deleted && prev.stock != null && d.stock != null && prev.stock !== d.stock) {
          await db.query(`INSERT INTO stock_movements (product_id, qty, reason, ref, device_id) VALUES ($1,$2,'adjust','catalog',$3)`, [d.id, d.stock - prev.stock, deviceId || null]);
        }
        continue;
      }
      if (table === 'online_orders') {
        if (prev?.deleted) continue; // pesanan yang sudah ditutup tidak dihidupkan lagi
        await db.query(
          `INSERT INTO online_orders (id, payload, device_id) VALUES ($1,$2,$3)
           ON CONFLICT (id) DO UPDATE SET payload=EXCLUDED.payload, updated_at=now(), device_id=EXCLUDED.device_id`,
          [p.id, JSON.stringify(p.data), deviceId || null]);
        await storeTransition(db, { oldPayload: prev?.payload, newPayload: p.data, deleted: false, actor: user.username });
        continue;
      }
      await db.query(
        `INSERT INTO ${def.sql} (id, payload, device_id) VALUES ($1,$2,$3)
         ON CONFLICT (id) DO UPDATE SET payload=EXCLUDED.payload, deleted=false, updated_at=now(), device_id=EXCLUDED.device_id`,
        [p.id, JSON.stringify(p.data), deviceId || null]);
    }
    if (table === 'settings') await audit(db, user.username, 'settings.updated', 'main', null);
    return { accepted: prepared.length };
  });
}

const CURSOR_TS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/;

export async function pullTable(table, { since, sinceId, limit }) {
  if (!isPullable(table)) throw badRequest('Tabel tidak dikenal.', 'unknown_table');
  if (since && !CURSOR_TS.test(since)) throw badRequest('Parameter since tidak valid.', 'bad_cursor');
  const lim = Math.min(Math.max(Number.parseInt(limit, 10) || 1000, 1), 1000);

  const run = async (db) => {
    if (table === 'orders') return pullOrders(db, { since, sinceId, limit: lim });
    const def = TABLES.get(table);
    const params = [lim + 1];
    let where = '';
    if (since) { params.push(since, sinceId || ''); where = 'WHERE (updated_at, id) > ($2::timestamptz, $3::text)'; }
    const r = await db.query(`SELECT id, payload, deleted, ${tsSql('updated_at')} AS updated_iso FROM ${def.sql} ${where} ORDER BY updated_at, id LIMIT $1`, params);
    return {
      hasMore: r.rows.length > lim,
      rows: r.rows.slice(0, lim).map((x) => ({ id: x.id, deleted: x.deleted, updatedAt: x.updated_iso, payload: x.deleted && table === 'online_orders' ? { id: x.id } : x.payload })),
    };
  };
  const out = await tx(run);
  const last = out.rows[out.rows.length - 1];
  return {
    table,
    rows: out.rows,
    hasMore: out.hasMore,
    cursor: last ? { since: last.updatedAt, sinceId: last.id } : (since ? { since, sinceId: sinceId || '' } : null),
    serverTime: new Date().toISOString(),
  };
}
