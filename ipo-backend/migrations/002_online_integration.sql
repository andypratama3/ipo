-- 002_online_integration.sql - GoFood: peta menu, log webhook, antrean aksi
CREATE TABLE IF NOT EXISTS online_menu_map (
  id                TEXT PRIMARY KEY,
  source            TEXT        NOT NULL CHECK (source IN ('gofood','grab','shopee')),
  partner_menu_id   TEXT        NOT NULL,
  partner_menu_name TEXT,
  product_id        TEXT        REFERENCES products(id) ON DELETE SET NULL,
  auto_matched      BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_menu_map_source_menu ON online_menu_map (source, partner_menu_id);
CREATE INDEX        IF NOT EXISTS idx_menu_map_product    ON online_menu_map (product_id);

CREATE TABLE IF NOT EXISTS webhook_events (
  id              BIGSERIAL PRIMARY KEY,
  source          TEXT        NOT NULL,
  event_type      TEXT,
  entity_id       TEXT,
  idempotency_key TEXT,
  signature_ok    BOOLEAN     NOT NULL DEFAULT FALSE,
  status          TEXT        NOT NULL CHECK (status IN ('accepted','duplicate','ignored','rejected','error')),
  note            TEXT,
  raw             JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX        IF NOT EXISTS idx_webhook_created     ON webhook_events (source, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_webhook_idempotency  ON webhook_events (source, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS online_order_actions (
  id               BIGSERIAL PRIMARY KEY,
  source           TEXT        NOT NULL,
  order_id         TEXT        NOT NULL,
  partner_order_id TEXT,
  order_type       TEXT        CHECK (order_type IS NULL OR order_type IN ('delivery','pickup')),
  action           TEXT        NOT NULL CHECK (action IN ('accept','reject','ready','cancel-review')),
  status           TEXT        NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sent','failed','manual','ignored')),
  attempts         INTEGER     NOT NULL DEFAULT 0,
  reason_code      TEXT,
  reason_text      TEXT,
  error            TEXT,
  payload          JSONB,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_online_actions_queue ON online_order_actions (status, created_at);
CREATE INDEX IF NOT EXISTS idx_online_actions_order ON online_order_actions (order_id);
