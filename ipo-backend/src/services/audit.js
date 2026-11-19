/** Catat audit memakai klien transaksi (atau pool). Tidak boleh memuat sandi/token. */
export async function audit(db, actor, action, target = null, detail = null) {
  await db.query('INSERT INTO audit_log (actor, action, target, detail) VALUES ($1,$2,$3,$4)', [
    actor || 'sistem', action, target, detail ? JSON.stringify(detail) : null,
  ]);
}
