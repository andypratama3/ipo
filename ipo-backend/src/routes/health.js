import { Router } from 'express';
import { config } from '../config.js';
import { query } from '../db.js';
import { ah } from '../lib/errors.js';

const r = Router();
// Selalu 200 selama proses hidup. Tidak membocorkan detail konfigurasi.
r.get('/', ah(async (req, res) => {
  let db = 'unconfigured';
  if (config.dbConfigured) {
    try {
      await Promise.race([query('SELECT 1'), new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 3000))]);
      db = 'up';
    } catch { db = 'down'; }
  }
  res.json({ ok: true, db, time: new Date().toISOString() });
}));
export default r;
