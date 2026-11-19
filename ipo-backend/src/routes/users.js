import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { tx, query } from '../db.js';
import { ah, conflict, notFound, badRequest } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { userCreateSchema, userUpdateSchema } from '../lib/schemas.js';
import { requireAuth, requireOwner } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

const r = Router();
r.use(requireAuth, requireOwner);

const out = (u) => ({ id: u.id, username: u.username, displayName: u.display_name, role: u.role, active: u.active, createdAt: u.created_at, updatedAt: u.updated_at });

r.get('/', ah(async (req, res) => {
  const { rows } = await query('SELECT id, username, display_name, role, active, created_at, updated_at FROM users ORDER BY id');
  res.json({ users: rows.map(out) });
}));

r.post('/', ah(async (req, res) => {
  const d = parse(userCreateSchema, req.body, 'Pengguna');
  const hash = await bcrypt.hash(d.password, 12);
  try {
    const { rows } = await query(
      'INSERT INTO users (username, display_name, role, password_hash) VALUES ($1,$2,$3,$4) RETURNING id, username, display_name, role, active, created_at, updated_at',
      [d.username, d.displayName, d.role, hash]);
    await audit({ query }, req.user.username, 'user.created', String(rows[0].id), { role: d.role });
    res.status(201).json({ user: out(rows[0]) });
  } catch (e) {
    if (e.code === '23505') throw conflict('Username sudah dipakai.', 'username_taken');
    throw e;
  }
}));

r.put('/:id', ah(async (req, res) => {
  if (!/^\d{1,18}$/.test(req.params.id)) throw badRequest('ID tidak valid.');
  const d = parse(userUpdateSchema, req.body, 'Pengguna');
  const hash = d.password ? await bcrypt.hash(d.password, 12) : null;

  const user = await tx(async (db) => {
    // Kunci semua pemilik aktif agar pemeriksaan "pemilik terakhir" aman dari balapan.
    const owners = (await db.query(`SELECT id FROM users WHERE role='Pemilik' AND active=true ORDER BY id FOR UPDATE`)).rows;
    const cur = (await db.query('SELECT * FROM users WHERE id=$1 FOR UPDATE', [req.params.id])).rows[0];
    if (!cur) throw notFound('Pengguna tidak ditemukan.');
    const nextRole = d.role ?? cur.role;
    const nextActive = d.active ?? cur.active;
    const wasActiveOwner = cur.role === 'Pemilik' && cur.active;
    const staysActiveOwner = nextRole === 'Pemilik' && nextActive;
    if (wasActiveOwner && !staysActiveOwner && owners.length <= 1) {
      throw conflict('Harus ada minimal satu akun Pemilik aktif.', 'last_owner');
    }
    const bump = d.password || nextRole !== cur.role || nextActive !== cur.active; // cabut token lama
    const up = await db.query(
      `UPDATE users SET display_name=$2, role=$3, active=$4, password_hash=COALESCE($5, password_hash),
         token_version = token_version + $6, updated_at=now() WHERE id=$1
       RETURNING id, username, display_name, role, active, created_at, updated_at`,
      [cur.id, d.displayName ?? cur.display_name, nextRole, nextActive, hash, bump ? 1 : 0]);
    await audit(db, req.user.username, 'user.updated', String(cur.id), { fields: Object.keys(d).filter((k) => k !== 'password'), passwordReset: Boolean(d.password) });
    return up.rows[0];
  });
  res.json({ user: out(user) });
}));

export default r;
