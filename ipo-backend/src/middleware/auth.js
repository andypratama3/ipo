import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { query } from '../db.js';
import { AppError, ah, unauthorized, forbidden } from '../lib/errors.js';

const BEARER = /^Bearer ([A-Za-z0-9._~+/=-]{20,2048})$/;

export function signToken(user) {
  const expiresInSec = config.jwtTtlHours * 3600;
  const token = jwt.sign({ tv: user.token_version }, config.jwtSecret, {
    algorithm: 'HS256',
    subject: String(user.id),
    issuer: config.jwtIssuer,
    audience: config.jwtAudience,
    expiresIn: expiresInSec,
  });
  return { token, expiresAt: new Date(Date.now() + expiresInSec * 1000).toISOString() };
}

export function requireConfig(req, res, next) {
  if (!config.jwtOk) {
    return next(new AppError(503, 'server_misconfigured', 'Server belum dikonfigurasi dengan benar.'));
  }
  next();
}

/** Verifikasi JWT (HS256 saja) lalu cek ulang user di DB: nonaktif / ganti sandi => token langsung mati. */
export const requireAuth = ah(async (req, res, next) => {
  if (!config.jwtOk) throw new AppError(503, 'server_misconfigured', 'Server belum dikonfigurasi dengan benar.');
  const m = BEARER.exec(req.headers.authorization || '');
  if (!m) throw unauthorized();
  let claims;
  try {
    claims = jwt.verify(m[1], config.jwtSecret, {
      algorithms: ['HS256'],
      issuer: config.jwtIssuer,
      audience: config.jwtAudience,
    });
  } catch {
    throw unauthorized();
  }
  if (!/^\d{1,18}$/.test(String(claims.sub))) throw unauthorized();
  const { rows } = await query(
    'SELECT id, username, display_name, role, active, token_version FROM users WHERE id = $1',
    [claims.sub],
  );
  const u = rows[0];
  if (!u || !u.active || u.token_version !== claims.tv) throw unauthorized();
  req.user = { id: u.id, username: u.username, displayName: u.display_name, role: u.role };
  next();
});

export const requireRole = (...roles) => (req, res, next) =>
  roles.includes(req.user?.role) ? next() : next(forbidden('Hanya Pemilik yang boleh melakukan aksi ini.'));

export const requireOwner = requireRole('Pemilik');
