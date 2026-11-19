-- 001_init.sql - identitas, katalog, transaksi, stok, audit
-- Idempoten: aman dijalankan berulang.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id            BIGSERIAL PRIMARY KEY,
  username      TEXT        NOT NULL UNIQUE,
  display_name  TEXT        NOT NULL,
  role          TEXT        NOT NULL CHECK (role IN ('Pemilik','Kasir')),
  password_hash TEXT        NOT NULL,
  active        BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS categories (
  id         TEXT PRIMARY KEY,
  payload    JSONB       NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted    BOOLEAN     NOT NULL DEFAULT FALSE,
  device_id  TEXT
);

CREATE TABLE IF NOT EXISTS products (
  id          TEXT PRIMARY KEY,
  name        TEXT        NOT NULL CHECK (char_length(name) <= 120),
  category_id TEXT,
  price       INTEGER     NOT NULL CHECK (price >= 0),
  stock       INTEGER     CHECK (stock IS NULL OR stock >= 0),
  available   BOOLEAN     NOT NULL DEFAULT TRUE,
  description TEXT,
  emoji       TEXT,
  payload     JSONB       NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted     BOOLEAN     NOT NULL DEFAULT FALSE,
  device_id   TEXT
);

CREATE TABLE IF NOT EXISTS settings (
  id         TEXT PRIMARY KEY DEFAULT 'main' CHECK (id = 'main'),
  payload    JSONB       NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted    BOOLEAN     NOT NULL DEFAULT FALSE,
  device_id  TEXT
);

CREATE TABLE IF NOT EXISTS transactions (
  id            TEXT PRIMARY KEY,
  client_txn_id UUID          NOT NULL UNIQUE,
  created_at    TIMESTAMPTZ   NOT NULL,
  order_date    DATE          NOT NULL,
  order_type    TEXT,
  table_number  TEXT,
  subtotal      INTEGER       NOT NULL CHECK (subtotal >= 0),
  discount      INTEGER       NOT NULL DEFAULT 0 CHECK (discount >= 0),
  tax_rate      NUMERIC(5,2)  NOT NULL DEFAULT 0 CHECK (tax_rate >= 0 AND tax_rate <= 100),
  total         INTEGER       NOT NULL CHECK (total >= 0),
  payment       TEXT          NOT NULL CHECK (payment IN ('cash','qris','transfer','card')),
  paid_amount   INTEGER       NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),
  change_amount INTEGER       NOT NULL DEFAULT 0 CHECK (change_amount >= 0),
  status        TEXT          NOT NULL DEFAULT 'paid',
  cashier       TEXT,
  note          TEXT,
  device_id     TEXT,
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
  deleted       BOOLEAN       NOT NULL DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_txn_created ON transactions (created_at);
CREATE INDEX IF NOT EXISTS idx_txn_date    ON transactions (order_date);
CREATE INDEX IF NOT EXISTS idx_txn_updated ON transactions (updated_at, id);

CREATE TABLE IF NOT EXISTS transaction_items (
  id             BIGSERIAL PRIMARY KEY,
  transaction_id TEXT    NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  product_id     TEXT,
  name           TEXT    NOT NULL,
  price          INTEGER NOT NULL CHECK (price >= 0),
  qty            INTEGER NOT NULL CHECK (qty > 0),
  total          INTEGER NOT NULL CHECK (total >= 0),
  note           TEXT
);
CREATE INDEX IF NOT EXISTS idx_items_txn ON transaction_items (transaction_id);

CREATE TABLE IF NOT EXISTS pending_orders (
  id         TEXT PRIMARY KEY,
  payload    JSONB       NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted    BOOLEAN     NOT NULL DEFAULT FALSE,
  device_id  TEXT
);

CREATE TABLE IF NOT EXISTS online_orders (
  id         TEXT PRIMARY KEY,
  payload    JSONB       NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted    BOOLEAN     NOT NULL DEFAULT FALSE,
  device_id  TEXT
);

CREATE TABLE IF NOT EXISTS stock_movements (
  id         BIGSERIAL PRIMARY KEY,
  product_id TEXT        NOT NULL,
  qty        INTEGER     NOT NULL,
  reason     TEXT        NOT NULL CHECK (reason IN ('sale','restock','adjust','reconcile')),
  ref        TEXT,
  device_id  TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_stock_mov_product ON stock_movements (product_id, created_at DESC);

CREATE TABLE IF NOT EXISTS audit_log (
  id         BIGSERIAL PRIMARY KEY,
  actor      TEXT,
  action     TEXT        NOT NULL,
  target     TEXT,
  detail     JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log (created_at DESC);

-- Index keyset untuk pull sinkronisasi (updated_at, id)
CREATE INDEX IF NOT EXISTS idx_products_sync   ON products       (updated_at, id);
CREATE INDEX IF NOT EXISTS idx_categories_sync ON categories     (updated_at, id);
CREATE INDEX IF NOT EXISTS idx_settings_sync   ON settings       (updated_at, id);
CREATE INDEX IF NOT EXISTS idx_pending_sync    ON pending_orders (updated_at, id);
CREATE INDEX IF NOT EXISTS idx_online_sync     ON online_orders  (updated_at, id);
