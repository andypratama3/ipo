// Jalankan: npm run seed
// Wajib set SEED_OWNER_PASSWORD (dan opsional SEED_CASHIER_PASSWORD) minimal 10 karakter. Tidak ada sandi bawaan.
import bcrypt from 'bcryptjs';
import { pathToFileURL } from 'node:url';
import { config } from '../src/config.js';
import { getPool, closePool } from '../src/db.js';
import { passwordSchema, usernameSchema } from '../src/lib/schemas.js';

async function upsertUser(db, { username, display, role, password }) {
  const u = usernameSchema.parse(username);
  if (password.length < 10) throw new Error(`Sandi ${role} minimal 10 karakter.`);
  passwordSchema.parse(password);
  const hash = await bcrypt.hash(password, 12);
  const r = await db.query(
    `INSERT INTO users (username, display_name, role, password_hash) VALUES ($1,$2,$3,$4)
     ON CONFLICT (username) DO NOTHING RETURNING id`, [u, display, role, hash]);
  if (r.rows[0]) return `+ akun ${role} "${u}" dibuat`;
  if (process.env.SEED_RESET === '1') {
    await db.query('UPDATE users SET password_hash=$2, role=$3, active=true, token_version=token_version+1, updated_at=now() WHERE username=$1', [u, hash, role]);
    return `~ akun ${role} "${u}" di-reset (SEED_RESET=1)`;
  }
  return `- akun "${u}" sudah ada (tidak diubah; pakai SEED_RESET=1 untuk reset sandi)`;
}

export async function seed(env = process.env, log = console.log) {
  const db = getPool();
  const ownerPw = env.SEED_OWNER_PASSWORD || '';
  if (!ownerPw) throw new Error('SEED_OWNER_PASSWORD wajib diisi (tidak ada sandi bawaan).');
  log(await upsertUser(db, { username: env.SEED_OWNER_USERNAME || 'pemilik', display: 'Pemilik', role: 'Pemilik', password: ownerPw }));
  if (env.SEED_CASHIER_PASSWORD) {
    log(await upsertUser(db, { username: env.SEED_CASHIER_USERNAME || 'kasir', display: 'Kasir', role: 'Kasir', password: env.SEED_CASHIER_PASSWORD }));
  } else log('- SEED_CASHIER_PASSWORD kosong: akun kasir dilewati');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!config.dbConfigured) { console.error('DATABASE_URL belum diisi / masih placeholder.'); process.exit(1); }
  seed().catch((e) => { console.error(e.message); process.exitCode = 1; }).finally(closePool);
}
