import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { config } from '../config.js';
import { query } from '../db.js';
import { ah, unauthorized, badRequest } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { loginSchema, changePasswordSchema } from '../lib/schemas.js';
import { enforce, resetKey } from '../lib/ratelimit.js';
import { requireAuth, requireConfig, signToken } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

const r = Router();
// Hash palsu: user tidak ada & user ada memakan waktu bcrypt yang sama (anti user-enumeration timing).
const DUMMY_HASH = bcrypt.hashSync('dummy-password-for-timing', 12);
const WINDOW = 15 * 60;

const publicUser = (u) => ({ id: u.id, username: u.username, displayName: u.display_name ?? u.displayName, role: u.role });

r.post('/login', requireConfig, ah(async (req, res) => {
  const { username, password } = parse(loginSchema, req.body, 'Login');
  const ip = req.ip || 'unknown';
  await enforce(`login:ip:${ip}`, config.loginRateLimit, WINDOW, 'Terlalu banyak percobaan login. Coba lagi nanti.');
  const iuKey = `login:iu:${ip}:${username}`;
  await enforce(iuKey, 8, WINDOW, 'Terlalu banyak percobaan login untuk akun ini. Coba lagi nanti.');

  const { rows } = await query('SELECT * FROM users WHERE username = $1', [username]);
  const u = rows[0];
  const ok = await bcrypt.compare(password, u ? u.password_hash : DUMMY_HASH);
  if (!u || !ok || !u.active) {
    await audit({ query }, username.slice(0, 32), 'auth.login_failed', null, { ip });
    throw unauthorized('Username atau sandi salah.');
  }
  await resetKey(iuKey);
  await audit({ query }, u.username, 'auth.login', String(u.id), null);
  res.json({ ...signToken(u), user: publicUser(u) });
}));

r.get('/me', requireAuth, (req, res) => res.json({ user: publicUser(req.user) }));

r.post('/change-password', requireAuth, ah(async (req, res) => {
  const { currentPassword, newPassword } = parse(changePasswordSchema, req.body, 'Ganti sandi');
  await enforce(`pw:${req.user.id}`, 10, WINDOW, 'Terlalu banyak percobaan. Coba lagi nanti.');
  const { rows } = await query('SELECT * FROM users WHERE id = $1', [req.user.id]);
  const u = rows[0];
  if (!(await bcrypt.compare(currentPassword, u.password_hash))) throw unauthorized('Sandi saat ini salah.');
  if (currentPassword === newPassword) throw badRequest('Sandi baru harus berbeda.');
  const hash = await bcrypt.hash(newPassword, 12);
  const up = await query(
    'UPDATE users SET password_hash=$2, token_version = token_version + 1, updated_at = now() WHERE id=$1 RETURNING *',
    [u.id, hash]);
  await audit({ query }, u.username, 'auth.password_changed', String(u.id), null);
  res.json({ ...signToken(up.rows[0]), user: publicUser(up.rows[0]) }); // token lama otomatis mati
}));

export default r;
