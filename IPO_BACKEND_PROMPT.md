# iPo Mie Pangsit — Backend Lengkap (Express + PostgreSQL/Neon, siap Vercel)

Dokumen ini **satu file berisi semuanya**: panduan, hasil cross-check keamanan, dan **seluruh kode** (setiap file ada di bagian "KODE LENGKAP" di bawah, diawali `### FILE: <path>`). Disusun dari PRD v1.0 (19 Nov 2026).

## 1. Status & bukti uji

| Pemeriksaan | Hasil |
|---|---|
| Tes otomatis (`npm run selftest`) | **19/19 lolos** (7 unit + 12 integrasi ke PostgreSQL 16 sungguhan) |
| `npm audit --omit=dev` | **0 kerentanan** (zod di-upgrade ke v4 karena advisory GHSA-mrhx-c7xc-m3w5) |
| Boot tanpa DB / tanpa JWT_SECRET | Proses hidup, `/api/health` = 200 `db:"unconfigured"`, login = 503 (tidak crash) |
| Uji balik dokumen ini | md ini diekstrak ke folder kosong → `npm install` → semua tes lolos |

**Belum bisa saya buktikan (jujur):** deploy ke Vercel sungguhan dan panggilan ke GoBiz sandbox (saya tidak punya akun/kredensial Anda). Lihat bagian 7.

## 2. Struktur proyek

```
ipo-backend/
├─ package.json  vercel.json  .env.example  .gitignore  .vercelignore
├─ migrations/   001_init.sql  002_online_integration.sql  003_security_hardening.sql
├─ scripts/      migrate.js  seed.js  check-env.js  mock-gofood-order.js
├─ src/
│  ├─ index.js            (entry Express; default export untuk Vercel)
│  ├─ config.js  db.js
│  ├─ lib/                errors  crypto  qris  ratelimit  validate  schemas  background
│  ├─ middleware/         auth  security  error
│  ├─ services/           audit  orders  sync  online  gofood
│  └─ routes/             health  auth  users  sync  orders  webhooks  online  cron
└─ tests/        unit.test.js  integration.test.js
```

## 3. Cara pakai (urut)

**A. Siapkan database Neon** — buat project, salin connection string **pooled** (host berisi `-pooler`, `sslmode=require`). Pilih region Singapore (`ap-southeast-1`) agar dekat dengan fungsi Vercel `sin1`.

**B. Lokal (sekali, dari komputer Anda)**
```bash
npm install
cp .env.example .env          # isi DATABASE_URL, JWT_SECRET, SEED_OWNER_PASSWORD (>=10 karakter), dst.
npm run check                 # cek konfigurasi (tidak mencetak rahasia)
npm run migrate               # buat 14 tabel
npm run seed                  # buat akun pemilik (+ kasir bila SEED_CASHIER_PASSWORD diisi)
TEST_DATABASE_URL="postgresql://..." npm run selftest   # pakai DB KOSONG/uji, bukan produksi! (tes melakukan TRUNCATE)
npm run dev
```
Buat JWT_SECRET: `node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"`

**C. Deploy ke Vercel**
1. Push folder ke GitHub → Vercel → *Add New Project* → import. Framework terdeteksi otomatis sebagai Express (tanpa build command).
2. *Settings → Environment Variables* (Production): `DATABASE_URL`, `JWT_SECRET`, `CORS_ORIGINS`, `CRON_SECRET` (≥16 karakter), `JWT_TTL_HOURS`, lalu variabel `GOFOOD_*` bila sudah ada. **Jangan** pasang `SEED_*` di Vercel.
3. Deploy. Cek `https://<proyek>.vercel.app/api/health` → `{"ok":true,"db":"up"}`.
4. Di aplikasi kasir, isi alamat server: `https://<proyek>.vercel.app` (Pengaturan → Server & cadangan).
5. GoFood (setelah kredensial ada): isi `GOFOOD_*` + `GOFOOD_WEBHOOK_URL=https://<proyek>.vercel.app/api/webhooks/gofood`, redeploy, lalu (sebagai Pemilik) `POST /api/online/gofood/cek` dan `POST /api/online/gofood/langganan`.

`CORS_ORIGINS` untuk APK Capacitor biasanya `https://localhost,capacitor://localhost` ditambah domain PWA Anda.

## 4. Endpoint

| Endpoint | Akses | Fungsi |
|---|---|---|
| `GET /api/health` | publik | status proses & DB (tanpa detail konfigurasi) |
| `POST /api/auth/login` · `GET /api/auth/me` · `POST /api/auth/change-password` | publik / login | JWT HS256, ganti sandi mencabut token lama |
| `GET/POST /api/users` · `PUT /api/users/:id` | Pemilik | kelola akun; pemilik aktif terakhir dilindungi |
| `GET /api/sync/tables` · `POST /api/sync/push` · `GET /api/sync/pull` | login | sinkronisasi (daftar putih tabel, maks 1000 baris, kursor `(updated_at,id)`) |
| `POST /api/orders` · `DELETE /api/orders/:id` | login / Pemilik | transaksi (harga dihitung ulang server, idempoten), soft delete tanpa pengembalian stok |
| `POST /api/webhooks/gofood` | tanda tangan HMAC | terima event GoFood |
| `/api/online/{config,orders,menu-map,actions,webhooks,gofood/cek,gofood/langganan}` | login/Pemilik | operasional pesanan online |
| `GET /api/cron/maintenance` | `CRON_SECRET` | kirim ulang antrean aksi + bersih-bersih data lama |

Kontrak sinkronisasi: `POST /api/sync/push` body `{ "table": "products", "rows": [{ "id": "...", "payload": {...}, "deleted": false }], "deviceId": "..." }`. Tombstone cukup `{ "id": "...", "deleted": true }`. Pull: `GET /api/sync/pull?table=products&since=<ISO>&sinceId=<id>` → `{ rows:[{id,payload,deleted,updatedAt}], cursor:{since,sinceId}, hasMore }`; simpan `cursor` untuk panggilan berikutnya.

## 5. Cross-check keamanan (semua poin diuji di `tests/`)

| Risiko | Kontrol di kode | Diuji |
|---|---|---|
| Token palsu / `alg:none` | `jwt.verify` dipaksa `HS256`, cek `iss`/`aud`/`exp` | ✅ |
| Token tetap hidup setelah akun dinonaktifkan / ganti sandi | tiap request cek user di DB + `token_version` | ✅ |
| Brute force login | batas per-IP (`LOGIN_RATE_LIMIT`) + per-IP+username (8/15 mnt), **disimpan di DB** (aman di serverless) | ✅ |
| User enumeration | pesan sama + bcrypt dummy agar waktu seragam | ✅ (logika) |
| Sandi lemah | min 8, maks 72 byte (batas bcrypt), tolak pola umum; seed menolak sandi <10 & tanpa sandi bawaan | ✅ |
| SQL injection | semua query berparameter; nama tabel hanya dari `Map` statis | ✅ (`__proto__`, `';DROP`) |
| Eskalasi peran | `requireOwner`; kasir ditolak push katalog/users/hapus transaksi | ✅ |
| Manipulasi harga dari klien | server hitung ulang dari `products`; diskon dibatasi; kembalian ≥ 0 | ✅ |
| Transaksi ganda / balapan | `id` + `client_txn_id` unik, transaksi DB, kunci baris `FOR UPDATE`, tangani 23505 | ✅ (5 request paralel → 1 baris) |
| Stok negatif | minimum 0 + audit `stock.conflict` | ✅ |
| Webhook palsu | HMAC-SHA256 dari **byte mentah**, `timingSafeEqual`; secret kosong = tolak semua; isi body penyerang tidak disimpan | ✅ |
| Webhook ganda / hilang | kunci idempotensi diklaim **dalam transaksi yang sama** dengan pemrosesan (gagal → rollback → mitra kirim ulang) | ✅ |
| Webhook sumber tak terverifikasi | `grab`/`shopee` → 404 (tidak menerima payload tanpa autentikasi) | ✅ |
| Event outlet lain | dibandingkan dengan `GOFOOD_OUTLET_ID` → `ignored` | ✅ |
| Pesanan online ditutup hidup lagi | webhook & push tidak menghidupkan baris `deleted` | ✅ |
| Aksi mitra terkirim ganda | unique index aksi aktif + lease `locked_until` | ✅ |
| Kebocoran rahasia | `/online/config` hanya boolean; log tanpa body/token/stack; `raw` webhook tidak dikembalikan API | ✅ |
| Header & CORS | Helmet (CSP `default-src 'none'`, HSTS), `no-store`, tanpa `x-powered-by`, CORS whitelist | ✅ |
| Payload besar / JSON rusak / tipe konten | batas 2 MB (webhook 256 KB), 413/400/415 | ✅ |
| Mass-assignment / JSONB sembarang | skema zod (`strip`), `settings` hanya primitif, payload ≤ 64 KB, QRIS dicek struktur+CRC | ✅ |
| Cron terbuka | wajib `Bearer CRON_SECRET` (≥16), dibandingkan waktu konstan | ✅ |
| Dependensi rentan | `npm audit` bersih | ✅ |

## 6. Kesesuaian dengan PRD & penyimpangan yang disengaja

- **JWT_TTL_HOURS default 24** (PRD: 720). Alasan: sesi klien sudah berakhir saat ganti hari; 30 hari terlalu lama bila HP hilang. Set `720` jika ingin sama seperti PRD.
- **Migrasi 003 (aditif)**: kolom `users.token_version`, `online_order_actions.locked_until`, tabel `rate_limits` (tabel ke-14), indeks unik aksi aktif. Diperlukan untuk serverless (in-memory tidak berbagi state antar instance).
- Duplikat webhook: event pertama `accepted`; event ulang dicatat sebagai baris baru berstatus `duplicate` (kunci idempotensi dikosongkan di baris itu karena indeks unik).
- Tombstone untuk id yang belum ada **tidak** membuat baris baru (hanya `UPDATE`).
- `online:cancelled` dari mitra: jika pesanan masih `baru` → ditutup; jika sudah diterima → ditandai + aksi `cancel-review` (status `manual`) agar ditinjau manusia, tidak dibatalkan diam-diam.
- Pesanan online **tidak pernah** diselesaikan otomatis oleh webhook (supaya transaksi/omzet tidak hilang); status dari webhook tidak pernah mundur.

## 7. Batasan & hal yang perlu Anda verifikasi

1. **Vercel belum diuji langsung.** Pola yang dipakai mengikuti dokumentasi Vercel (Express zero-config: `import express` + `export default app` di `src/index.js`). Uji nyata saya: Express + PostgreSQL 16 lokal.
2. **GoBiz**: path `PUT .../orders/{delivery|pickup}/{id}/accepted`, `/cancelled` (body `cancel_reason_code`, `cancel_reason_description`), `/food-prepared`, dan `POST /integrations/partner/outlets/{outlet_id}/v1/notification-subscriptions` saya ambil dari dokumentasi developer.gobiz.com. Yang **belum terkonfirmasi** di dokumentasi: encoding `X-Go-Signature` (kode menerima hex atau base64) dan nama header `X-Go-Idempotency-Key` (jika tidak ada, dipakai `header.event_id`). Endpoint "linked outlets" tidak saya implementasikan; `gofood/cek` memakai daftar langganan. Uji di sandbox dengan `scripts/mock-gofood-order.js` dan kredensial asli sebelum produksi.
3. **Kontrak klien**: saya tidak memiliki `www/js/pos.js`. Bentuk baris sinkronisasi saya turunkan dari PRD §6; cocokkan dengan klien Anda (terutama `payload.category` produk dan format `since`/`cursor`).
4. **Stok & push produk**: push katalog oleh Pemilik bersifat *last-write-wins* termasuk kolom `stock`. Bila perangkat Pemilik menyimpan stok usang lalu push, ia menimpa pengurangan stok dari penjualan. Disarankan klien hanya mengirim produk yang benar-benar diedit.
5. **Cron di paket Hobby** hanya boleh 1×/hari (`vercel.json` sudah `0 3 * * *`). Di Pro boleh `*/5 * * * *`. Antrean aksi juga dicoba otomatis setelah push status dari kasir (`waitUntil`).
6. Sandi default `1234` **tidak ada** di server; seed mewajibkan sandi yang Anda tentukan.
7. Soal "skill fullstack" dan model DeepSeek/OMP di komputer Anda: saya tidak punya akses ke lingkungan lokal Anda, dan katalog skill di sini tidak memuat skill backend. Dokumen ini sengaja *self-contained* sehingga bisa langsung diberikan ke agen mana pun (lihat bagian 8).

## 8. Memakai dokumen ini di OMP / DeepSeek

Berikan file ini ke agen dengan instruksi:

> Ekstrak setiap blok di bagian "KODE LENGKAP" menjadi file dengan path persis seperti judul `### FILE: <path>` (isi blok apa adanya, jangan diubah). Lalu jalankan `npm install` dan `npm run selftest` dengan `TEST_DATABASE_URL` ke database uji kosong. Laporkan hasilnya.

---

# KODE LENGKAP


### FILE: package.json

`````json
{
  "name": "ipo-pos-backend",
  "version": "1.0.0",
  "description": "Backend iPo Mie Pangsit (POS Kasir + integrasi GoFood) - Express + PostgreSQL (Neon), siap deploy di Vercel",
  "private": true,
  "type": "module",
  "main": "src/index.js",
  "engines": {
    "node": ">=20"
  },
  "scripts": {
    "start": "node src/index.js",
    "dev": "node --watch src/index.js",
    "migrate": "node scripts/migrate.js",
    "seed": "node scripts/seed.js",
    "check": "node scripts/check-env.js",
    "selftest": "node --test",
    "mock:gofood": "node scripts/mock-gofood-order.js"
  },
  "dependencies": {
    "@vercel/functions": "^2.0.0",
    "bcryptjs": "^2.4.3",
    "cors": "^2.8.5",
    "dotenv": "^16.4.7",
    "express": "^4.21.2",
    "express-rate-limit": "^7.5.0",
    "helmet": "^8.0.0",
    "jsonwebtoken": "^9.0.2",
    "pg": "^8.13.1",
    "zod": "^4.6.7"
  }
}
`````

### FILE: vercel.json

`````json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "regions": ["sin1"],
  "crons": [{ "path": "/api/cron/maintenance", "schedule": "0 3 * * *" }]
}
`````

### FILE: .env.example

`````bash
# ===== WAJIB =====
# Neon: pakai connection string "pooled" (host mengandung -pooler), sslmode=require
DATABASE_URL=postgresql://USER:PASSWORD@ep-xxxx-pooler.ap-southeast-1.aws.neon.tech/neondb?sslmode=require
# Acak panjang >= 32 karakter. Buat: node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
JWT_SECRET=
# Origin aplikasi (pisahkan koma). Untuk APK Capacitor biasanya https://localhost dan capacitor://localhost
CORS_ORIGINS=https://pos.domainanda.com,https://localhost,capacitor://localhost

# ===== DIREKOMENDASIKAN =====
JWT_TTL_HOURS=24
LOGIN_RATE_LIMIT=20
# Minimal 16 karakter. Vercel Cron otomatis mengirimnya sebagai Authorization: Bearer <nilai ini>
CRON_SECRET=
WEBHOOK_RETENTION_DAYS=90
# Vercel mengisi 1 otomatis; lokal biarkan 0
TRUST_PROXY=

# ===== SEED (hanya dipakai `npm run seed`, jangan dipasang di Vercel) =====
SEED_OWNER_USERNAME=pemilik
SEED_OWNER_PASSWORD=
SEED_CASHIER_USERNAME=kasir
SEED_CASHIER_PASSWORD=

# ===== GOFOOD (isi setelah Partner Integration disetujui) =====
GOFOOD_AUTH_URL=https://integration-goauth.gojekapi.com/oauth2/token
GOFOOD_API_BASE=https://api.partner-sandbox.gobiz.co.id
GOFOOD_CLIENT_ID=
GOFOOD_CLIENT_SECRET=
GOFOOD_OUTLET_ID=
GOFOOD_NOTIFICATION_SECRET=
GOFOOD_WEBHOOK_URL=https://API-ANDA.vercel.app/api/webhooks/gofood
GOFOOD_AUTO_ACCEPT=0
GOFOOD_REJECT_REASON_CODE=OTHERS
`````

### FILE: .gitignore

`````
node_modules
.env
.env.*
!.env.example
.vercel
*.log
`````

### FILE: .vercelignore

`````
tests
scripts/mock-gofood-order.js
.env
.env.*
`````

### FILE: migrations/001_init.sql

`````sql
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
`````

### FILE: migrations/002_online_integration.sql

`````sql
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
`````

### FILE: migrations/003_security_hardening.sql

`````sql
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
`````

### FILE: src/index.js

`````js
// Entry point. Vercel mendeteksi Express dari `import express` + default export `app`.
import express from 'express';
import { pathToFileURL } from 'node:url';
import { config, configProblems } from './config.js';
import { securityHeaders, corsMiddleware, noStore, globalLimiter, requestLog, requireJson } from './middleware/security.js';
import { notFoundHandler, errorHandler } from './middleware/error.js';
import { webhookHandler } from './routes/webhooks.js';
import healthRoutes from './routes/health.js';
import authRoutes from './routes/auth.js';
import userRoutes from './routes/users.js';
import syncRoutes from './routes/sync.js';
import orderRoutes from './routes/orders.js';
import onlineRoutes from './routes/online.js';
import cronRoutes from './routes/cron.js';

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', config.trustProxy); // Vercel: 1 (IP klien dari X-Forwarded-For)
app.set('etag', false);

app.use(securityHeaders);
app.use(corsMiddleware);
app.use(requestLog);
app.use('/api', noStore);

// Webhook SEBELUM parser JSON: butuh byte mentah untuk HMAC.
app.post('/api/webhooks/:source', express.raw({ type: () => true, limit: '256kb' }), webhookHandler);

app.use('/api', globalLimiter);
app.use('/api', requireJson);
app.use(express.json({ limit: '2mb', strict: true }));

app.use('/api/health', healthRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/sync', syncRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/online', onlineRoutes);
app.use('/api/cron', cronRoutes);

app.get('/', (req, res) => res.json({ name: 'iPo Mie Pangsit API', ok: true }));
app.use(notFoundHandler);
app.use(errorHandler);

const problems = configProblems();
if (problems.length) console.warn(JSON.stringify({ level: 'warn', msg: 'config', problems }));

// Jalankan listener hanya bila file ini dieksekusi langsung (npm start / dev); di Vercel cukup default export.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  app.listen(config.port, () => console.log(`iPo API listening on :${config.port}`));
}

export default app;
`````

### FILE: src/config.js

`````js
import 'dotenv/config';

const env = process.env;

const bool = (v, d = false) =>
  v == null || v === '' ? d : ['1', 'true', 'yes', 'on'].includes(String(v).toLowerCase());
const int = (v, d, min = -Infinity, max = Infinity) => {
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : d;
};
const list = (v) => String(v || '').split(',').map((s) => s.trim()).filter(Boolean);

const isProd = env.NODE_ENV === 'production' || env.VERCEL_ENV === 'production';
const onVercel = Boolean(env.VERCEL);

const databaseUrl = (env.DATABASE_URL || '').trim();
const PLACEHOLDER_DB = /ipos_placeholder|contoh:contoh|user:password@host|your-db|example\.com/i;

const jwtSecret = env.JWT_SECRET || '';
const WEAK_SECRET = /(change[-_ ]?me|placeholder|contoh|example|secret123|password)/i;

const REJECT_CODES = ['HIGH_DEMAND', 'RESTAURANT_CLOSED', 'ITEMS_OUT_OF_STOCK', 'OTHERS'];
const rejectCode = (env.GOFOOD_REJECT_REASON_CODE || 'OTHERS').toUpperCase();

export const config = {
  isProd,
  onVercel,
  port: int(env.PORT, 8080, 1, 65535),

  databaseUrl,
  dbConfigured: databaseUrl !== '' && !PLACEHOLDER_DB.test(databaseUrl),
  dbLocal: /@(localhost|127\.0\.0\.1|\[::1\])(:|\/|$)/.test(databaseUrl),

  jwtSecret,
  jwtOk: jwtSecret.length >= 32 && !WEAK_SECRET.test(jwtSecret),
  jwtTtlHours: int(env.JWT_TTL_HOURS, 24, 1, 720),
  jwtIssuer: 'ipo-pos',
  jwtAudience: 'ipo-pos-app',

  corsOrigins: list(env.CORS_ORIGINS),
  trustProxy: int(env.TRUST_PROXY, onVercel ? 1 : 0, 0, 5),
  loginRateLimit: int(env.LOGIN_RATE_LIMIT, 20, 3, 1000),
  cronSecret: env.CRON_SECRET || '',
  webhookRetentionDays: int(env.WEBHOOK_RETENTION_DAYS, 90, 7, 3650),

  gofood: {
    authUrl: env.GOFOOD_AUTH_URL || 'https://integration-goauth.gojekapi.com/oauth2/token',
    apiBase: (env.GOFOOD_API_BASE || 'https://api.partner-sandbox.gobiz.co.id').replace(/\/+$/, ''),
    clientId: env.GOFOOD_CLIENT_ID || '',
    clientSecret: env.GOFOOD_CLIENT_SECRET || '',
    outletId: env.GOFOOD_OUTLET_ID || '',
    notificationSecret: env.GOFOOD_NOTIFICATION_SECRET || '',
    webhookUrl: env.GOFOOD_WEBHOOK_URL || '',
    autoAccept: bool(env.GOFOOD_AUTO_ACCEPT, false),
    rejectReasonCode: REJECT_CODES.includes(rejectCode) ? rejectCode : 'OTHERS',
    scope:
      env.GOFOOD_SCOPE ||
      'partner:outlet:read gofood:order:read gofood:order:write gofood:catalog:read gofood:catalog:write',
  },
};

config.gofood.apiReady = Boolean(
  config.gofood.clientId && config.gofood.clientSecret && config.gofood.outletId,
);

/** Daftar masalah konfigurasi (untuk log & `npm run check`; tidak pernah memuat nilai rahasia). */
export function configProblems() {
  const p = [];
  if (!config.dbConfigured) p.push('DATABASE_URL belum diisi / masih placeholder');
  if (!config.jwtOk) p.push('JWT_SECRET kosong, <32 karakter, atau memakai nilai contoh');
  if (config.isProd && config.corsOrigins.length === 0)
    p.push('CORS_ORIGINS kosong: hanya same-origin/non-browser yang bisa mengakses');
  if (config.isProd && !config.cronSecret) p.push('CRON_SECRET kosong: endpoint cron akan menolak semua panggilan');
  if (config.isProd && !config.gofood.notificationSecret)
    p.push('GOFOOD_NOTIFICATION_SECRET kosong: semua webhook GoFood akan ditolak');
  if (config.gofood.webhookUrl && !/^https:\/\//i.test(config.gofood.webhookUrl))
    p.push('GOFOOD_WEBHOOK_URL harus HTTPS');
  return p;
}
`````

### FILE: src/db.js

`````js
import pg from 'pg';
import { config } from './config.js';
import { AppError } from './lib/errors.js';

// DATE (oid 1082) tetap string 'YYYY-MM-DD' (tanpa konversi zona waktu), COUNT/int8 tetap string.
pg.types.setTypeParser(1082, (v) => v);

let pool = null;

export function getPool() {
  if (!config.dbConfigured) {
    throw new AppError(503, 'database_not_configured', 'Database belum dikonfigurasi di server.');
  }
  if (!pool) {
    pool = new pg.Pool({
      connectionString: config.databaseUrl,
      // Neon memakai sertifikat publik; selalu verifikasi kecuali DB lokal (dev).
      ssl: config.dbLocal ? false : { rejectUnauthorized: true },
      max: 5,
      idleTimeoutMillis: 10_000,
      connectionTimeoutMillis: 8_000,
      statement_timeout: 15_000,
      query_timeout: 20_000,
      allowExitOnIdle: true,
    });
    pool.on('error', (e) => console.error(JSON.stringify({ level: 'error', msg: 'pg pool', code: e.code })));
  }
  return pool;
}

export const query = (text, params) => getPool().query(text, params);

/** Jalankan fn dalam satu transaksi (BEGIN/COMMIT, ROLLBACK jika error). */
export async function tx(fn) {
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    const out = await fn(client);
    await client.query('COMMIT');
    return out;
  } catch (e) {
    try { await client.query('ROLLBACK'); } catch { /* koneksi sudah putus */ }
    throw e;
  } finally {
    client.release();
  }
}

export async function closePool() {
  if (pool) { await pool.end(); pool = null; }
}
`````

### FILE: src/lib/errors.js

`````js
export class AppError extends Error {
  constructor(status, code, message, extra) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

export const badRequest = (msg = 'Permintaan tidak valid.', code = 'bad_request', extra) =>
  new AppError(400, code, msg, extra);
export const unauthorized = (msg = 'Sesi tidak valid. Silakan login ulang.') =>
  new AppError(401, 'unauthorized', msg);
export const forbidden = (msg = 'Anda tidak punya izin untuk aksi ini.') =>
  new AppError(403, 'forbidden', msg);
export const notFound = (msg = 'Data tidak ditemukan.') => new AppError(404, 'not_found', msg);
export const conflict = (msg = 'Konflik data.', code = 'conflict') => new AppError(409, code, msg);

/** Bungkus handler async agar error masuk ke error middleware (Express 4 tidak menangkapnya sendiri). */
export const ah = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
`````

### FILE: src/lib/crypto.js

`````js
import crypto from 'node:crypto';

/** Bandingkan dua string dengan waktu konstan (panjang berbeda pun tidak bocor). */
export function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

export const sha256Hex = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

/**
 * Verifikasi X-Go-Signature = HMAC-SHA256(notification_secret, raw body).
 * Menerima hex atau base64 (dokumentasi GoBiz tidak menegaskan encoding).
 */
export function verifyGoSignature(rawBody, headerValue, secret) {
  if (!secret || !headerValue || !Buffer.isBuffer(rawBody)) return false;
  const mac = crypto.createHmac('sha256', secret).update(rawBody).digest();
  const given = String(headerValue).trim().replace(/^sha256=/i, '');
  const hex = mac.toString('hex');
  const b64 = mac.toString('base64');
  // Bandingkan keduanya tanpa short-circuit agar waktu tetap konstan.
  const okHex = safeEqual(given.toLowerCase(), hex);
  const okB64 = safeEqual(given, b64);
  return okHex || okB64;
}
`````

### FILE: src/lib/qris.js

`````js
/** CRC16-CCITT (poly 0x1021, init 0xFFFF) sesuai EMVCo/QRIS. */
export function crc16(str) {
  let crc = 0xffff;
  for (let i = 0; i < str.length; i++) {
    crc ^= str.charCodeAt(i) << 8;
    for (let j = 0; j < 8; j++) crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/** Validasi struktur TLV + CRC. String kosong dianggap "belum diatur" (valid). */
export function isValidQris(payload) {
  if (payload === '' || payload == null) return true;
  if (typeof payload !== 'string' || payload.length < 20 || payload.length > 1024) return false;
  if (!/^[\x20-\x7E]+$/.test(payload)) return false;
  if (!payload.startsWith('000201')) return false;
  if (payload.slice(-8, -4) !== '6304') return false;
  // Jalan melalui TLV: tag(2) len(2) value(len)
  let i = 0;
  while (i < payload.length) {
    if (i + 4 > payload.length) return false;
    const len = Number.parseInt(payload.slice(i + 2, i + 4), 10);
    if (!Number.isInteger(len) || len < 0) return false;
    i += 4 + len;
  }
  if (i !== payload.length) return false;
  return crc16(payload.slice(0, -4)) === payload.slice(-4).toUpperCase();
}
`````

### FILE: src/lib/ratelimit.js

`````js
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
`````

### FILE: src/lib/validate.js

`````js
import { badRequest } from './errors.js';

/** Parse dengan zod; kesalahan dikembalikan sebagai 400 tanpa mengulang nilai input. */
export function parse(schema, data, label = 'Data') {
  const r = schema.safeParse(data);
  if (r.success) return r.data;
  const issues = r.error.issues.slice(0, 10).map((i) => ({
    path: i.path.join('.') || '(root)',
    message: i.message,
  }));
  throw badRequest(`${label} tidak valid.`, 'validation_error', { issues });
}
`````

### FILE: src/lib/schemas.js

`````js
import { z } from 'zod';
import { isValidQris } from './qris.js';

export const ID_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/;
export const idStr = z.string().regex(ID_RE, 'ID tidak valid');
export const deviceIdSchema = z.string().regex(/^[A-Za-z0-9._:-]{1,64}$/, 'deviceId tidak valid').optional();

const str = (max) => z.string().max(max);
const optStr = (max) => z.string().max(max).optional().nullable();
const rupiah = z.number().int().min(0).max(100_000_000);
const isoDate = z.string().max(40).refine((s) => !Number.isNaN(Date.parse(s)), 'Tanggal tidak valid');

export const MAX_PAYLOAD_BYTES = 64 * 1024;
export const jsonSize = (v) => Buffer.byteLength(JSON.stringify(v), 'utf8');

// ---------- Auth & pengguna ----------
export const usernameSchema = z
  .string()
  .trim()
  .toLowerCase()
  .regex(/^[a-z0-9._-]{3,32}$/, 'Username 3-32 karakter: huruf kecil, angka, titik, strip, garis bawah');

// bcrypt hanya memakai 72 byte pertama -> tolak lebih panjang agar tidak terpotong diam-diam.
export const passwordSchema = z
  .string()
  .min(8, 'Sandi minimal 8 karakter')
  .refine((s) => Buffer.byteLength(s, 'utf8') <= 72, 'Sandi maksimal 72 byte')
  .refine((s) => !/^(.)\1+$/.test(s) && !/^(12345678|password|qwertyui|11111111)$/i.test(s), 'Sandi terlalu mudah ditebak');

export const loginSchema = z.object({
  username: z.string().trim().toLowerCase().min(1).max(64),
  password: z.string().min(1).max(200),
});

export const changePasswordSchema = z.object({
  currentPassword: z.string().min(1).max(200),
  newPassword: passwordSchema,
});

export const userCreateSchema = z.object({
  username: usernameSchema,
  displayName: z.string().trim().min(1).max(60),
  role: z.enum(['Pemilik', 'Kasir']),
  password: passwordSchema,
});

export const userUpdateSchema = z
  .object({
    displayName: z.string().trim().min(1).max(60).optional(),
    role: z.enum(['Pemilik', 'Kasir']).optional(),
    active: z.boolean().optional(),
    password: passwordSchema.optional(),
  })
  .refine((o) => Object.keys(o).length > 0, 'Tidak ada perubahan');

// ---------- Sinkronisasi ----------
export const productSchema = z.object({
  id: idStr,
  name: z.string().trim().min(1).max(120),
  category: str(120).optional().nullable().default(''),
  price: rupiah,
  stock: z.number().int().min(0).max(1_000_000).nullable().optional().default(null),
  available: z.boolean().optional().default(true),
  description: str(500).optional().nullable().default(''),
  emoji: str(16).optional().nullable().default(''),
});

export const categorySchema = z.object({
  id: idStr,
  emoji: str(16).optional().nullable().default(''),
  label: z.string().trim().min(1).max(80),
});

const primitive = z.union([z.string().max(2000), z.number(), z.boolean(), z.null()]);
export const settingsSchema = z
  .object({
    businessName: str(120).optional(),
    businessAddress: str(300).optional(),
    businessPhone: str(40).optional(),
    taxRate: z.number().min(0).max(100).optional(),
    qrisStaticPayload: z
      .string()
      .trim()
      .max(1024)
      .refine((s) => isValidQris(s), 'String QRIS tidak valid (struktur/CRC)')
      .optional(),
    receiptPaperSize: z.enum(['58mm', '80mm', 'A4']).optional(),
    receiptFooter: str(300).optional(),
    onlineRejectionMessage: str(200).optional(),
  })
  .catchall(primitive);

const itemSchema = z.object({
  productId: str(64).optional().nullable(),
  name: z.string().min(1).max(160),
  price: rupiah,
  qty: z.number().int().min(1).max(999),
  total: z.number().int().min(0).max(2_000_000_000).optional(),
  note: optStr(200),
});

export const pendingOrderSchema = z
  .object({
    id: z.string().regex(/^HOLD-\d{8}-[A-Za-z0-9]{3,12}$/, 'ID pesanan tidak valid'),
    createdAt: isoDate.optional(),
    orderType: optStr(30),
    tableNumber: optStr(20),
    items: z.array(itemSchema).min(1).max(100),
    subtotal: z.number().int().min(0).max(2_000_000_000),
    discount: z.number().int().min(0).max(2_000_000_000).optional(),
    total: z.number().int().min(0).max(2_000_000_000),
    status: str(20).optional(),
    payment: optStr(20),
    cashier: optStr(60),
    note: optStr(500),
  })
  .passthrough();

export const ONLINE_STATUSES = ['baru', 'dibuat', 'siap', 'selesai'];
export const onlineOrderSchema = z
  .object({
    id: z.string().regex(/^ONL-[A-Za-z0-9_-]{1,64}$/, 'ID pesanan online tidak valid'),
    source: z.enum(['gofood', 'grab', 'shopee']),
    partnerOrderId: optStr(80),
    orderType: z.enum(['delivery', 'pickup']).optional().nullable(),
    status: z.enum(['baru', 'dibuat', 'siap', 'selesai']),
    customer: optStr(120),
    note: optStr(500),
    items: z
      .array(z.object({ productId: str(64).optional().nullable(), qty: z.number().int().min(1).max(999), note: optStr(200) }).passthrough())
      .max(100),
    rejectReason: optStr(200),
  })
  .passthrough();

export const syncRowSchema = z.object({
  id: idStr,
  payload: z.record(z.string(), z.any()).optional(),
  deleted: z.boolean().optional().default(false),
});

export const syncPushSchema = z.object({
  table: z.string().min(1).max(40),
  rows: z.array(syncRowSchema).min(1).max(1000),
  deviceId: deviceIdSchema,
});

export const PAYMENTS = ['cash', 'qris', 'transfer', 'card'];
export const orderInputSchema = z.object({
  order: z.object({
    id: z.string().regex(/^MPJ-\d{8}-[A-Za-z0-9]{3,12}$/, 'Nomor struk tidak valid'),
    clientTxnId: z.string().uuid('clientTxnId harus UUID'),
    createdAt: isoDate,
    items: z.array(itemSchema).min(1).max(100),
    orderType: z.string().max(30).regex(/^[A-Za-z0-9_-]*$/).optional().nullable(),
    tableNumber: optStr(20),
    discount: z.number().int().min(0).max(2_000_000_000).optional().default(0),
    payment: z.string().max(20).optional().default('cash'),
    paidAmount: z.number().int().min(0).max(2_000_000_000).optional().default(0),
    status: str(20).optional(),
    cashier: optStr(60),
    note: optStr(500),
  }),
  deviceId: deviceIdSchema,
});

export const menuMapSchema = z.object({
  source: z.enum(['gofood', 'grab', 'shopee']),
  partnerMenuId: z.string().min(1).max(120),
  partnerMenuName: z.string().max(200).optional().nullable(),
  productId: idStr.nullable(),
});
`````

### FILE: src/lib/background.js

`````js
import { processQueue } from '../services/gofood.js';

/** Jalankan setelah respons dikirim (waitUntil di Vercel; fire-and-forget di lokal). */
export function kickQueue() {
  const job = processQueue(5).catch((e) => console.error(JSON.stringify({ level: 'error', msg: 'queue', code: e?.code })));
  import('@vercel/functions').then((m) => { try { m.waitUntil(job); } catch { /* bukan di Vercel */ } }).catch(() => {});
}
`````

### FILE: src/middleware/auth.js

`````js
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
`````

### FILE: src/middleware/security.js

`````js
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { config } from '../config.js';

export const securityHeaders = helmet({
  contentSecurityPolicy: { directives: { defaultSrc: ["'none'"], frameAncestors: ["'none'"] } },
  crossOriginResourcePolicy: { policy: 'same-site' },
  referrerPolicy: { policy: 'no-referrer' },
  hsts: { maxAge: 63072000, includeSubDomains: true },
});

const DEV_ORIGINS = ['http://localhost:8031', 'http://127.0.0.1:8031', 'http://localhost:3000'];

export const corsMiddleware = cors({
  origin(origin, cb) {
    if (!origin) return cb(null, true); // non-browser (webhook, curl, cron)
    const allowed = config.corsOrigins.length ? config.corsOrigins : config.isProd ? [] : DEV_ORIGINS;
    cb(null, allowed.includes(origin));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type'],
  credentials: false,
  maxAge: 86400,
});

export function noStore(req, res, next) {
  res.set('Cache-Control', 'no-store');
  next();
}

/** Lapis kasar per-instance (lapis utama untuk login/webhook ada di DB: lib/ratelimit.js). */
export const globalLimiter = rateLimit({
  windowMs: 60_000,
  limit: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'rate_limited', message: 'Terlalu banyak permintaan.' },
});

export function requestLog(req, res, next) {
  const t = Date.now();
  res.on('finish', () => {
    console.log(JSON.stringify({ m: req.method, p: req.path, s: res.statusCode, ms: Date.now() - t, u: req.user?.username }));
  });
  next();
}

/** POST/PUT/DELETE dengan body harus JSON. */
export function requireJson(req, res, next) {
  if (['POST', 'PUT'].includes(req.method) && Number(req.headers['content-length'] || 0) > 0) {
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'unsupported_media_type', message: 'Content-Type harus application/json.' });
    }
  }
  next();
}
`````

### FILE: src/middleware/error.js

`````js
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
`````

### FILE: src/services/audit.js

`````js
/** Catat audit memakai klien transaksi (atau pool). Tidak boleh memuat sandi/token. */
export async function audit(db, actor, action, target = null, detail = null) {
  await db.query('INSERT INTO audit_log (actor, action, target, detail) VALUES ($1,$2,$3,$4)', [
    actor || 'sistem', action, target, detail ? JSON.stringify(detail) : null,
  ]);
}
`````

### FILE: src/services/orders.js

`````js
import { tx } from '../db.js';
import { badRequest } from '../lib/errors.js';
import { PAYMENTS } from '../lib/schemas.js';
import { audit } from './audit.js';

const MAX_INT = 2_147_483_647;
const TS = `to_char(%s AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;
export const tsSql = (col) => TS.replace('%s', col);

/** Hitung ulang total. Murni (mudah diuji): harga resmi menggantikan harga klien. */
export function computeTotals({ items, discount, payment, paidAmount }) {
  let subtotal = 0;
  const lines = items.map((it) => {
    const total = it.price * it.qty;
    subtotal += total;
    return { ...it, total };
  });
  if (subtotal > MAX_INT) throw badRequest('Total pesanan terlalu besar.', 'total_too_large');
  const disc = Math.min(Math.max(Number(discount) || 0, 0), subtotal);
  const total = subtotal - disc;
  const pay = PAYMENTS.includes(payment) ? payment : 'cash';
  let paid = total;
  let change = 0;
  if (pay === 'cash') {
    paid = Math.max(Number(paidAmount) || 0, total);
    change = paid - total;
  }
  return { lines, subtotal, discount: disc, total, payment: pay, paidAmount: paid, changeAmount: change };
}

export function orderDateFromId(id, createdAt) {
  const m = /^[A-Z]+-(\d{4})(\d{2})(\d{2})-/.exec(id);
  if (m) {
    const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
    if (d.getUTCFullYear() === +m[1] && d.getUTCMonth() === +m[2] - 1 && d.getUTCDate() === +m[3]) {
      return `${m[1]}-${m[2]}-${m[3]}`;
    }
  }
  return new Date(createdAt).toISOString().slice(0, 10);
}

export function buildPayload(t, items) {
  return {
    id: t.id,
    clientTxnId: t.client_txn_id,
    createdAt: t.created_iso,
    items: items.map((i) => ({ productId: i.product_id, name: i.name, price: i.price, qty: i.qty, total: i.total, note: i.note || '' })),
    orderType: t.order_type,
    tableNumber: t.table_number || '',
    subtotal: t.subtotal,
    discount: t.discount,
    total: t.total,
    taxRate: Number(t.tax_rate),
    taxIncluded: true,
    payment: t.payment,
    paidAmount: t.paid_amount,
    changeAmount: t.change_amount,
    status: t.status,
    cashier: t.cashier || '',
    note: t.note || '',
  };
}

async function loadExisting(db, id, clientTxnId) {
  const { rows } = await db.query(
    `SELECT *, ${tsSql('created_at')} AS created_iso FROM transactions WHERE id = $1 OR client_txn_id = $2 LIMIT 1`,
    [id, clientTxnId],
  );
  if (!rows[0]) return null;
  const items = await db.query('SELECT * FROM transaction_items WHERE transaction_id = $1 ORDER BY id', [rows[0].id]);
  return buildPayload(rows[0], items.rows);
}

export async function createOrder(input, user) {
  const o = input.order;
  const deviceId = input.deviceId || null;
  const created = new Date(o.createdAt);
  if (created.getTime() > Date.now() + 24 * 3600 * 1000) throw badRequest('Tanggal transaksi di masa depan.', 'bad_date');

  try {
    return await tx(async (db) => {
      const dup = await loadExisting(db, o.id, o.clientTxnId);
      if (dup) return { duplicate: true, order: dup };

      const ids = [...new Set(o.items.map((i) => i.productId).filter(Boolean))].sort();
      const prod = new Map();
      if (ids.length) {
        const r = await db.query(
          'SELECT id, name, price, stock FROM products WHERE id = ANY($1::text[]) AND deleted = false ORDER BY id FOR UPDATE',
          [ids],
        );
        r.rows.forEach((p) => prod.set(p.id, p));
      }
      const unverified = [];
      const items = o.items.map((it) => {
        const p = it.productId ? prod.get(it.productId) : null;
        if (!p) { unverified.push(it.productId || it.name); return { ...it, productId: it.productId || null }; }
        return { ...it, name: p.name, price: p.price };
      });

      const s = await db.query(`SELECT payload->'taxRate' AS tax FROM settings WHERE id = 'main' AND deleted = false`);
      const taxRaw = Number(s.rows[0]?.tax);
      const taxRate = Number.isFinite(taxRaw) ? Math.min(100, Math.max(0, taxRaw)) : 0;

      const c = computeTotals({ items, discount: o.discount, payment: o.payment, paidAmount: o.paidAmount });
      const orderDate = orderDateFromId(o.id, o.createdAt);

      await db.query(
        `INSERT INTO transactions (id, client_txn_id, created_at, order_date, order_type, table_number, subtotal, discount,
           tax_rate, total, payment, paid_amount, change_amount, status, cashier, note, device_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'paid',$14,$15,$16)`,
        [o.id, o.clientTxnId, created.toISOString(), orderDate, o.orderType || null, o.tableNumber || null, c.subtotal,
          c.discount, taxRate, c.total, c.payment, c.paidAmount, c.changeAmount, o.cashier || user.displayName, o.note || null, deviceId],
      );
      for (const l of c.lines) {
        await db.query(
          'INSERT INTO transaction_items (transaction_id, product_id, name, price, qty, total, note) VALUES ($1,$2,$3,$4,$5,$6,$7)',
          [o.id, l.productId || null, l.name, l.price, l.qty, l.total, l.note || null],
        );
      }

      // Stok: hanya produk bertipe stok terbatas; minimum 0; kunci baris sudah diambil (FOR UPDATE).
      const need = new Map();
      c.lines.forEach((l) => { if (l.productId && prod.get(l.productId)?.stock != null) need.set(l.productId, (need.get(l.productId) || 0) + l.qty); });
      for (const [pid, qty] of need) {
        const before = prod.get(pid).stock;
        const after = Math.max(before - qty, 0);
        if (before < qty) await audit(db, user.username, 'stock.conflict', pid, { before, qty, order: o.id });
        await db.query(
          `UPDATE products SET stock = $2, payload = jsonb_set(payload, '{stock}', to_jsonb($2::int)), updated_at = now() WHERE id = $1`,
          [pid, after],
        );
        await db.query(`INSERT INTO stock_movements (product_id, qty, reason, ref, device_id) VALUES ($1,$2,'sale',$3,$4)`, [pid, -(before - after), o.id, deviceId]);
      }
      if (unverified.length) await audit(db, user.username, 'order.item_unverified', o.id, { items: unverified.slice(0, 20) });
      await audit(db, user.username, 'order.created', o.id, { total: c.total, payment: c.payment });

      return { duplicate: false, order: await loadExisting(db, o.id, o.clientTxnId) };
    });
  } catch (e) {
    if (e.code === '23505') { // balapan: permintaan kembar masuk bersamaan
      return tx(async (db) => ({ duplicate: true, order: await loadExisting(db, o.id, o.clientTxnId) }));
    }
    throw e;
  }
}

export async function deleteOrder(id, user) {
  return tx(async (db) => {
    const r = await db.query('UPDATE transactions SET deleted = true, updated_at = now() WHERE id = $1 AND deleted = false RETURNING id', [id]);
    if (!r.rows[0]) return false;
    await audit(db, user.username, 'order.deleted', id, null); // stok SENGAJA tidak dikembalikan
    return true;
  });
}

export async function pullOrders(db, { since, sinceId, limit }) {
  const params = [limit + 1];
  let where = '';
  if (since) { params.push(since, sinceId || ''); where = `WHERE (updated_at, id) > ($2::timestamptz, $3::text)`; }
  const r = await db.query(
    `SELECT *, ${tsSql('created_at')} AS created_iso, ${tsSql('updated_at')} AS updated_iso
       FROM transactions ${where} ORDER BY updated_at, id LIMIT $1`, params);
  const hasMore = r.rows.length > limit;
  const rows = r.rows.slice(0, limit);
  const items = rows.length
    ? (await db.query('SELECT * FROM transaction_items WHERE transaction_id = ANY($1::text[]) ORDER BY id', [rows.filter((t) => !t.deleted).map((t) => t.id)])).rows
    : [];
  const by = new Map();
  items.forEach((i) => by.set(i.transaction_id, [...(by.get(i.transaction_id) || []), i]));
  return {
    rows: rows.map((t) => ({
      id: t.id, deleted: t.deleted, updatedAt: t.updated_iso,
      payload: t.deleted ? { id: t.id } : buildPayload(t, by.get(t.id) || []),
    })),
    hasMore,
  };
}
`````

### FILE: src/services/sync.js

`````js
import { tx } from '../db.js';
import { badRequest, forbidden } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import {
  productSchema, categorySchema, settingsSchema, pendingOrderSchema, onlineOrderSchema,
  jsonSize, MAX_PAYLOAD_BYTES,
} from '../lib/schemas.js';
import { audit } from './audit.js';
import { pullOrders, tsSql } from './orders.js';
import { storeTransition } from './online.js';

// Nama tabel TIDAK pernah berasal dari input: hanya dari Map statis ini (daftar putih).
const TABLES = new Map([
  ['products',       { sql: 'products',       owner: true,  schema: productSchema }],
  ['categories',     { sql: 'categories',     owner: true,  schema: categorySchema }],
  ['settings',       { sql: 'settings',       owner: true,  schema: settingsSchema }],
  ['pending_orders', { sql: 'pending_orders', owner: false, schema: pendingOrderSchema }],
  ['online_orders',  { sql: 'online_orders',  owner: false, schema: onlineOrderSchema }],
]);

export const CLIENT_TABLES = ['products', 'categories', 'settings', 'orders', 'pending_orders', 'online_orders'];
export const isPullable = (t) => TABLES.has(t) || t === 'orders';

export async function pushRows({ table, rows, deviceId }, user) {
  const def = TABLES.get(table); // 'orders' & nama lain -> undefined -> ditolak
  if (!def) throw badRequest('Tabel tidak dikenal.', 'unknown_table');
  if (def.owner && user.role !== 'Pemilik') throw forbidden('Hanya Pemilik yang boleh mengubah data ini.');

  // Validasi SEMUA baris dulu (atomik: satu salah, tidak ada yang tersimpan).
  const prepared = rows.map((row, idx) => {
    const rowId = table === 'settings' ? 'main' : row.id;
    if (row.deleted) return { id: rowId, deleted: true };
    if (!row.payload) throw badRequest(`Baris ${idx}: payload wajib.`, 'validation_error', { rowId: row.id });
    if (jsonSize(row.payload) > MAX_PAYLOAD_BYTES) throw badRequest(`Baris ${idx}: payload terlalu besar.`, 'payload_too_large', { rowId: row.id });
    const candidate = table === 'settings' ? row.payload : { ...row.payload, id: row.payload.id ?? row.id };
    if (table !== 'settings' && candidate.id !== row.id) throw badRequest(`Baris ${idx}: id payload tidak sama dengan id baris.`, 'id_mismatch', { rowId: row.id });
    let data;
    try { data = parse(def.schema, candidate, `Baris ${idx}`); }
    catch (e) { e.extra = { ...(e.extra || {}), rowId: row.id }; throw e; }
    return { id: rowId, deleted: false, data };
  });

  return tx(async (db) => {
    const ids = prepared.map((p) => p.id);
    const old = new Map((await db.query(`SELECT id, payload, deleted${table === 'products' ? ', stock' : ''} FROM ${def.sql} WHERE id = ANY($1::text[]) FOR UPDATE`, [ids])).rows.map((r) => [r.id, r]));

    for (const p of prepared) {
      const prev = old.get(p.id);
      if (p.deleted) {
        // Tombstone = UPDATE saja (tidak membuat baris baru untuk id yang tidak ada).
        if (!prev || prev.deleted) continue;
        await db.query(`UPDATE ${def.sql} SET deleted = true, updated_at = now(), device_id = $2 WHERE id = $1`, [p.id, deviceId || null]);
        if (table === 'online_orders') await storeTransition(db, { oldPayload: prev.payload, newPayload: null, deleted: true, actor: user.username });
        continue;
      }
      if (table === 'products') {
        const d = p.data;
        await db.query(
          `INSERT INTO products (id, name, category_id, price, stock, available, description, emoji, payload, device_id)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
           ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, category_id=EXCLUDED.category_id, price=EXCLUDED.price,
             stock=EXCLUDED.stock, available=EXCLUDED.available, description=EXCLUDED.description, emoji=EXCLUDED.emoji,
             payload=EXCLUDED.payload, deleted=false, updated_at=now(), device_id=EXCLUDED.device_id`,
          [d.id, d.name, d.category || null, d.price, d.stock, d.available, d.description || null, d.emoji || null, JSON.stringify(d), deviceId || null]);
        if (prev && !prev.deleted && prev.stock != null && d.stock != null && prev.stock !== d.stock) {
          await db.query(`INSERT INTO stock_movements (product_id, qty, reason, ref, device_id) VALUES ($1,$2,'adjust','catalog',$3)`, [d.id, d.stock - prev.stock, deviceId || null]);
        }
        continue;
      }
      if (table === 'online_orders') {
        if (prev?.deleted) continue; // pesanan yang sudah ditutup tidak dihidupkan lagi
        await db.query(
          `INSERT INTO online_orders (id, payload, device_id) VALUES ($1,$2,$3)
           ON CONFLICT (id) DO UPDATE SET payload=EXCLUDED.payload, updated_at=now(), device_id=EXCLUDED.device_id`,
          [p.id, JSON.stringify(p.data), deviceId || null]);
        await storeTransition(db, { oldPayload: prev?.payload, newPayload: p.data, deleted: false, actor: user.username });
        continue;
      }
      await db.query(
        `INSERT INTO ${def.sql} (id, payload, device_id) VALUES ($1,$2,$3)
         ON CONFLICT (id) DO UPDATE SET payload=EXCLUDED.payload, deleted=false, updated_at=now(), device_id=EXCLUDED.device_id`,
        [p.id, JSON.stringify(p.data), deviceId || null]);
    }
    if (table === 'settings') await audit(db, user.username, 'settings.updated', 'main', null);
    return { accepted: prepared.length };
  });
}

const CURSOR_TS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/;

export async function pullTable(table, { since, sinceId, limit }) {
  if (!isPullable(table)) throw badRequest('Tabel tidak dikenal.', 'unknown_table');
  if (since && !CURSOR_TS.test(since)) throw badRequest('Parameter since tidak valid.', 'bad_cursor');
  const lim = Math.min(Math.max(Number.parseInt(limit, 10) || 1000, 1), 1000);

  const run = async (db) => {
    if (table === 'orders') return pullOrders(db, { since, sinceId, limit: lim });
    const def = TABLES.get(table);
    const params = [lim + 1];
    let where = '';
    if (since) { params.push(since, sinceId || ''); where = 'WHERE (updated_at, id) > ($2::timestamptz, $3::text)'; }
    const r = await db.query(`SELECT id, payload, deleted, ${tsSql('updated_at')} AS updated_iso FROM ${def.sql} ${where} ORDER BY updated_at, id LIMIT $1`, params);
    return {
      hasMore: r.rows.length > lim,
      rows: r.rows.slice(0, lim).map((x) => ({ id: x.id, deleted: x.deleted, updatedAt: x.updated_iso, payload: x.deleted && table === 'online_orders' ? { id: x.id } : x.payload })),
    };
  };
  const out = await tx(run);
  const last = out.rows[out.rows.length - 1];
  return {
    table,
    rows: out.rows,
    hasMore: out.hasMore,
    cursor: last ? { since: last.updatedAt, sinceId: last.id } : (since ? { since, sinceId: sinceId || '' } : null),
    serverTime: new Date().toISOString(),
  };
}
`````

### FILE: src/services/online.js

`````js
import { config } from '../config.js';
import { audit } from './audit.js';
import { ONLINE_STATUSES } from '../lib/schemas.js';

const RANK = Object.fromEntries(ONLINE_STATUSES.map((s, i) => [s, i]));
const PREFIX = { gofood: 'GF', grab: 'GR', shopee: 'SP' };

const clean = (v, max = 200) => (v == null ? '' : String(v).replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max));
const safeId = (v) => clean(v, 80).replace(/[^A-Za-z0-9_-]/g, '');

export const normName = (s) =>
  clean(s, 200).toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
export const baseName = (s) => normName(String(s || '').replace(/\(.*?\)|\[.*?\]|\s[-–]\s.*$/g, ''));

/** Ubah envelope GoBiz menjadi bentuk internal. Mengembalikan null bila bukan event pesanan. */
export function normalizeGoFood(env) {
  const header = env?.header || {};
  const body = env?.body || {};
  const order = body.order;
  const eventName = clean(header.event_name, 80);
  if (!eventName.startsWith('gofood.order.') || !order || typeof order !== 'object') return null;
  const orderNumber = safeId(order.order_number);
  if (!orderNumber) return null;
  const items = (Array.isArray(order.order_items) ? order.order_items : []).slice(0, 100).map((it) => {
    const variants = (Array.isArray(it.variants) ? it.variants : []).map((v) => clean(v.name, 60)).filter(Boolean);
    const note = [clean(it.notes, 150), variants.length ? `Varian: ${variants.join(', ')}` : ''].filter(Boolean).join(' | ');
    return {
      partnerMenuId: clean(it.external_id || it.id, 120),
      name: clean(it.name, 160),
      qty: Math.min(999, Math.max(1, Math.trunc(Number(it.quantity)) || 1)),
      price: Math.max(0, Math.trunc(Number(it.price)) || 0),
      note,
    };
  });
  return {
    eventName,
    eventId: clean(header.event_id, 80),
    partnerOrderId: orderNumber,
    partnerStatus: clean(order.status, 40).toUpperCase(),
    orderType: body.service_type === 'gofood_pickup' ? 'pickup' : 'delivery',
    outletId: clean(body.outlet?.id, 60),
    externalOutletId: clean(body.outlet?.external_outlet_id, 60),
    customer: clean(body.customer?.name, 120),
    driverName: clean(body.driver?.name, 120),
    pin: clean(order.pin, 12),
    total: Math.max(0, Math.trunc(Number(order.order_total)) || 0),
    createdAt: Number.isNaN(Date.parse(order.created_at)) ? new Date().toISOString() : new Date(order.created_at).toISOString(),
    items,
  };
}

/** Status partner -> status kasir. Tidak pernah menutup/menyelesaikan otomatis. */
export function mapStatus(partnerStatus) {
  switch (partnerStatus) {
    case 'MERCHANT_ACCEPTED':
    case 'PREP_ORDER_NOW': return 'dibuat';
    case 'DRIVER_OTW_PICKUP':
    case 'DRIVER_ARRIVED':
    case 'PLACED':
    case 'COMPLETED': return 'siap';
    default: return 'baru';
  }
}

/** peta manual -> id sama -> nama persis -> nama dasar -> awalan unik */
export function matchProduct(item, products, mapRows) {
  const manual = mapRows.get(item.partnerMenuId);
  if (manual?.product_id && products.some((p) => p.id === manual.product_id)) return { productId: manual.product_id, auto: false };
  if (manual && !manual.auto_matched && !manual.product_id) return null; // pemilik sengaja mengosongkan
  const byId = products.find((p) => p.id === item.partnerMenuId);
  if (byId) return { productId: byId.id, auto: true };
  const n = normName(item.name);
  if (!n) return null;
  const exact = products.filter((p) => normName(p.name) === n);
  if (exact.length === 1) return { productId: exact[0].id, auto: true };
  const b = baseName(item.name);
  const base = products.filter((p) => baseName(p.name) === b);
  if (b && base.length === 1) return { productId: base[0].id, auto: true };
  if (b.length >= 4) {
    const pre = products.filter((p) => {
      const pb = baseName(p.name);
      return pb.startsWith(b) || (pb.length >= 4 && b.startsWith(pb));
    });
    if (pre.length === 1) return { productId: pre[0].id, auto: true };
  }
  return null;
}

async function queueAction(db, { source, orderId, partnerOrderId, orderType, action, status = 'queued', reasonCode = null, reasonText = null }) {
  await db.query(
    `INSERT INTO online_order_actions (source, order_id, partner_order_id, order_type, action, status, reason_code, reason_text)
     SELECT $1,$2,$3,$4,$5,$6,$7,$8
      WHERE NOT EXISTS (SELECT 1 FROM online_order_actions WHERE order_id=$2 AND action=$5 AND status IN ('queued','sent','failed'))`,
    [source, orderId, partnerOrderId, orderType, action, status, reasonCode, reasonText]);
}

/** Dipanggil saat kasir mengubah status pesanan online (lewat sync push). */
export async function storeTransition(db, { oldPayload, newPayload, deleted, actor }) {
  const src = newPayload?.source || oldPayload?.source;
  if (!src) return;
  const base = {
    source: src,
    orderId: (newPayload || oldPayload).id,
    partnerOrderId: (newPayload || oldPayload).partnerOrderId || null,
    orderType: (newPayload || oldPayload).orderType || null,
  };
  if (!base.partnerOrderId) return;
  const off = src !== 'gofood' ? { status: 'ignored' } : {};
  const oldS = oldPayload?.status;
  if (deleted) {
    // Aksi tolak hanya bila pesanan belum diterima (status lama 'baru'); selain itu tidak mengirim apa pun.
    if (oldS === 'baru') {
      const { rows } = await db.query(`SELECT payload->>'onlineRejectionMessage' AS msg FROM settings WHERE id='main'`);
      await queueAction(db, { ...base, ...off, action: 'reject', reasonCode: config.gofood.rejectReasonCode, reasonText: clean(oldPayload?.rejectReason || rows[0]?.msg || 'Mohon maaf stok habis', 200) });
      await audit(db, actor, 'online:reject', base.orderId, null);
    }
    return;
  }
  const newS = newPayload.status;
  if (oldS === 'baru' && RANK[newS] >= RANK.dibuat) {
    await queueAction(db, { ...base, ...off, action: 'accept' });
    await audit(db, actor, 'online:accept', base.orderId, null);
  }
  if ((oldS == null || RANK[oldS] < RANK.siap) && RANK[newS] >= RANK.siap) {
    if (oldS === 'baru') await queueAction(db, { ...base, ...off, action: 'accept' });
    await queueAction(db, { ...base, ...off, action: 'ready' });
    await audit(db, actor, 'online:ready', base.orderId, null);
  }
}

/** Proses event GoFood (dipanggil di dalam transaksi DB). Mengembalikan {status, note}. */
export async function ingestGoFood(db, ev) {
  const gf = config.gofood;
  if (gf.outletId && ev.outletId !== gf.outletId && ev.externalOutletId !== gf.outletId) {
    return { status: 'ignored', note: 'outlet tidak cocok' };
  }
  const id = `ONL-${PREFIX.gofood}-${ev.partnerOrderId}`.slice(0, 68);
  const cur = (await db.query('SELECT payload, deleted FROM online_orders WHERE id=$1 FOR UPDATE', [id])).rows[0];
  if (cur?.deleted) return { status: 'ignored', note: 'pesanan sudah ditutup' };

  if (ev.partnerStatus === 'CANCELLED') {
    if (!cur) return { status: 'ignored', note: 'batal untuk pesanan yang belum dikenal' };
    if (cur.payload.status === 'baru') {
      await db.query('UPDATE online_orders SET deleted=true, updated_at=now() WHERE id=$1', [id]);
      await audit(db, 'sistem', 'online:cancelled_by_partner', id, null);
      return { status: 'accepted', note: 'dibatalkan mitra' };
    }
    await db.query(`UPDATE online_orders SET payload = jsonb_set(payload,'{partnerStatus}','"CANCELLED"'), updated_at=now() WHERE id=$1`, [id]);
    await queueAction(db, { source: 'gofood', orderId: id, partnerOrderId: ev.partnerOrderId, orderType: ev.orderType, action: 'cancel-review', status: 'manual' });
    await audit(db, 'sistem', 'online:cancel_review', id, null);
    return { status: 'accepted', note: 'dibatalkan mitra, perlu ditinjau' };
  }

  const products = (await db.query('SELECT id, name FROM products WHERE deleted=false')).rows;
  const mapRows = new Map((await db.query(`SELECT * FROM online_menu_map WHERE source='gofood'`)).rows.map((r) => [r.partner_menu_id, r]));
  const items = [];
  const unmapped = [];
  for (const it of ev.items) {
    const m = matchProduct(it, products, mapRows);
    if (m) {
      items.push({ productId: m.productId, qty: it.qty, note: it.note });
      if (m.auto && it.partnerMenuId) {
        await db.query(
          `INSERT INTO online_menu_map (id, source, partner_menu_id, partner_menu_name, product_id, auto_matched)
           VALUES ($1,'gofood',$2,$3,$4,true)
           ON CONFLICT (source, partner_menu_id) DO UPDATE SET product_id=COALESCE(online_menu_map.product_id, EXCLUDED.product_id), partner_menu_name=EXCLUDED.partner_menu_name, updated_at=now()`,
          [`gofood:${it.partnerMenuId}`.slice(0, 140), it.partnerMenuId, it.name, m.productId]);
      }
    } else {
      unmapped.push({ partnerMenuId: it.partnerMenuId, name: it.name, qty: it.qty, price: it.price, note: it.note });
      if (it.partnerMenuId) {
        await db.query(
          `INSERT INTO online_menu_map (id, source, partner_menu_id, partner_menu_name) VALUES ($1,'gofood',$2,$3)
           ON CONFLICT (source, partner_menu_id) DO NOTHING`,
          [`gofood:${it.partnerMenuId}`.slice(0, 140), it.partnerMenuId, it.name]);
      }
    }
  }

  const prevStatus = cur?.payload?.status || 'baru';
  const mapped = mapStatus(ev.partnerStatus);
  const status = RANK[mapped] > RANK[prevStatus] ? mapped : prevStatus; // tidak pernah mundur
  const payload = {
    ...(cur?.payload || {}),
    id, source: 'gofood', partnerOrderId: ev.partnerOrderId,
    partnerOutletId: ev.outletId, externalOutletId: ev.externalOutletId,
    orderType: ev.orderType, code: `GF-${ev.partnerOrderId}`,
    customer: ev.customer, driverName: ev.driverName, driverPin: ev.pin,
    note: ev.items.map((i) => i.note).filter(Boolean).join(' ; ').slice(0, 500),
    status, partnerStatus: ev.partnerStatus, createdAt: cur?.payload?.createdAt || ev.createdAt,
    items, unmappedItems: unmapped, partnerTotal: ev.total,
  };
  await db.query(
    `INSERT INTO online_orders (id, payload, device_id) VALUES ($1,$2,'webhook')
     ON CONFLICT (id) DO UPDATE SET payload=EXCLUDED.payload, updated_at=now(), device_id='webhook'`,
    [id, JSON.stringify(payload)]);

  if (!cur && gf.autoAccept) {
    await queueAction(db, { source: 'gofood', orderId: id, partnerOrderId: ev.partnerOrderId, orderType: ev.orderType, action: 'accept' });
  }
  return { status: 'accepted', note: cur ? 'diperbarui' : 'pesanan baru', orderId: id, isNew: !cur };
}
`````

### FILE: src/services/gofood.js

`````js
import { config } from '../config.js';
import { query } from '../db.js';
import { AppError } from '../lib/errors.js';

const TIMEOUT_MS = 10_000;
let tokenCache = { token: null, exp: 0 };

function assertReady() {
  if (!config.gofood.apiReady) {
    throw new AppError(503, 'gofood_not_configured', 'Kredensial GoFood belum diisi di server.');
  }
}

export async function getToken() {
  assertReady();
  if (tokenCache.token && Date.now() < tokenCache.exp - 30_000) return tokenCache.token;
  const body = new URLSearchParams({
    client_id: config.gofood.clientId,
    client_secret: config.gofood.clientSecret,
    grant_type: 'client_credentials',
    scope: config.gofood.scope,
  });
  const res = await fetch(config.gofood.authUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
    body,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`GoBiz auth HTTP ${res.status}`);
  const j = await res.json();
  if (!j.access_token) throw new Error('GoBiz auth: token kosong');
  tokenCache = { token: j.access_token, exp: Date.now() + (Number(j.expires_in) || 300) * 1000 };
  return tokenCache.token;
}

async function call(method, path, body) {
  const token = await getToken();
  const res = await fetch(`${config.gofood.apiBase}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  let data = null;
  try { data = await res.json(); } catch { /* body kosong */ }
  if (res.status === 401) tokenCache = { token: null, exp: 0 };
  return { status: res.status, ok: res.ok, data };
}

const seg = (v) => encodeURIComponent(String(v));

/** Kirim satu aksi antrean ke GoBiz. Endpoint sesuai dokumentasi developer.gobiz.com. */
export async function sendAction(a) {
  const outlet = seg(config.gofood.outletId);
  const type = a.order_type === 'pickup' ? 'pickup' : 'delivery';
  const id = seg(a.partner_order_id);
  const base = `/integrations/gofood/outlets/${outlet}/v1/orders/${type}/${id}`;
  if (a.action === 'accept') return call('PUT', `${base}/accepted`);
  if (a.action === 'ready') return call('PUT', `${base}/food-prepared`);
  if (a.action === 'reject') {
    const text = String(a.reason_text || 'Mohon maaf stok habis').padEnd(3, '.').slice(0, 200);
    return call('PUT', `${base}/cancelled`, {
      cancel_reason_code: a.reason_code || config.gofood.rejectReasonCode,
      cancel_reason_description: text,
    });
  }
  throw new Error(`Aksi tidak didukung: ${a.action}`);
}

export async function listSubscriptions() {
  const r = await call('GET', `/integrations/partner/outlets/${seg(config.gofood.outletId)}/v1/notification-subscriptions`);
  return r;
}

export const SUBSCRIBE_EVENTS = [
  'gofood.order.created',
  'gofood.order.awaiting_merchant_acceptance',
  'gofood.order.merchant_accepted',
  'gofood.order.prep_order_now',
  'gofood.order.driver_otw_pickup',
  'gofood.order.driver_arrived',
  'gofood.order.completed',
  'gofood.order.cancelled',
];

export async function subscribeAll() {
  if (!/^https:\/\//i.test(config.gofood.webhookUrl)) {
    throw new AppError(400, 'webhook_url_invalid', 'GOFOOD_WEBHOOK_URL wajib HTTPS publik.');
  }
  const existing = await listSubscriptions();
  const have = new Set((existing.data?.data?.subscriptions || []).filter((s) => s.url === config.gofood.webhookUrl).map((s) => s.event));
  const results = [];
  for (const event of SUBSCRIBE_EVENTS) {
    if (have.has(event)) { results.push({ event, status: 'sudah ada' }); continue; }
    const r = await call('POST', `/integrations/partner/outlets/${seg(config.gofood.outletId)}/v1/notification-subscriptions`, {
      event, url: config.gofood.webhookUrl, active: true,
    });
    results.push({ event, status: r.ok ? 'dibuat' : `gagal (HTTP ${r.status})` });
  }
  return results;
}

const MAX_ATTEMPTS = 5;

/** Klaim (lease) lalu kirim satu aksi. Aman dipanggil bersamaan dari cron & retry manual. */
export async function processAction(id) {
  const claim = await query(
    `UPDATE online_order_actions SET locked_until = now() + interval '60 seconds', updated_at = now()
      WHERE id = $1 AND status IN ('queued','failed') AND (locked_until IS NULL OR locked_until < now())
      RETURNING *`, [id]);
  const a = claim.rows[0];
  if (!a) return { id, skipped: true };
  if (a.source !== 'gofood') {
    await query(`UPDATE online_order_actions SET status='ignored', error='Adapter belum tersedia', locked_until=NULL, updated_at=now() WHERE id=$1`, [id]);
    return { id, status: 'ignored' };
  }
  if (!config.gofood.apiReady) {
    await query(`UPDATE online_order_actions SET locked_until=NULL, error='Kredensial GoFood belum diisi', updated_at=now() WHERE id=$1`, [id]);
    return { id, status: 'queued', note: 'kredensial belum ada' };
  }
  const attempts = a.attempts + 1;
  try {
    const r = await sendAction(a);
    if (r.ok) {
      await query(`UPDATE online_order_actions SET status='sent', attempts=$2, error=NULL, locked_until=NULL, updated_at=now() WHERE id=$1`, [id, attempts]);
      return { id, status: 'sent' };
    }
    const permanent = [400, 403, 404, 406].includes(r.status);
    const next = permanent || attempts >= MAX_ATTEMPTS ? 'manual' : 'failed';
    await query(`UPDATE online_order_actions SET status=$3, attempts=$2, error=$4, locked_until=NULL, updated_at=now() WHERE id=$1`,
      [id, attempts, next, `HTTP ${r.status}`]);
    return { id, status: next, http: r.status };
  } catch (e) {
    const next = attempts >= MAX_ATTEMPTS ? 'manual' : 'failed';
    await query(`UPDATE online_order_actions SET status=$3, attempts=$2, error=$4, locked_until=NULL, updated_at=now() WHERE id=$1`,
      [id, attempts, next, String(e.message).slice(0, 200)]);
    return { id, status: next };
  }
}

/** Kirim antrean (dipanggil cron). Backoff: tunggu attempts * 2 menit sebelum mencoba lagi. */
export async function processQueue(limit = 20) {
  const { rows } = await query(
    `SELECT id FROM online_order_actions
      WHERE status IN ('queued','failed') AND attempts < $2
        AND updated_at <= now() - (attempts * interval '2 minutes')
      ORDER BY created_at LIMIT $1`, [limit, MAX_ATTEMPTS]);
  const out = [];
  for (const r of rows) out.push(await processAction(r.id));
  return out;
}
`````

### FILE: src/routes/health.js

`````js
import { Router } from 'express';
import { config } from '../config.js';
import { query } from '../db.js';
import { ah } from '../lib/errors.js';

const r = Router();
// Selalu 200 selama proses hidup. Tidak membocorkan detail konfigurasi.
r.get('/', ah(async (req, res) => {
  let db = 'unconfigured';
  if (config.dbConfigured) {
    try {
      await Promise.race([query('SELECT 1'), new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 3000))]);
      db = 'up';
    } catch { db = 'down'; }
  }
  res.json({ ok: true, db, time: new Date().toISOString() });
}));
export default r;
`````

### FILE: src/routes/auth.js

`````js
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
`````

### FILE: src/routes/users.js

`````js
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
`````

### FILE: src/routes/sync.js

`````js
import { Router } from 'express';
import { ah } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { syncPushSchema } from '../lib/schemas.js';
import { requireAuth } from '../middleware/auth.js';
import { pushRows, pullTable, CLIENT_TABLES } from '../services/sync.js';
import { kickQueue } from '../lib/background.js';

const r = Router();
r.use(requireAuth);

r.get('/tables', (req, res) => res.json({ tables: CLIENT_TABLES }));

r.post('/push', ah(async (req, res) => {
  const body = parse(syncPushSchema, req.body, 'Sinkronisasi');
  const result = await pushRows(body, req.user);
  if (body.table === 'online_orders') kickQueue(); // kirim aksi ke mitra tanpa menahan respons
  res.json({ ok: true, table: body.table, ...result, serverTime: new Date().toISOString() });
}));

r.get('/pull', ah(async (req, res) => {
  const { table, since, sinceId, limit } = req.query;
  const one = (v) => (typeof v === 'string' ? v : undefined); // tolak array/objek dari query string
  res.json(await pullTable(one(table), { since: one(since), sinceId: one(sinceId), limit: one(limit) }));
}));

export default r;
`````

### FILE: src/routes/orders.js

`````js
import { Router } from 'express';
import { ah, notFound, badRequest } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { orderInputSchema } from '../lib/schemas.js';
import { requireAuth, requireOwner } from '../middleware/auth.js';
import { createOrder, deleteOrder } from '../services/orders.js';

const r = Router();
r.use(requireAuth);

r.post('/', ah(async (req, res) => {
  const input = parse(orderInputSchema, req.body, 'Transaksi');
  const out = await createOrder(input, req.user);
  res.status(out.duplicate ? 200 : 201).json({ ok: true, ...out });
}));

r.delete('/:id', requireOwner, ah(async (req, res) => {
  if (!/^MPJ-\d{8}-[A-Za-z0-9]{3,12}$/.test(req.params.id)) throw badRequest('Nomor struk tidak valid.');
  if (!(await deleteOrder(req.params.id, req.user))) throw notFound('Transaksi tidak ditemukan.');
  res.json({ ok: true, id: req.params.id, stockRestored: false });
}));

export default r;
`````

### FILE: src/routes/webhooks.js

`````js
import { config } from '../config.js';
import { query, tx } from '../db.js';
import { ah, notFound } from '../lib/errors.js';
import { enforce } from '../lib/ratelimit.js';
import { sha256Hex, verifyGoSignature } from '../lib/crypto.js';
import { ingestGoFood, normalizeGoFood } from '../services/online.js';
import { kickQueue } from '../lib/background.js';

const logEvent = (db, e) =>
  db.query(
    `INSERT INTO webhook_events (source, event_type, entity_id, idempotency_key, signature_ok, status, note, raw)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
    [e.source, e.eventType || null, e.entityId || null, e.key || null, Boolean(e.sigOk), e.status, (e.note || '').slice(0, 300), e.raw ? JSON.stringify(e.raw) : null]);

/** Dipasang dengan express.raw() supaya tanda tangan dihitung dari byte asli, bukan hasil parse. */
export const webhookHandler = ah(async (req, res) => {
  const source = String(req.params.source || '').toLowerCase();
  // Hanya GoFood yang punya verifikasi tanda tangan. Sumber lain ditolak (jangan terima webhook tanpa autentikasi).
  if (source !== 'gofood') throw notFound('Sumber webhook tidak didukung.');
  await enforce(`wh:${source}:${req.ip}`, 300, 60, 'Terlalu banyak permintaan webhook.');

  const raw = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
  const sigOk = verifyGoSignature(raw, req.headers['x-go-signature'], config.gofood.notificationSecret);
  if (!sigOk) {
    // Isi body penyerang TIDAK disimpan; hanya ukuran & hash untuk jejak.
    await logEvent({ query }, { source, sigOk: false, status: 'rejected', note: `tanda tangan tidak valid; bytes=${raw.length}; sha256=${sha256Hex(raw).slice(0, 16)}` });
    return res.status(401).json({ error: 'invalid_signature', message: 'Tanda tangan tidak valid.' });
  }

  let env;
  try { env = JSON.parse(raw.toString('utf8')); } catch { env = null; }
  if (!env || typeof env !== 'object') {
    await logEvent({ query }, { source, sigOk: true, status: 'rejected', note: 'JSON tidak valid' });
    return res.status(400).json({ error: 'invalid_json', message: 'Body bukan JSON.' });
  }

  const headerKey = String(req.headers['x-go-idempotency-key'] || '').trim();
  const rawKey = headerKey || String(env?.header?.event_id || '').trim();
  const key = /^[\w.:-]{1,128}$/.test(rawKey) ? rawKey : '';
  const ev = normalizeGoFood(env);
  const meta = { source, sigOk: true, key, eventType: String(env?.header?.event_name || '').slice(0, 80), entityId: ev?.partnerOrderId, raw: env };

  let result;
  try {
    result = await tx(async (db) => {
      // Klaim kunci idempotensi di transaksi yang SAMA dengan pemrosesan: gagal => rollback => mitra bisa mengirim ulang.
      const claim = await db.query(
        `INSERT INTO webhook_events (source, event_type, entity_id, idempotency_key, signature_ok, status, raw)
         VALUES ($1,$2,$3,$4,true,'accepted',$5)
         ${key ? 'ON CONFLICT (source, idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING' : ''}
         RETURNING id`,
        [source, meta.eventType || null, meta.entityId || null, key || null, JSON.stringify(env)]);
      if (!claim.rows[0]) return { status: 'duplicate' };
      if (!ev) {
        await db.query(`UPDATE webhook_events SET status='ignored', note='bukan event pesanan' WHERE id=$1`, [claim.rows[0].id]);
        return { status: 'ignored' };
      }
      const out = await ingestGoFood(db, ev);
      await db.query('UPDATE webhook_events SET status=$2, note=$3 WHERE id=$1', [claim.rows[0].id, out.status, (out.note || '').slice(0, 300)]);
      return out;
    });
  } catch (e) {
    await logEvent({ query }, { ...meta, key: '', raw: null, status: 'error', note: `gagal diproses: ${String(e.code || e.name)}` }).catch(() => {});
    throw e; // 500 -> GoBiz mengirim ulang (at-least-once)
  }

  if (result.status === 'duplicate') {
    await logEvent({ query }, { ...meta, key: '', raw: null, status: 'duplicate', note: `duplikat dari kunci ${key}` });
  }
  if (result.isNew && config.gofood.autoAccept) kickQueue();
  res.status(200).json({ ok: true, status: result.status });
});
`````

### FILE: src/routes/online.js

`````js
import { Router } from 'express';
import { config } from '../config.js';
import { query } from '../db.js';
import { ah, notFound, badRequest } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { menuMapSchema } from '../lib/schemas.js';
import { requireAuth, requireOwner } from '../middleware/auth.js';
import { audit } from '../services/audit.js';
import { listSubscriptions, processAction, processQueue, subscribeAll } from '../services/gofood.js';

const r = Router();
r.use(requireAuth);

const lim = (v, d = 50) => Math.min(Math.max(Number.parseInt(typeof v === 'string' ? v : '', 10) || d, 1), 200);

// Status konfigurasi tanpa rahasia (hanya boolean/URL publik).
r.get('/config', requireOwner, (req, res) => {
  const g = config.gofood;
  res.json({
    gofood: {
      apiReady: g.apiReady, notificationSecretSet: Boolean(g.notificationSecret), webhookUrl: g.webhookUrl || null,
      autoAccept: g.autoAccept, rejectReasonCode: g.rejectReasonCode, apiBase: g.apiBase, outletIdSet: Boolean(g.outletId),
    },
    grab: { supported: false }, shopee: { supported: false },
  });
});

r.get('/orders', ah(async (req, res) => {
  const { rows } = await query(`SELECT id, payload, updated_at FROM online_orders WHERE deleted = false ORDER BY updated_at DESC LIMIT $1`, [lim(req.query.limit, 100)]);
  res.json({ orders: rows.map((x) => ({ ...x.payload, updatedAt: x.updated_at })) });
}));

r.get('/menu-map', ah(async (req, res) => {
  const { rows } = await query(
    `SELECT m.id, m.source, m.partner_menu_id, m.partner_menu_name, m.product_id, m.auto_matched, p.name AS product_name
       FROM online_menu_map m LEFT JOIN products p ON p.id = m.product_id ORDER BY m.source, m.partner_menu_name LIMIT 500`);
  res.json({ items: rows });
}));

r.put('/menu-map', requireOwner, ah(async (req, res) => {
  const d = parse(menuMapSchema, req.body, 'Peta menu');
  if (d.productId) {
    const p = await query('SELECT 1 FROM products WHERE id=$1 AND deleted=false', [d.productId]);
    if (!p.rows[0]) throw badRequest('Produk tidak ditemukan.', 'product_not_found');
  }
  const { rows } = await query(
    `INSERT INTO online_menu_map (id, source, partner_menu_id, partner_menu_name, product_id, auto_matched)
     VALUES ($1,$2,$3,$4,$5,false)
     ON CONFLICT (source, partner_menu_id) DO UPDATE SET product_id=EXCLUDED.product_id,
       partner_menu_name=COALESCE(EXCLUDED.partner_menu_name, online_menu_map.partner_menu_name), auto_matched=false, updated_at=now()
     RETURNING *`,
    [`${d.source}:${d.partnerMenuId}`.slice(0, 140), d.source, d.partnerMenuId, d.partnerMenuName || null, d.productId]);
  await audit({ query }, req.user.username, 'online.menu_map', rows[0].id, { productId: d.productId });
  res.json({ item: rows[0] });
}));

r.get('/actions', ah(async (req, res) => {
  const { rows } = await query(
    `SELECT id, source, order_id, partner_order_id, order_type, action, status, attempts, reason_code, reason_text, error, created_at, updated_at
       FROM online_order_actions ORDER BY id DESC LIMIT $1`, [lim(req.query.limit)]);
  res.json({ actions: rows });
}));

r.post('/actions/process', requireOwner, ah(async (req, res) => res.json({ results: await processQueue(20) })));

r.post('/actions/:id/retry', ah(async (req, res) => {
  if (!/^\d{1,18}$/.test(req.params.id)) throw badRequest('ID tidak valid.');
  const a = await query('SELECT status FROM online_order_actions WHERE id=$1', [req.params.id]);
  if (!a.rows[0]) throw notFound('Aksi tidak ditemukan.');
  // 'manual' (gagal permanen/ditinjau) boleh dicoba ulang oleh pemilik saja.
  if (a.rows[0].status === 'manual') {
    if (req.user.role !== 'Pemilik') throw badRequest('Hanya Pemilik yang boleh mengulang aksi manual.', 'owner_only');
    await query(`UPDATE online_order_actions SET status='queued', attempts=0, error=NULL, updated_at=now() WHERE id=$1`, [req.params.id]);
  }
  res.json({ result: await processAction(req.params.id) });
}));

r.get('/webhooks', requireOwner, ah(async (req, res) => {
  const { rows } = await query(
    `SELECT id, source, event_type, entity_id, signature_ok, status, note, created_at
       FROM webhook_events ORDER BY id DESC LIMIT $1`, [lim(req.query.limit)]); // raw TIDAK dikembalikan
  res.json({ events: rows });
}));

r.post('/gofood/cek', requireOwner, ah(async (req, res) => {
  const s = await listSubscriptions();
  res.json({ ok: s.ok, httpStatus: s.status, subscriptions: s.data?.data?.subscriptions?.length ?? null });
}));

r.post('/gofood/langganan', requireOwner, ah(async (req, res) => {
  const results = await subscribeAll();
  await audit({ query }, req.user.username, 'online.gofood_subscribe', null, { count: results.length });
  res.json({ results });
}));

export default r;
`````

### FILE: src/routes/cron.js

`````js
import { Router } from 'express';
import { config } from '../config.js';
import { query } from '../db.js';
import { ah, unauthorized } from '../lib/errors.js';
import { safeEqual } from '../lib/crypto.js';
import { processQueue } from '../services/gofood.js';

const r = Router();

// Vercel Cron mengirim "Authorization: Bearer $CRON_SECRET" bila env CRON_SECRET diset.
r.get('/maintenance', ah(async (req, res) => {
  const given = String(req.headers.authorization || '');
  if (!config.cronSecret || config.cronSecret.length < 16 || !safeEqual(given, `Bearer ${config.cronSecret}`)) throw unauthorized('Tidak diizinkan.');
  const actions = await processQueue(20);
  const rl = await query(`DELETE FROM rate_limits WHERE reset_at < now() - interval '1 hour'`);
  const wh = await query(`DELETE FROM webhook_events WHERE created_at < now() - ($1::int * interval '1 day')`, [config.webhookRetentionDays]);
  res.json({ ok: true, actionsProcessed: actions.length, rateLimitsPurged: rl.rowCount, webhookEventsPurged: wh.rowCount });
}));

export default r;
`````

### FILE: scripts/migrate.js

`````js
// Jalankan: npm run migrate   (butuh DATABASE_URL; dijalankan dari komputer Anda, BUKAN saat runtime Vercel)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { config } from '../src/config.js';
import { getPool, closePool } from '../src/db.js';

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations');

export async function migrate(log = console.log) {
  const client = await getPool().connect();
  try {
    await client.query('SELECT pg_advisory_lock(727001)'); // cegah migrasi ganda bersamaan
    await client.query('CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())');
    const done = new Set((await client.query('SELECT name FROM schema_migrations')).rows.map((r) => r.name));
    for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.sql')).sort()) {
      if (done.has(f)) { log(`- lewati ${f}`); continue; }
      try {
        await client.query('BEGIN');
        await client.query(fs.readFileSync(path.join(dir, f), 'utf8'));
        await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [f]);
        await client.query('COMMIT');
        log(`+ terapkan ${f}`);
      } catch (e) {
        await client.query('ROLLBACK');
        throw new Error(`Migrasi ${f} gagal: ${e.message}`);
      }
    }
  } finally {
    try { await client.query('SELECT pg_advisory_unlock(727001)'); } catch { /* sudah putus */ }
    client.release();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!config.dbConfigured) { console.error('DATABASE_URL belum diisi / masih placeholder.'); process.exit(1); }
  migrate().then(() => console.log('Selesai.')).catch((e) => { console.error(e.message); process.exitCode = 1; }).finally(closePool);
}
`````

### FILE: scripts/seed.js

`````js
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
`````

### FILE: scripts/check-env.js

`````js
// Jalankan: npm run check  -> cek konfigurasi tanpa mencetak rahasia.
import { config, configProblems } from '../src/config.js';

const mark = (ok) => (ok ? 'OK ' : 'BELUM');
console.log(`DATABASE_URL            ${mark(config.dbConfigured)}`);
console.log(`JWT_SECRET (>=32 char)  ${mark(config.jwtOk)}`);
console.log(`CORS_ORIGINS            ${config.corsOrigins.length ? config.corsOrigins.join(', ') : '(kosong)'}`);
console.log(`CRON_SECRET             ${mark(config.cronSecret.length >= 16)}`);
console.log(`GoFood API kredensial   ${mark(config.gofood.apiReady)}`);
console.log(`GoFood notif secret     ${mark(Boolean(config.gofood.notificationSecret))}`);
console.log(`GoFood webhook URL      ${config.gofood.webhookUrl || '(kosong)'}`);
const p = configProblems();
console.log(p.length ? `\nCatatan:\n- ${p.join('\n- ')}` : '\nSemua konfigurasi utama siap.');
`````

### FILE: scripts/mock-gofood-order.js

`````js
// Simulasi webhook GoFood ke server Anda (untuk sandbox/lokal).
// Pakai: GOFOOD_NOTIFICATION_SECRET=xxx node scripts/mock-gofood-order.js http://localhost:8080 [event] [orderNo]
import crypto from 'node:crypto';

const base = (process.argv[2] || 'http://localhost:8080').replace(/\/+$/, '');
const event = process.argv[3] || 'gofood.order.awaiting_merchant_acceptance';
const orderNo = process.argv[4] || `F-${Date.now()}`;
const secret = process.env.GOFOOD_NOTIFICATION_SECRET;
if (!secret) { console.error('Set GOFOOD_NOTIFICATION_SECRET dulu.'); process.exit(1); }

const body = JSON.stringify({
  header: { event_name: event, event_id: crypto.randomUUID(), version: 1, timestamp: new Date().toISOString() },
  body: {
    customer: { id: 'C1', name: 'Dina' }, driver: { name: '' }, service_type: 'gofood',
    outlet: { id: process.env.GOFOOD_OUTLET_ID || 'G123456789', external_outlet_id: 'outlet01' },
    order: {
      status: event.split('.').pop().toUpperCase(), pin: '1234', order_number: orderNo, order_total: 36000,
      order_items: [{ quantity: 2, price: 18000, notes: 'pedas', name: 'Pangsit Original', id: 'uuid-1', external_id: 'pangsit-original', variants: [] }],
      currency: 'IDR', takeaway_charges: 0, created_at: new Date().toISOString(),
    },
  },
});
const sig = crypto.createHmac('sha256', secret).update(body).digest('hex');
const res = await fetch(`${base}/api/webhooks/gofood`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Go-Signature': sig }, body });
console.log(res.status, await res.text());
`````

### FILE: tests/unit.test.js

`````js
import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { crc16, isValidQris } from '../src/lib/qris.js';
import { verifyGoSignature, safeEqual } from '../src/lib/crypto.js';
import { computeTotals, orderDateFromId } from '../src/services/orders.js';
import { normalizeGoFood, matchProduct, mapStatus, baseName } from '../src/services/online.js';
import { passwordSchema, productSchema, settingsSchema, orderInputSchema } from '../src/lib/schemas.js';

const tlv = (tag, val) => tag + String(val.length).padStart(2, '0') + val;
const mkQris = () => {
  const body =
    tlv('00', '01') + tlv('01', '11') +
    tlv('26', tlv('00', 'ID.CO.QRIS.WWW') + tlv('01', 'ID1020000000001') + tlv('02', 'UMI')) +
    tlv('52', '5812') + tlv('53', '360') + tlv('58', 'ID') + tlv('59', 'MIE TEST') + tlv('60', 'JAKARTA') + '6304';
  return body + crc16(body);
};

test('QRIS: CRC valid diterima, diubah ditolak', () => {
  const q = mkQris();
  assert.equal(isValidQris(q), true);
  assert.equal(isValidQris(q.replace('MIE TEST', 'MIE TESX')), false);
  assert.equal(isValidQris('bukan qris'), false);
  assert.equal(isValidQris(''), true);
});

test('Tanda tangan GoBiz: hex & base64 valid, salah/kosong ditolak', () => {
  const raw = Buffer.from('{"a":1}');
  const mac = () => crypto.createHmac('sha256', 's3cret').update(raw);
  const hex = mac().digest('hex');
  const b64 = mac().digest('base64');
  assert.equal(verifyGoSignature(raw, hex, 's3cret'), true);
  assert.equal(verifyGoSignature(raw, b64, 's3cret'), true);
  assert.equal(verifyGoSignature(raw, hex, 'lain'), false);
  assert.equal(verifyGoSignature(Buffer.from('{"a":2}'), hex, 's3cret'), false);
  assert.equal(verifyGoSignature(raw, '', 's3cret'), false);
  assert.equal(verifyGoSignature(raw, hex, ''), false); // secret belum diset => selalu tolak
  assert.equal(safeEqual('a', 'ab'), false);
});

test('Hitung ulang total: diskon dibatasi, tunai & kembalian, metode tak dikenal => cash', () => {
  const items = [{ price: 18000, qty: 2 }, { price: 5000, qty: 1 }];
  let c = computeTotals({ items, discount: 999999, payment: 'cash', paidAmount: 50000 });
  assert.equal(c.subtotal, 41000); assert.equal(c.discount, 41000); assert.equal(c.total, 0);
  c = computeTotals({ items, discount: 1000, payment: 'cash', paidAmount: 50000 });
  assert.equal(c.total, 40000); assert.equal(c.changeAmount, 10000);
  c = computeTotals({ items, discount: 0, payment: 'cash', paidAmount: 1 });
  assert.equal(c.paidAmount, 41000); assert.equal(c.changeAmount, 0); // paidAmount >= total
  c = computeTotals({ items, discount: -5, payment: 'gofood', paidAmount: 0 });
  assert.equal(c.payment, 'cash'); assert.equal(c.discount, 0);
  c = computeTotals({ items, discount: 0, payment: 'qris', paidAmount: 0 });
  assert.equal(c.paidAmount, 41000); assert.equal(c.changeAmount, 0);
  assert.throws(() => computeTotals({ items: [{ price: 100_000_000, qty: 999 }, { price: 100_000_000, qty: 999 }], discount: 0, payment: 'cash' }));
});

test('Tanggal dari nomor struk, fallback UTC createdAt', () => {
  assert.equal(orderDateFromId('MPJ-20261119-48123', '2020-01-01T00:00:00Z'), '2026-11-19');
  assert.equal(orderDateFromId('MPJ-20261399-48123', '2026-05-05T23:00:00Z'), '2026-05-05');
});

test('Skema: sandi, produk, settings, order', () => {
  assert.equal(passwordSchema.safeParse('1234').success, false);
  assert.equal(passwordSchema.safeParse('password').success, false);
  assert.equal(passwordSchema.safeParse('x'.repeat(73)).success, false);
  assert.equal(passwordSchema.safeParse('Sandi-Kuat-2026').success, true);
  assert.equal(productSchema.safeParse({ id: 'a', name: 'Mie', price: -1 }).success, false);
  assert.equal(productSchema.safeParse({ id: 'a', name: 'Mie', price: 1.5 }).success, false);
  assert.equal(productSchema.safeParse({ id: '../x', name: 'Mie', price: 1 }).success, false);
  assert.equal(productSchema.parse({ id: 'a', name: 'Mie', price: 1, evil: 'x' }).evil, undefined);
  assert.equal(settingsSchema.safeParse({ qrisStaticPayload: 'ngawur' }).success, false);
  assert.equal(settingsSchema.safeParse({ taxRate: 11, extra: { nested: 1 } }).success, false);
  const ok = { order: { id: 'MPJ-20261119-48123', clientTxnId: crypto.randomUUID(), createdAt: new Date().toISOString(), items: [{ productId: 'a', name: 'X', price: 1, qty: 1 }] } };
  assert.equal(orderInputSchema.safeParse(ok).success, true);
  assert.equal(orderInputSchema.safeParse({ order: { ...ok.order, items: [] } }).success, false);
  assert.equal(orderInputSchema.safeParse({ order: { ...ok.order, clientTxnId: 'x' } }).success, false);
});

const envelope = (over = {}) => ({
  header: { event_name: 'gofood.order.awaiting_merchant_acceptance', event_id: 'e1', version: 1, timestamp: '2026-11-19T07:00:00+07:00' },
  body: {
    customer: { id: 'c', name: 'Dina' }, driver: { name: '' }, service_type: 'gofood', outlet: { id: 'G1', external_outlet_id: 'o1' },
    order: { status: 'AWAITING_MERCHANT_ACCEPTANCE', pin: '1234', order_number: 'F-2174', order_total: 4e4,
      order_items: [{ quantity: 2, price: 1.8e4, notes: 'pedas', name: 'Pangsit Original (Pedas)', id: 'u1', external_id: 'm1', variants: [{ name: 'Level 2' }] }],
      created_at: '2026-11-19T07:00:00+07:00' }, ...over,
  },
});

test('Normalisasi GoFood & pemetaan status tidak pernah menutup otomatis', () => {
  const ev = normalizeGoFood(envelope());
  assert.equal(ev.partnerOrderId, 'F-2174'); assert.equal(ev.orderType, 'delivery');
  assert.equal(ev.items[0].qty, 2); assert.match(ev.items[0].note, /pedas/); assert.match(ev.items[0].note, /Level 2/);
  assert.equal(normalizeGoFood({ header: { event_name: 'payment.transaction.settlement' }, body: {} }), null);
  assert.equal(normalizeGoFood({}), null);
  assert.equal(mapStatus('AWAITING_MERCHANT_ACCEPTANCE'), 'baru');
  assert.equal(mapStatus('MERCHANT_ACCEPTED'), 'dibuat');
  assert.equal(mapStatus('COMPLETED'), 'siap');
});

test('Pencocokan menu: peta manual > id > nama persis > nama dasar > awalan unik', () => {
  const products = [{ id: 'pangsit-original', name: 'Pangsit Original' }, { id: 'mie-kering', name: 'Mie Kering Ayam' }, { id: 'es-teh', name: 'Es Teh' }, { id: 'es-jeruk', name: 'Es Jeruk' }];
  const none = new Map();
  assert.equal(matchProduct({ partnerMenuId: 'm', name: 'Es Teh' }, products, new Map([['m', { product_id: 'es-jeruk' }]])).productId, 'es-jeruk');
  assert.equal(matchProduct({ partnerMenuId: 'es-teh', name: 'x' }, products, none).productId, 'es-teh');
  assert.equal(matchProduct({ partnerMenuId: 'z', name: 'pangsit  original' }, products, none).productId, 'pangsit-original');
  assert.equal(matchProduct({ partnerMenuId: 'z', name: 'Pangsit Original (Pedas)' }, products, none).productId, 'pangsit-original');
  assert.equal(matchProduct({ partnerMenuId: 'z', name: 'Mie Kering' }, products, none).productId, 'mie-kering');
  assert.equal(matchProduct({ partnerMenuId: 'z', name: 'Es' }, products, none), null); // ambigu
  assert.equal(matchProduct({ partnerMenuId: 'z', name: 'Soto' }, products, none), null);
  assert.equal(baseName('Es Teh - Large'), 'es teh');
});
`````

### FILE: tests/integration.test.js

`````js
// Integrasi penuh ke PostgreSQL sungguhan. Jalankan: TEST_DATABASE_URL=postgresql://... npm run selftest
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const DB = process.env.TEST_DATABASE_URL;
const skip = !DB && 'TEST_DATABASE_URL belum diisi';
const SECRET = 'whsec-test-secret-1234567890';
let server, base, closePool, tokens = {};

const api = async (method, path, { token, body, headers } = {}) => {
  const res = await fetch(base + path, {
    method,
    headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null; try { json = await res.json(); } catch { /* kosong */ }
  return { status: res.status, json };
};
const sign = (raw) => crypto.createHmac('sha256', SECRET).update(raw).digest('hex');
const hook = (event, orderNo, extra = {}, { eventId = crypto.randomUUID(), badSig = false } = {}) => {
  const raw = JSON.stringify({
    header: { event_name: event, event_id: eventId, version: 1, timestamp: new Date().toISOString() },
    body: { customer: { id: 'c', name: 'Dina' }, driver: { name: '' }, service_type: 'gofood', outlet: { id: 'G1', external_outlet_id: 'o1' },
      order: { status: event.split('.').pop().toUpperCase(), pin: '1234', order_number: orderNo, order_total: 36000,
        order_items: [{ quantity: 2, price: 18000, notes: 'pedas', name: 'Pangsit Original', id: 'u1', external_id: 'pangsit-original', variants: [] }],
        created_at: new Date().toISOString(), ...extra } },
  });
  return fetch(`${base}/api/webhooks/gofood`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Go-Signature': badSig ? 'deadbeef' : sign(raw) }, body: raw });
};

before(async () => {
  if (skip) return;
  Object.assign(process.env, {
    DATABASE_URL: DB, JWT_SECRET: 'jwt-secret-for-tests-aaaaaaaaaaaaaaaaaaaaaaaaaaaa'.replace('secret', 'k3y'),
    GOFOOD_NOTIFICATION_SECRET: SECRET, GOFOOD_OUTLET_ID: 'G1', CRON_SECRET: 'cron-secret-1234567890', NODE_ENV: 'test',
  });
  const { migrate } = await import('../scripts/migrate.js');
  const { seed } = await import('../scripts/seed.js');
  const db = await import('../src/db.js');
  closePool = db.closePool;
  await migrate(() => {});
  await db.query('TRUNCATE users, products, categories, settings, transactions, transaction_items, pending_orders, online_orders, stock_movements, audit_log, online_menu_map, webhook_events, online_order_actions, rate_limits RESTART IDENTITY CASCADE');
  await seed({ SEED_OWNER_PASSWORD: 'Pemilik-Kuat-2026', SEED_CASHIER_PASSWORD: 'Kasir-Kuat-2026' }, () => {});
  const { default: app } = await import('../src/index.js');
  await new Promise((r) => { server = app.listen(0, r); });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => { if (server) await new Promise((r) => server.close(r)); if (closePool) await closePool(); });

test('health 200 & tidak membocorkan konfigurasi', { skip }, async () => {
  const r = await api('GET', '/api/health');
  assert.equal(r.status, 200); assert.equal(r.json.db, 'up');
  assert.deepEqual(Object.keys(r.json).sort(), ['db', 'ok', 'time']);
});

test('auth: login salah, rate limit, login benar, token palsu/alg none ditolak', { skip }, async () => {
  assert.equal((await api('POST', '/api/auth/login', { body: { username: 'pemilik', password: 'salah-salah' } })).status, 401);
  assert.equal((await api('POST', '/api/auth/login', { body: { username: 'tidakada', password: 'salah-salah' } })).status, 401);
  const o = await api('POST', '/api/auth/login', { body: { username: 'pemilik', password: 'Pemilik-Kuat-2026' } });
  const k = await api('POST', '/api/auth/login', { body: { username: 'kasir', password: 'Kasir-Kuat-2026' } });
  assert.equal(o.status, 200); assert.equal(k.json.user.role, 'Kasir');
  tokens = { owner: o.json.token, cashier: k.json.token };
  assert.equal((await api('GET', '/api/auth/me', { token: tokens.owner })).json.user.username, 'pemilik');
  assert.equal((await api('GET', '/api/auth/me')).status, 401);
  assert.equal((await api('GET', '/api/auth/me', { token: 'aaaa.bbbb.cccc' })).status, 401);
  const none = `${Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url')}.${Buffer.from('{"sub":"1","tv":0}').toString('base64url')}.`;
  assert.equal((await api('GET', '/api/auth/me', { token: none })).status, 401);
  // 8 gagal per (ip,user) lalu 429
  let last;
  for (let i = 0; i < 9; i++) last = await api('POST', '/api/auth/login', { body: { username: 'kasir', password: 'salah-salah' } });
  assert.equal(last.status, 429);
  assert.equal((await api('POST', '/api/auth/login', { body: { username: 'kasir', password: 'Kasir-Kuat-2026' } })).status, 429);
});

test('RBAC: kasir tidak boleh push katalog/kelola user/hapus transaksi', { skip }, async () => {
  const prod = { table: 'products', rows: [{ id: 'pangsit-original', payload: { name: 'Pangsit Original', price: 18000, stock: 10 } }] };
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.cashier, body: prod })).status, 403);
  assert.equal((await api('GET', '/api/users', { token: tokens.cashier })).status, 403);
  assert.equal((await api('DELETE', '/api/orders/MPJ-20261119-00001', { token: tokens.cashier })).status, 403);
  assert.equal((await api('GET', '/api/sync/tables', { token: tokens.cashier })).json.tables.length, 6);
});

test('sync push/pull: katalog, validasi, tabel orders ditolak, tombstone, kursor', { skip }, async () => {
  const rows = [
    { id: 'pangsit-original', payload: { name: 'Pangsit Original', category: 'Mie Pangsit Jakarta', price: 18000, stock: 10, emoji: '🥟' } },
    { id: 'es-teh', payload: { name: 'Es Teh', price: 5000, stock: null } },
  ];
  const p = await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'products', rows, deviceId: 'dev-1' } });
  assert.equal(p.status, 200); assert.equal(p.json.accepted, 2);
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'products', rows: [{ id: 'x', payload: { name: 'Bad', price: -5 } }] } })).status, 400);
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'orders', rows: [{ id: 'x', payload: {} }] } })).json.error, 'unknown_table');
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'users', rows: [{ id: 'x', payload: {} }] } })).json.error, 'unknown_table');
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: '__proto__', rows: [{ id: 'x', payload: {} }] } })).json.error, 'unknown_table');
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'settings', rows: [{ id: 'main', payload: { businessName: 'Mie Pangsit', taxRate: 11 } }] } })).status, 200);
  const pull = await api('GET', '/api/sync/pull?table=products', { token: tokens.cashier });
  assert.equal(pull.json.rows.length, 2);
  const again = await api('GET', `/api/sync/pull?table=products&since=${encodeURIComponent(pull.json.cursor.since)}&sinceId=${pull.json.cursor.sinceId}`, { token: tokens.cashier });
  assert.equal(again.json.rows.length, 0);
  assert.equal((await api('GET', '/api/sync/pull?table=products&since=bukan-tanggal', { token: tokens.cashier })).status, 400);
  assert.equal((await api('GET', "/api/sync/pull?table=products';DROP TABLE users;--", { token: tokens.cashier })).status, 400);
  assert.equal((await api('POST', '/api/sync/push', { token: tokens.owner, body: { table: 'categories', rows: [{ id: 'nonexist', deleted: true }] } })).status, 200);
});

test('transaksi: harga dihitung ulang server, stok turun, idempoten, validasi', { skip }, async () => {
  const order = {
    id: 'MPJ-20261119-11111', clientTxnId: crypto.randomUUID(), createdAt: new Date().toISOString(), orderType: 'dine-in', tableNumber: '3',
    items: [{ productId: 'pangsit-original', name: 'HARGA PALSU', price: 1, qty: 2 }, { productId: 'es-teh', name: 'Es Teh', price: 99999, qty: 1 }],
    discount: 1000, payment: 'cash', paidAmount: 50000,
  };
  const r = await api('POST', '/api/orders', { token: tokens.cashier, body: { order, deviceId: 'dev-1' } });
  assert.equal(r.status, 201, JSON.stringify(r.json));
  assert.equal(r.json.order.subtotal, 41000); assert.equal(r.json.order.total, 40000); assert.equal(r.json.order.changeAmount, 10000);
  assert.equal(r.json.order.items[0].name, 'Pangsit Original'); assert.equal(r.json.order.taxRate, 11);
  const dup = await api('POST', '/api/orders', { token: tokens.cashier, body: { order } });
  assert.equal(dup.status, 200); assert.equal(dup.json.duplicate, true);
  const dup2 = await api('POST', '/api/orders', { token: tokens.cashier, body: { order: { ...order, id: 'MPJ-20261119-22222' } } }); // clientTxnId sama
  assert.equal(dup2.json.duplicate, true);
  // race: 5 permintaan kembar bersamaan => tepat 1 baris
  const o2 = { ...order, id: 'MPJ-20261119-33333', clientTxnId: crypto.randomUUID() };
  const rs = await Promise.all(Array.from({ length: 5 }, () => api('POST', '/api/orders', { token: tokens.cashier, body: { order: o2 } })));
  assert.equal(rs.filter((x) => x.json?.duplicate === false).length, 1); assert.ok(rs.every((x) => x.status < 300));
  const prods = await api('GET', '/api/sync/pull?table=products', { token: tokens.cashier });
  const po = prods.json.rows.find((x) => x.id === 'pangsit-original');
  assert.equal(po.payload.stock, 6); // 10 - 2 - 2 (dua transaksi unik)
  const et = prods.json.rows.find((x) => x.id === 'es-teh');
  assert.equal(et.payload.stock, null); // tanpa batas tidak berubah
  const bad = await api('POST', '/api/orders', { token: tokens.cashier, body: { order: { ...order, id: 'x', clientTxnId: crypto.randomUUID() } } });
  assert.equal(bad.status, 400);
  const pull = await api('GET', '/api/sync/pull?table=orders', { token: tokens.cashier });
  assert.equal(pull.json.rows.length, 2); assert.equal(pull.json.rows[0].payload.items.length, 2);
});

test('stok tidak boleh negatif & konflik tercatat', { skip }, async () => {
  const o = { id: 'MPJ-20261119-44444', clientTxnId: crypto.randomUUID(), createdAt: new Date().toISOString(), items: [{ productId: 'pangsit-original', name: 'x', price: 1, qty: 50 }], payment: 'qris' };
  assert.equal((await api('POST', '/api/orders', { token: tokens.cashier, body: { order: o } })).status, 201);
  const { query } = await import('../src/db.js');
  assert.equal((await query(`SELECT stock FROM products WHERE id='pangsit-original'`)).rows[0].stock, 0);
  assert.equal((await query(`SELECT count(*)::int n FROM audit_log WHERE action='stock.conflict'`)).rows[0].n, 1);
});

test('hapus transaksi: hanya Pemilik, soft delete, stok TIDAK kembali, tombstone di pull', { skip }, async () => {
  const d = await api('DELETE', '/api/orders/MPJ-20261119-11111', { token: tokens.owner });
  assert.equal(d.status, 200); assert.equal(d.json.stockRestored, false);
  assert.equal((await api('DELETE', '/api/orders/MPJ-20261119-11111', { token: tokens.owner })).status, 404);
  const { query } = await import('../src/db.js');
  assert.equal((await query(`SELECT stock FROM products WHERE id='pangsit-original'`)).rows[0].stock, 0);
  const pull = await api('GET', '/api/sync/pull?table=orders', { token: tokens.owner });
  const t = pull.json.rows.find((x) => x.id === 'MPJ-20261119-11111');
  assert.equal(t.deleted, true); assert.deepEqual(t.payload, { id: 'MPJ-20261119-11111' });
});

test('webhook: tanda tangan salah ditolak & dicatat; benar diterima; duplikat tidak menggandakan', { skip }, async () => {
  const { query } = await import('../src/db.js');
  const bad = await hook('gofood.order.awaiting_merchant_acceptance', 'F-1', {}, { badSig: true });
  assert.equal(bad.status, 401);
  const rej = (await query(`SELECT signature_ok, status, raw FROM webhook_events WHERE status='rejected' ORDER BY id DESC LIMIT 1`)).rows[0];
  assert.equal(rej.signature_ok, false); assert.equal(rej.raw, null);

  const eid = crypto.randomUUID();
  const ok = await hook('gofood.order.awaiting_merchant_acceptance', 'F-2174', {}, { eventId: eid });
  assert.equal(ok.status, 200); assert.equal((await ok.json()).status, 'accepted');
  const dup = await hook('gofood.order.awaiting_merchant_acceptance', 'F-2174', {}, { eventId: eid });
  assert.equal((await dup.json()).status, 'duplicate');
  assert.equal((await query(`SELECT count(*)::int n FROM online_orders WHERE id='ONL-GF-F-2174'`)).rows[0].n, 1);
  assert.equal((await query(`SELECT count(*)::int n FROM webhook_events WHERE status='duplicate'`)).rows[0].n, 1);
  const o = (await query(`SELECT payload FROM online_orders WHERE id='ONL-GF-F-2174'`)).rows[0].payload;
  assert.equal(o.status, 'baru'); assert.equal(o.items[0].productId, 'pangsit-original'); assert.equal(o.unmappedItems.length, 0);
  assert.equal((await fetch(`${base}/api/webhooks/grab`, { method: 'POST', body: '{}' })).status, 404);
  assert.equal((await fetch(`${base}/api/webhooks/gofood`, { method: 'POST', headers: { 'X-Go-Signature': sign('') } , body: '' })).status, 400);
  // outlet lain diabaikan
  const raw = JSON.stringify({ header: { event_name: 'gofood.order.created', event_id: 'zz1' }, body: { outlet: { id: 'LAIN' }, service_type: 'gofood', order: { order_number: 'F-9', order_items: [], status: 'CREATED' } } });
  const other = await fetch(`${base}/api/webhooks/gofood`, { method: 'POST', headers: { 'X-Go-Signature': sign(raw), 'Content-Type': 'application/json' }, body: raw });
  assert.equal((await other.json()).status, 'ignored');
});

test('status online: tidak mundur oleh webhook; transisi kasir mengantrekan aksi (tanpa ganda)', { skip }, async () => {
  const { query } = await import('../src/db.js');
  const cur = (await query(`SELECT payload FROM online_orders WHERE id='ONL-GF-F-2174'`)).rows[0].payload;
  const up = { ...cur, status: 'dibuat' };
  const push = () => api('POST', '/api/sync/push', { token: tokens.cashier, body: { table: 'online_orders', rows: [{ id: cur.id, payload: up }], deviceId: 'dev-1' } });
  assert.equal((await push()).status, 200); await push();
  let acts = (await query(`SELECT action, status FROM online_order_actions WHERE order_id=$1`, [cur.id])).rows;
  assert.deepEqual(acts.map((a) => a.action), ['accept']); // GoFood belum dikonfigurasi => tetap 'queued'
  await hook('gofood.order.awaiting_merchant_acceptance', 'F-2174'); // webhook lama datang terlambat
  assert.equal((await query(`SELECT payload->>'status' s FROM online_orders WHERE id=$1`, [cur.id])).rows[0].s, 'dibuat');
  await api('POST', '/api/sync/push', { token: tokens.cashier, body: { table: 'online_orders', rows: [{ id: cur.id, payload: { ...cur, status: 'siap' } }] } });
  acts = (await query(`SELECT action FROM online_order_actions WHERE order_id=$1 ORDER BY id`, [cur.id])).rows.map((a) => a.action);
  assert.deepEqual(acts, ['accept', 'ready']);
  // tolak pesanan baru (status lama 'baru') => reject; pesanan yang sudah diterima => tidak mengirim apa pun
  await hook('gofood.order.awaiting_merchant_acceptance', 'F-3000');
  await api('POST', '/api/sync/push', { token: tokens.cashier, body: { table: 'online_orders', rows: [{ id: 'ONL-GF-F-3000', deleted: true }] } });
  await api('POST', '/api/sync/push', { token: tokens.cashier, body: { table: 'online_orders', rows: [{ id: cur.id, deleted: true }] } });
  const all = (await query(`SELECT order_id, action FROM online_order_actions WHERE action='reject'`)).rows;
  assert.deepEqual(all, [{ order_id: 'ONL-GF-F-3000', action: 'reject' }]);
  // pesanan yang sudah ditutup tidak dihidupkan lagi oleh webhook susulan
  await hook('gofood.order.merchant_accepted', 'F-3000');
  assert.equal((await query(`SELECT deleted FROM online_orders WHERE id='ONL-GF-F-3000'`)).rows[0].deleted, true);
});

test('pengguna: buat, pemilik terakhir terlindungi, ganti sandi mencabut token lama', { skip }, async () => {
  assert.equal((await api('POST', '/api/users', { token: tokens.owner, body: { username: 'Kasir2', displayName: 'Kasir 2', role: 'Kasir', password: '1234' } })).status, 400);
  const c = await api('POST', '/api/users', { token: tokens.owner, body: { username: 'Kasir2', displayName: 'Kasir 2', role: 'Kasir', password: 'Kasir2-Kuat-2026' } });
  assert.equal(c.status, 201); assert.equal(c.json.user.username, 'kasir2'); assert.equal(c.json.user.passwordHash, undefined);
  assert.equal((await api('POST', '/api/users', { token: tokens.owner, body: { username: 'kasir2', displayName: 'x', role: 'Kasir', password: 'Kasir2-Kuat-2026' } })).status, 409);
  const me = await api('GET', '/api/auth/me', { token: tokens.owner });
  const last = await api('PUT', `/api/users/${me.json.user.id}`, { token: tokens.owner, body: { active: false } });
  assert.equal(last.status, 409); assert.equal(last.json.error, 'last_owner');
  assert.equal((await api('PUT', `/api/users/${me.json.user.id}`, { token: tokens.owner, body: { role: 'Kasir' } })).status, 409);
  const login = await api('POST', '/api/auth/login', { body: { username: 'kasir2', password: 'Kasir2-Kuat-2026' } });
  const oldTok = login.json.token;
  const ch = await api('POST', '/api/auth/change-password', { token: oldTok, body: { currentPassword: 'Kasir2-Kuat-2026', newPassword: 'Kasir2-Baru-2026' } });
  assert.equal(ch.status, 200);
  assert.equal((await api('GET', '/api/auth/me', { token: oldTok })).status, 401); // token lama mati
  assert.equal((await api('GET', '/api/auth/me', { token: ch.json.token })).status, 200);
  await api('PUT', `/api/users/${c.json.user.id}`, { token: tokens.owner, body: { active: false } });
  assert.equal((await api('GET', '/api/auth/me', { token: ch.json.token })).status, 401); // nonaktif => langsung mati
});

test('cron: butuh CRON_SECRET; online/config tidak membocorkan rahasia', { skip }, async () => {
  assert.equal((await api('GET', '/api/cron/maintenance')).status, 401);
  assert.equal((await api('GET', '/api/cron/maintenance', { headers: { Authorization: 'Bearer salah' } })).status, 401);
  const ok = await api('GET', '/api/cron/maintenance', { headers: { Authorization: 'Bearer cron-secret-1234567890' } });
  assert.equal(ok.status, 200);
  const cfg = await api('GET', '/api/online/config', { token: tokens.owner });
  const s = JSON.stringify(cfg.json);
  assert.ok(!s.includes(SECRET) && !s.includes('clientSecret'));
  const ev = await api('GET', '/api/online/webhooks', { token: tokens.owner });
  assert.ok(ev.json.events.length > 0); assert.equal(ev.json.events[0].raw, undefined);
});

test('keamanan HTTP: header, JSON rusak, content-type, ukuran, 404', { skip }, async () => {
  const r = await fetch(`${base}/api/health`);
  assert.equal(r.headers.get('x-powered-by'), null);
  assert.equal(r.headers.get('cache-control'), 'no-store');
  assert.ok(r.headers.get('strict-transport-security'));
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  const bad = await fetch(`${base}/api/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{rusak' });
  assert.equal(bad.status, 400);
  const ct = await fetch(`${base}/api/auth/login`, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: 'x' });
  assert.equal(ct.status, 415);
  const big = await fetch(`${base}/api/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ a: 'x'.repeat(3 * 1024 * 1024) }) });
  assert.equal(big.status, 413);
  assert.equal((await api('GET', '/api/tidak-ada')).status, 404);
  const cors = await fetch(`${base}/api/health`, { headers: { Origin: 'https://jahat.example' } });
  assert.equal(cors.headers.get('access-control-allow-origin'), null);
});
`````
