-- 003_security_hardening.sql - tambahan keamanan & operasional serverless (aditif, idempoten)

-- Pembatalan token: naik setiap ganti sandi / nonaktif / ganti peran
ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0;

-- Rate limit berbasis DB (in-memory tidak andal di serverless karena banyak instance)
CREATE TABLE IF NOT EXISTS rate_limits (
  key      TEXT PRIMARY KEY,
  count    INTEGER     NOT NULL,
  reset_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rate_limits_reset ON rate_limits (reset_at);

-- Lease pengiriman aksi ke mitra: mencegah kirim ganda saat cron & retry manual bersamaan
ALTER TABLE online_order_actions ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;

-- Satu aksi aktif per (order, aksi): mencegah antrean ganda
CREATE UNIQUE INDEX IF NOT EXISTS uq_online_actions_active
  ON online_order_actions (order_id, action)
  WHERE status IN ('queued','sent','failed');
