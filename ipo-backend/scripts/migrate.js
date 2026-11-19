// Jalankan: npm run migrate   (butuh DATABASE_URL; dijalankan dari komputer Anda, BUKAN saat runtime Vercel)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { config } from '../src/config.js';
import { getPool, closePool } from '../src/db.js';

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations');

export async function migrate(log = console.log) {
  const client = await getPool().connect();
  try {
    await client.query('SELECT pg_advisory_lock(727001)'); // cegah migrasi ganda bersamaan
    await client.query('CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())');
    const done = new Set((await client.query('SELECT name FROM schema_migrations')).rows.map((r) => r.name));
    for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.sql')).sort()) {
      if (done.has(f)) { log(`- lewati ${f}`); continue; }
      try {
        await client.query('BEGIN');
        await client.query(fs.readFileSync(path.join(dir, f), 'utf8'));
        await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [f]);
        await client.query('COMMIT');
        log(`+ terapkan ${f}`);
      } catch (e) {
        await client.query('ROLLBACK');
        throw new Error(`Migrasi ${f} gagal: ${e.message}`);
      }
    }
  } finally {
    try { await client.query('SELECT pg_advisory_unlock(727001)'); } catch { /* sudah putus */ }
    client.release();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!config.dbConfigured) { console.error('DATABASE_URL belum diisi / masih placeholder.'); process.exit(1); }
  migrate().then(() => console.log('Selesai.')).catch((e) => { console.error(e.message); process.exitCode = 1; }).finally(closePool);
}
