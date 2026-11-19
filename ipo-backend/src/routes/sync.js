import { Router } from 'express';
import { ah } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { syncPushSchema } from '../lib/schemas.js';
import { requireAuth } from '../middleware/auth.js';
import { pushRows, pullTable, CLIENT_TABLES } from '../services/sync.js';
import { kickQueue } from '../lib/background.js';

const r = Router();
r.use(requireAuth);

r.get('/tables', (req, res) => res.json({ tables: CLIENT_TABLES }));

r.post('/push', ah(async (req, res) => {
  const body = parse(syncPushSchema, req.body, 'Sinkronisasi');
  const result = await pushRows(body, req.user);
  if (body.table === 'online_orders') kickQueue(); // kirim aksi ke mitra tanpa menahan respons
  res.json({ ok: true, table: body.table, ...result, serverTime: new Date().toISOString() });
}));

r.get('/pull', ah(async (req, res) => {
  const { table, since, sinceId, limit } = req.query;
  const one = (v) => (typeof v === 'string' ? v : undefined); // tolak array/objek dari query string
  res.json(await pullTable(one(table), { since: one(since), sinceId: one(sinceId), limit: one(limit) }));
}));

export default r;
