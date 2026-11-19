import { Router } from 'express';
import { config } from '../config.js';
import { query } from '../db.js';
import { ah, unauthorized } from '../lib/errors.js';
import { safeEqual } from '../lib/crypto.js';
import { processQueue } from '../services/gofood.js';

const r = Router();

// Vercel Cron mengirim "Authorization: Bearer $CRON_SECRET" bila env CRON_SECRET diset.
r.get('/maintenance', ah(async (req, res) => {
  const given = String(req.headers.authorization || '');
  if (!config.cronSecret || config.cronSecret.length < 16 || !safeEqual(given, `Bearer ${config.cronSecret}`)) throw unauthorized('Tidak diizinkan.');
  const actions = await processQueue(20);
  const rl = await query(`DELETE FROM rate_limits WHERE reset_at < now() - interval '1 hour'`);
  const wh = await query(`DELETE FROM webhook_events WHERE created_at < now() - ($1::int * interval '1 day')`, [config.webhookRetentionDays]);
  res.json({ ok: true, actionsProcessed: actions.length, rateLimitsPurged: rl.rowCount, webhookEventsPurged: wh.rowCount });
}));

export default r;
