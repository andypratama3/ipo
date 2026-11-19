import pg from 'pg';
import { config } from './config.js';
import { AppError } from './lib/errors.js';

// DATE (oid 1082) tetap string 'YYYY-MM-DD' (tanpa konversi zona waktu), COUNT/int8 tetap string.
pg.types.setTypeParser(1082, (v) => v);

let pool = null;

export function getPool() {
  if (!config.dbConfigured) {
    throw new AppError(503, 'database_not_configured', 'Database belum dikonfigurasi di server.');
  }
  if (!pool) {
    pool = new pg.Pool({
      connectionString: config.databaseUrl,
      // Neon memakai sertifikat publik; selalu verifikasi kecuali DB lokal (dev).
      ssl: config.dbLocal ? false : { rejectUnauthorized: true },
      max: 5,
      idleTimeoutMillis: 10_000,
      connectionTimeoutMillis: 8_000,
      statement_timeout: 15_000,
      query_timeout: 20_000,
      allowExitOnIdle: true,
    });
    pool.on('error', (e) => console.error(JSON.stringify({ level: 'error', msg: 'pg pool', code: e.code })));
  }
  return pool;
}

export const query = (text, params) => getPool().query(text, params);

/** Jalankan fn dalam satu transaksi (BEGIN/COMMIT, ROLLBACK jika error). */
export async function tx(fn) {
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    const out = await fn(client);
    await client.query('COMMIT');
    return out;
  } catch (e) {
    try { await client.query('ROLLBACK'); } catch { /* koneksi sudah putus */ }
    throw e;
  } finally {
    client.release();
  }
}

export async function closePool() {
  if (pool) { await pool.end(); pool = null; }
}
