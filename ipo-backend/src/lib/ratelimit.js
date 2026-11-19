import { query } from '../db.js';
import { AppError } from './errors.js';

/**
 * Rate limit berbasis PostgreSQL (jendela tetap). Dipakai untuk login & webhook karena
 * penghitung in-memory tidak berbagi state antar instance serverless.
 * Gagal tertutup: jika DB bermasalah, error DB diteruskan (bukan melonggarkan batas).
 */
export async function hit(key, limit, windowSec) {
  const { rows } = await query(
    `INSERT INTO rate_limits (key, count, reset_at)
          VALUES ($1, 1, now() + ($2::int * interval '1 second'))
     ON CONFLICT (key) DO UPDATE SET
       count    = CASE WHEN rate_limits.reset_at <= now() THEN 1 ELSE rate_limits.count + 1 END,
       reset_at = CASE WHEN rate_limits.reset_at <= now() THEN now() + ($2::int * interval '1 second')
                       ELSE rate_limits.reset_at END
     RETURNING count, GREATEST(1, CEIL(EXTRACT(EPOCH FROM (reset_at - now()))))::int AS retry_after`,
    [key, windowSec],
  );
  const { count, retry_after: retryAfter } = rows[0];
  return { allowed: count <= limit, count, retryAfter };
}

/** Lempar 429 bila melebihi batas. */
export async function enforce(key, limit, windowSec, message = 'Terlalu banyak percobaan. Coba lagi nanti.') {
  const r = await hit(key, limit, windowSec);
  if (!r.allowed) {
    const err = new AppError(429, 'rate_limited', message, { retryAfter: r.retryAfter });
    err.retryAfter = r.retryAfter;
    throw err;
  }
}

export async function resetKey(key) {
  await query('DELETE FROM rate_limits WHERE key = $1', [key]);
}
