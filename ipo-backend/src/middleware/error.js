import { AppError } from '../lib/errors.js';

export function notFoundHandler(req, res) {
  res.status(404).json({ error: 'not_found', message: 'Endpoint tidak ditemukan.' });
}

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  if (res.headersSent) return;
  let status = 500;
  let body = { error: 'internal_error', message: 'Terjadi kesalahan pada server.' };

  if (err instanceof AppError) {
    status = err.status;
    body = { error: err.code, message: err.message, ...(err.extra || {}) };
    if (err.retryAfter) res.set('Retry-After', String(err.retryAfter));
  } else if (err?.type === 'entity.too.large') {
    status = 413;
    body = { error: 'payload_too_large', message: 'Data terlalu besar.' };
  } else if (err?.type === 'entity.parse.failed' || err instanceof SyntaxError) {
    status = 400;
    body = { error: 'invalid_json', message: 'Body bukan JSON yang valid.' };
  } else if (err?.code === '23505') {
    status = 409;
    body = { error: 'conflict', message: 'Data sudah ada.' };
  } else if (err?.code === '23514' || err?.code === '22003' || err?.code === '22P02') {
    status = 422;
    body = { error: 'invalid_data', message: 'Data melanggar aturan database.' };
  } else if (['ECONNREFUSED', 'ETIMEDOUT', 'ENOTFOUND', '57P01', '53300', '08006', '08001'].includes(err?.code)) {
    status = 503;
    body = { error: 'database_unavailable', message: 'Database sementara tidak tersedia.' };
  }

  if (status >= 500) {
    // Hanya metadata: tidak ada body request, token, atau stack ke klien/log.
    console.error(JSON.stringify({ level: 'error', code: err?.code || err?.name, msg: String(err?.message).slice(0, 200), path: req.path }));
  }
  res.status(status).json(body);
}
