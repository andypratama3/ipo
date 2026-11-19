import { config } from '../config.js';
import { query, tx } from '../db.js';
import { ah, notFound } from '../lib/errors.js';
import { enforce } from '../lib/ratelimit.js';
import { sha256Hex, verifyGoSignature } from '../lib/crypto.js';
import { ingestGoFood, normalizeGoFood } from '../services/online.js';
import { kickQueue } from '../lib/background.js';

const logEvent = (db, e) =>
  db.query(
    `INSERT INTO webhook_events (source, event_type, entity_id, idempotency_key, signature_ok, status, note, raw)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
    [e.source, e.eventType || null, e.entityId || null, e.key || null, Boolean(e.sigOk), e.status, (e.note || '').slice(0, 300), e.raw ? JSON.stringify(e.raw) : null]);

/** Dipasang dengan express.raw() supaya tanda tangan dihitung dari byte asli, bukan hasil parse. */
export const webhookHandler = ah(async (req, res) => {
  const source = String(req.params.source || '').toLowerCase();
  // Hanya GoFood yang punya verifikasi tanda tangan. Sumber lain ditolak (jangan terima webhook tanpa autentikasi).
  if (source !== 'gofood') throw notFound('Sumber webhook tidak didukung.');
  await enforce(`wh:${source}:${req.ip}`, 300, 60, 'Terlalu banyak permintaan webhook.');

  const raw = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
  const sigOk = verifyGoSignature(raw, req.headers['x-go-signature'], config.gofood.notificationSecret);
  if (!sigOk) {
    // Isi body penyerang TIDAK disimpan; hanya ukuran & hash untuk jejak.
    await logEvent({ query }, { source, sigOk: false, status: 'rejected', note: `tanda tangan tidak valid; bytes=${raw.length}; sha256=${sha256Hex(raw).slice(0, 16)}` });
    return res.status(401).json({ error: 'invalid_signature', message: 'Tanda tangan tidak valid.' });
  }

  let env;
  try { env = JSON.parse(raw.toString('utf8')); } catch { env = null; }
  if (!env || typeof env !== 'object') {
    await logEvent({ query }, { source, sigOk: true, status: 'rejected', note: 'JSON tidak valid' });
    return res.status(400).json({ error: 'invalid_json', message: 'Body bukan JSON.' });
  }

  const headerKey = String(req.headers['x-go-idempotency-key'] || '').trim();
  const rawKey = headerKey || String(env?.header?.event_id || '').trim();
  const key = /^[\w.:-]{1,128}$/.test(rawKey) ? rawKey : '';
  const ev = normalizeGoFood(env);
  const meta = { source, sigOk: true, key, eventType: String(env?.header?.event_name || '').slice(0, 80), entityId: ev?.partnerOrderId, raw: env };

  let result;
  try {
    result = await tx(async (db) => {
      // Klaim kunci idempotensi di transaksi yang SAMA dengan pemrosesan: gagal => rollback => mitra bisa mengirim ulang.
      const claim = await db.query(
        `INSERT INTO webhook_events (source, event_type, entity_id, idempotency_key, signature_ok, status, raw)
         VALUES ($1,$2,$3,$4,true,'accepted',$5)
         ${key ? 'ON CONFLICT (source, idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING' : ''}
         RETURNING id`,
        [source, meta.eventType || null, meta.entityId || null, key || null, JSON.stringify(env)]);
      if (!claim.rows[0]) return { status: 'duplicate' };
      if (!ev) {
        await db.query(`UPDATE webhook_events SET status='ignored', note='bukan event pesanan' WHERE id=$1`, [claim.rows[0].id]);
        return { status: 'ignored' };
      }
      const out = await ingestGoFood(db, ev);
      await db.query('UPDATE webhook_events SET status=$2, note=$3 WHERE id=$1', [claim.rows[0].id, out.status, (out.note || '').slice(0, 300)]);
      return out;
    });
  } catch (e) {
    await logEvent({ query }, { ...meta, key: '', raw: null, status: 'error', note: `gagal diproses: ${String(e.code || e.name)}` }).catch(() => {});
    throw e; // 500 -> GoBiz mengirim ulang (at-least-once)
  }

  if (result.status === 'duplicate') {
    await logEvent({ query }, { ...meta, key: '', raw: null, status: 'duplicate', note: `duplikat dari kunci ${key}` });
  }
  if (result.isNew && config.gofood.autoAccept) kickQueue();
  res.status(200).json({ ok: true, status: result.status });
});
