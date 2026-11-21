# PRD — iPo Mie Pangsit (POS Kasir + Integrasi Online)

**Versi dokumen:** 1.0  
**Tanggal:** 19 November 2026  
**Status:** Dokumen deskripsi produk berdasarkan kode yang **benar-benar ada** di repository (`www/`, `server/`, `android/`)  
**Sumber kebenaran:** kode sumber, migrasi SQL, dan dokumentasi di `server/README.md`, `migration/GOFOOD-INTEGRATION.md`

> Cara baca status: ✅ sudah terimplementasi · ⚠️ sudah ada kode tapi belum aktif/terbatas · ❌ belum ada / sengaja tidak dibuat.

---

## 1. Ringkasan eksekutif

iPo Mie Pangsit adalah aplikasi kasir **offline-first** untuk warung Mie Pangsit Jakarta yang berjalan di:

1. **Browser / PWA** — `www/pos.html`, dipakai untuk uji dan bisa dipasang di HP/tablet.
2. **APK Android** — pembungkus Capacitor 8 dari folder `www` yang sama, dengan plugin native untuk cetak struk Bluetooth.
3. **Backend opsional** — Node + Express + PostgreSQL (Neon) untuk sinkronisasi antar-perangkat, akun terpusat, dan penerima webhook GoFood.

Data transaksi **tetap bisa dibuat tanpa server**. Server dibutuhkan hanya untuk sinkronisasi, akun terpusat, dan pesanan online. Saat ini backend bisa berjalan tetapi **database belum terhubung** (`DATABASE_URL` masih placeholder), jadi fitur bergantung database masih belum aktif.

---

## 2. Tujuan produk

| Tujuan | Penjelasan |
|---|---|
| Kasir cepat & tetap jalan offline | Transaksi dibuat, disimpan, dan dicetak tanpa internet |
| Rekap omzet yang bisa dipertanggungjawabkan | Laporan harian/mingguan/rentang, export Excel |
| QRIS tanpa gateway | QRIS statis warung diubah jadi QRIS dinamis bernominal di perangkat |
| Data tidak hilang | Satu cadangan lokal + file backup JSON + salinan server lewat sinkronisasi |
| Pesanan mitra masuk ke satu alur | GoFood masuk sebagai pesanan online di panel kasir yang sama |
| Aman | Kredensial database tidak pernah ada di aplikasi; aksi pemilik dibatasi |

---

## 3. Pengguna & izin

| Peran | Hak akses |
|---|---|
| **Pemilik** | Semua menu: Dashboard, Kasir, Menu, Laporan, Pengaturan. Boleh tambah/edit menu & kategori, atur QRIS/printer/server, kelola pengguna, export/import backup, hapus cadangan, hapus transaksi, bersihkan riwayat |
| **Kasir** | Dashboard, Kasir, Laporan. Boleh transaksi, simpan pesanan "Bayar nanti", ubah status pesanan online, cetak struk. **Tidak** bisa membuka Menu/Pengaturan dan aksi owner-only |

Aturan tambahan:
- ✅ Harus ada minimal **satu akun Pemilik aktif**; akun pemilik terakhir tidak boleh dinonaktifkan/diturunkan perannya.
- ✅ Sesi berakhir otomatis **saat pergantian hari lokal** (bukan idle timeout).
- ✅ Mode lokal: akun bawaan `pemilik`/`1234` dan `kasir`/`1234` — **sandi default ini wajib diganti sebelum dipakai sungguhan**.
- ✅ Mode server: login divalidasi backend, token JWT disimpan di perangkat; password di server di-hash bcrypt cost 12.

---

## 4. Fitur & requirement

### 4.1 Dashboard ✅
- Kartu ringkasan: omzet hari ini, jumlah transaksi, dll.
- Daftar transaksi terakhir + pintasan ke Kasir dan Menu.
- Indikator status sinkronisasi (`Lokal` / `Tersinkron` / error) dan tombol sinkron manual.

### 4.2 Kasir ✅
**Katalog & keranjang**
- Kartu menu dikelompokkan per kategori (Mie Pangsit Jakarta, Mie Kering, Special menu, Topping, Minuman).
- Katalog bawaan 25 menu dengan harga dan emoji; bisa ditambah/diubah pemilik.
- Keranjang menyimpan: produk, qty, harga satuan (snapshot), catatan item, diskon, jenis pesanan, nomor meja, catatan.
- Jenis pesanan: `Makan di tempat` (minta nomor meja) atau `Bawa pulang`.
- Keranjang tersimpan di perangkat sehingga tetap ada setelah refresh.
- ✅ **Perilaku khusus:** menekan kartu menu saat panel berada di tab **Bayar nanti/Online** otomatis memindahkan panel ke tab **Keranjang**.

**Perhitungan**
- `subtotal = Σ(harga satuan × qty)`
- `diskon` dibatasi `0 … subtotal`
- `total = subtotal − diskon`
- ✅ PPN dicatat sebagai **metadata** (`taxRate` default 11, `taxIncluded: true`), **tidak ditambahkan** ke total.
- Server menghitung ulang subtotal/diskon/total dari harga produk di database; nilai dari klien tidak dipercaya.
- ✅ Kembalian dihitung dari uang diterima; konfirmasi "uang sudah diterima?" sebelum transaksi lunas.

**Pembayaran ✅**
| Metode | Perilaku |
|---|---|
| Tunai | Input uang diterima, kembalian otomatis, wajib konfirmasi |
| QRIS dinamis | QR dibuat offline dari string QRIS statis + nominal; kasir konfirmasi pembayaran muncul di HP pelanggan. Jika QRIS belum diatur → mode simulasi dengan pemberitahuan |
| Transfer | Catat manual, konfirmasi pembayaran |
| Kartu | Catat manual (EDC di luar aplikasi) |

- ✅ Transaksi selesai langsung masuk riwayat + struk (`status: paid`), **tidak** masuk antrean "Bayar nanti".
- ✅ Tombol **⏸ Simpan nanti** membuat entri belum bayar di tab **Bayar nanti**; bisa dilanjutkan, dibatalkan, atau ditandai selesai dibuat.

**Stok ✅**
- Stok bertipe nullable; `null` = tanpa batas.
- ✅ Stok dikurangi saat transaksi lunas, dibatasi minimum 0.
- ✅ **Aturan bisnis tetap:** menghapus transaksi **tidak mengembalikan stok** (soft delete + audit di server; perubahan stok dicatat di `stock_movements` alasan `sale`).

**Struk ✅**
- Ukuran kertas 58 mm / 80 mm / A4, footer struk bisa diatur.
- ✅ Android: kirim ESC/POS ke printer thermal Bluetooth melalui plugin native `BluetoothThermal` (iware X58BT II / MP58).
- ✅ Browser / tanpa printer: dialog cetak bawaan.
- Bisa cetak ulang struk dari detail pesanan.

### 4.3 QRIS ✅
- ✅ Pengaturan → Pembayaran berisi tombol **📷 Baca dari foto QRIS** + kolom string QRIS statis.
- ✅ Decoder QR (`jsQR`) berjalan **lokal di perangkat**; foto tidak diunggah. Batas 12 MB, beberapa skala resolusi, `inversionAttempts: attemptBoth`.
- ✅ Hanya payload yang **valid QRIS** (struktur TLV EMVCo + CRC16 cocok) yang mengisi textarea. QR lain ditolak, textarea tidak berubah. Gambar tanpa QR → pesan "QR tidak terbaca".
- ✅ String bisa juga ditempel manual; validasi sama. Nama merchant ditampilkan otomatis.
- ✅ QRIS dinamis dibuat dengan mengubah tag `01` menjadi `12`, menambahkan tag `54` (nominal), dan menghitung ulang CRC — tanpa Midtrans/gateway.

### 4.4 Pesanan online ✅ (backend) / ⚠️ (frontend)
- ✅ Panel kasir memiliki tab **Online** dengan status: **Baru → Dibuat → Siap diambil → Selesai**. Tombol mundur status tersedia untuk koreksi.
- ✅ Tolak/batalkan pesanan dengan alasan (default: "Mohon maaf stok habis"); pesanan dihapus dari daftar lokal, dan untuk GoFood aksi `reject` dikirim ke server jika alamat API + token tersedia. Tidak ada pengembalian stok otomatis di alur ini — stok baru berkurang saat pesanan online selesai menjadi transaksi.
- ✅ Saat pesanan online selesai, transaksi tercatat di laporan dengan `orderType: online`.
- ✅ Ada data contoh (dummy) jika belum ada pesanan asli; ini **bukan** pesanan sungguhan.
- ⚠️ Backend menerima webhook, menyimpan **raw event** di `webhook_events`, menormalisasi ke `online_orders`, memetakan menu mitra → produk, dan mengantrekan aksi balik di `online_order_actions` (`accept`/`reject`/`ready`).
- ✅ GoFood: adapter GoBiz (OAuth2, linked outlets, subscription notifikasi, verifikasi tanda tangan `X-Go-Signature` dengan secret, idempotency key `X-Go-Idempotency-Key`).
- ❌ GrabFood/ShopeeFood: hanya dikenal sebagai `source` dan dinormalisasi; **adapter Penguin/GoBiz tidak dibuat** (sesuai keputusan: ditunda).
- ❌ Midtrans tidak dipakai.

### 4.5 Laporan ✅
- Filter rentang tanggal, preset **Harian** dan **Mingguan**.
- ✅ Export `.xlsx` dibuat di perangkat (tanpa library server); di APK dibagikan lewat plugin native, di browser diunduh.
- Nama file contoh: `mpj-laporan-harian-2026-11-19-2026-11-19.xlsx`.

### 4.6 Pengaturan ✅
Lima tab: **Toko**, **Pembayaran**, **Printer & struk**, **Server & cadangan**, **Pengguna**.
- **Toko:** nama, alamat, nomor telepon (muncul di struk).
- **Pembayaran:** QRIS + alasan penolakan pesanan online.
- **Printer & struk:** ukuran kertas, footer, pemilihan perangkat Bluetooth, test cetak.
- **Server & cadangan:** alamat API, status sinkron, sinkron manual, **satu** cadangan lokal, download/import backup JSON, hapus cadangan per baris, bersihkan riwayat pembelian.
- **Pengguna:** daftar akun, tambah/edit, aktif/nonaktifkan, ganti sandi.

**Aturan cadangan ( ✅ )**
- ✅ **Satu** snapshot lokal saja; yang lama otomatis diganti. Perangkat dengan 6 snapshot lama dirapikan saat aplikasi dibuka.
- ✅ Setiap baris cadangan punya tombol **Kembalikan** dan **Hapus**; **Hapus menghapus satu cadangan saja**, bukan semua, dengan konfirmasi.
- ✅ Ukuran cadangan ditampilkan (KB). Batas: 600 KB per snapshot, total 1,2 MB, pangkas otomatis jika penyimpanan mendekati 4 MB.
- ✅ Download backup JSON disarankan minimal seminggu sekali; stamp waktu unduhan ditampilkan.
- ✅ **Bersihkan riwayat** hanya menghapus transaksi, "Pesanan dibuat", dan online — menu, pengaturan, keranjang, backup, dan snapshot tidak disentuh.

### 4.7 Sinkronisasi ✅ (kode ada, belum aktif)
- Tabel tersinkron: `products`, `categories`, `settings`, `orders`, `pending_orders`, `online_orders`.
- Outbox di **IndexedDB** (`ipos_local`, store `outbox`/`meta`) dengan status `pending | syncing | synced | failed`, retry backoff maksimal 5 menit.
- Push debounce 1,5 detik; pull setiap 45 detik; timeout 20 detik; batas 1000 baris per pull.
- Endpoint: `POST /api/sync/push`, `GET /api/sync/pull`, `GET /api/sync/tables`.
- Konflik: baris remote menang berdasarkan `updated_at`; identitas warung kosong dari cloud tidak menghapus isian lokal.
- ✅ Perubahan di tab lain terdeteksi lewat event `storage`.
- ⚠️ Default `DEFAULT_API_BASE = ''` → **mode lokal**. Sinkron aktif setelah alamat server diisi di Pengaturan dan login server berhasil.

---

## 5. Arsitektur & teknologi

| Lapisan | Teknologi |
|---|---|
| Web | HTML, CSS, JavaScript vanilla (IIFE), tanpa framework/bundler |
| Penyimpanan perangkat | `localStorage` (data POS), `IndexedDB` (outbox sinkron) |
| Offline | Service worker `sw.js`, cache `mpj-pos-v105`, fallback navigation ke `pos.html` |
| QR | `qris.js` (TLV/CRC), `qrcode.js` (generator), `jsQR.js` (decoder foto) |
| Android | Capacitor 8.5.3 (`@capacitor/core`, `@capacitor/cli`, `@capacitor/android`), Java native plugin |
| Android SDK | minSdk 24, compile/targetSdk 36, AndroidX 1.x |
| Backend | Node ≥18, Express 4.19, `pg`, `jsonwebtoken`, `bcryptjs`, `cors`, `express-rate-limit`, `dotenv` |
| Database | PostgreSQL (Neon), migrasi SQL idempoten, `pgcrypto` untuk UUID |
| Deploy backend | Docker `node:20-alpine` (port 8080) |
| Alat uji | `npm run selftest`, `migration/postman/GoFood.postman_collection.json`, `scripts/mock-gofood-order.js` |

**Struktur database (13 tabel):** `users`, `categories`, `products`, `settings`, `transactions`, `transaction_items`, `pending_orders`, `online_orders`, `stock_movements`, `audit_log`, `online_menu_map`, `webhook_events`, `online_order_actions`. Definisi kolom, ERD, payload, dan alur tulisnya ada di **Bagian 6**.

**Endpoint API:**
`/api/health`, `/api/auth/{login,me,change-password}`, `/api/users`, `/api/sync/{push,pull,tables}`, `/api/orders`, `/api/webhooks/:source`, `/api/online/{config,orders,menu-map,actions,webhooks,gofood/cek,gofood/langganan}`.

---

## 6. Struktur data backend

Bagian ini mendeskripsikan **struktur data yang benar-benar ada** di server, bukan rencana. Sumber kebenarannya adalah `server/migrations/001_init.sql`, `server/migrations/002_online_integration.sql`, `server/src/services/{sync,orders,online}.js`, dan `server/src/routes/sync.js`.

### 6.1 Tiga lapis data

| Lapis | Tempat | Bentuk | Peran |
|---|---|---|---|
| 1. Perangkat | `localStorage` (`mpj_pos_*`) | objek/array JavaScript | Sumber kebenaran saat kasir offline |
| 2. Antrean | IndexedDB `ipos_local` (`outbox`, `meta`) | `{ table, id, payload, deleted, deviceId }` | Menampung perubahan sebelum dikirim; retry backoff maks. 5 menit |
| 3. Server | PostgreSQL (Neon) | 13 tabel | Salinan bersama, audit, webhook, antrean aksi mitra |

Prinsipnya **local-first**: kasir tidak pernah menunggu jaringan. Saat pull, baris dengan `updated_at` lebih baru dari server menang. Pengecualian: field identitas warung yang kosong dari cloud tidak menghapus isian lokal.

### 6.2 Diagram relasi (ERD)

```mermaid
erDiagram
    users                ||--o{ audit_log            : "actor (logical)"
    transactions         ||--|{ transaction_items    : "transaction_id FK ON DELETE CASCADE"
    transactions         }o--|| settings             : "tax_rate dibaca (logical)"
    products             ||--o{ stock_movements      : "product_id (logical)"
    products             ||--o{ online_menu_map      : "product_id FK ON DELETE SET NULL"
    online_orders        ||--o{ online_order_actions : "order_id (logical)"
    online_orders        ||--o{ webhook_events       : "entity_id (logical)"

    users {
      BIGSERIAL id PK
      TEXT username UK "unique, login"
      TEXT display_name
      TEXT role "Pemilik|Kasir"
      TEXT password_hash "bcrypt cost 12"
      BOOLEAN active "default true"
      TIMESTAMPTZ created_at
      TIMESTAMPTZ updated_at
    }
    categories {
      TEXT id PK
      JSONB payload "id, emoji, label"
      TIMESTAMPTZ updated_at
      BOOLEAN deleted "tombstone"
      TEXT device_id
    }
    products {
      TEXT id PK
      TEXT name
      TEXT category_id "tanpa FK"
      INTEGER price ">= 0"
      INTEGER stock "NULL = tanpa batas"
      BOOLEAN available "default true"
      TEXT description
      TEXT emoji
      JSONB payload "bentuk lengkap untuk klien"
      TIMESTAMPTZ updated_at
      BOOLEAN deleted
      TEXT device_id
    }
    settings {
      TEXT id PK "selalu 'main'"
      JSONB payload "default kosong"
      TIMESTAMPTZ updated_at
      BOOLEAN deleted
      TEXT device_id
    }
    transactions {
      TEXT id PK "format MPJ-YYYYMMDD-xxxxx"
      UUID client_txn_id UK "idempotency"
      TIMESTAMPTZ created_at
      DATE order_date
      TEXT order_type
      TEXT table_number
      INTEGER subtotal ">= 0"
      INTEGER discount ">= 0"
      NUMERIC tax_rate "default 0"
      INTEGER total ">= 0"
      TEXT payment "cash|qris|transfer|card"
      INTEGER paid_amount
      INTEGER change_amount
      TEXT status "default paid"
      TEXT cashier
      TEXT note
      TEXT device_id
      TIMESTAMPTZ updated_at
      BOOLEAN deleted "tombstone"
    }
    transaction_items {
      BIGSERIAL id PK
      TEXT transaction_id FK "CASCADE"
      TEXT product_id
      TEXT name "snapshot"
      INTEGER price "snapshot, >= 0"
      INTEGER qty "> 0"
      INTEGER total ">= 0"
      TEXT note
    }
    pending_orders {
      TEXT id PK "HOLD-YYYYMMDD-xxxxx"
      JSONB payload "pesanan belum bayar"
      TIMESTAMPTZ updated_at
      BOOLEAN deleted
      TEXT device_id
    }
    online_orders {
      TEXT id PK "format ONL-prefix-idMitra"
      JSONB payload "pesanan mitra"
      TIMESTAMPTZ updated_at
      BOOLEAN deleted "tombstone = tutup pesanan"
      TEXT device_id
    }
    stock_movements {
      BIGSERIAL id PK
      TEXT product_id
      INTEGER qty "negatif = keluar"
      TEXT reason "sale|restock|adjust|reconcile"
      TEXT ref
      TEXT device_id
      TIMESTAMPTZ created_at
    }
    audit_log {
      BIGSERIAL id PK
      TEXT actor
      TEXT action
      TEXT target
      JSONB detail
      TIMESTAMPTZ created_at
    }
    online_menu_map {
      TEXT id PK "format source:partnerMenuId"
      TEXT source "gofood|grab|shopee"
      TEXT partner_menu_id UK "unique per source"
      TEXT partner_menu_name
      TEXT product_id FK "SET NULL"
      BOOLEAN auto_matched "default false"
      TIMESTAMPTZ created_at
      TIMESTAMPTZ updated_at
    }
    webhook_events {
      BIGSERIAL id PK
      TEXT source
      TEXT event_type
      TEXT entity_id
      TEXT idempotency_key UK "partial unique"
      BOOLEAN signature_ok "default false"
      TEXT status "accepted|duplicate|ignored|rejected|error"
      TEXT note
      JSONB raw "body mentah"
      TIMESTAMPTZ created_at
    }
    online_order_actions {
      BIGSERIAL id PK
      TEXT source
      TEXT order_id "id baris online_orders"
      TEXT partner_order_id
      TEXT order_type "delivery|pickup"
      TEXT action "accept|reject|ready|cancel-review"
      TEXT status "queued|sent|failed|manual|ignored"
      INTEGER attempts "default 0"
      TEXT reason_code
      TEXT reason_text
      TEXT error
      JSONB payload
      TIMESTAMPTZ created_at
      TIMESTAMPTZ updated_at
    }
```

### 6.3 Catatan ERD

Hubungan tanpa FK nyata diberi label `(logical)`. Satu-satunya FK fisik adalah `transaction_items.transaction_id → transactions.id` (CASCADE) dan `online_menu_map.product_id → products.id` (SET NULL). Tabel `categories`, `products`, `settings`, `pending_orders`, `online_orders`, dan `transactions` memakai `deleted` sebagai **tombstone**, bukan penghapusan fisik.

### 6.4 Definisi tabel

#### A. Identitas & katalog

**`users`** — akun login (dibuat oleh seed/migrasi, **bukan** lewat sinkronisasi).

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY |
| `username` | TEXT | NOT NULL, UNIQUE |
| `display_name` | TEXT | NOT NULL |
| `role` | TEXT | NOT NULL, `CHECK (role IN ('Pemilik','Kasir'))` |
| `password_hash` | TEXT | NOT NULL (bcrypt) |
| `active` | BOOLEAN | NOT NULL, DEFAULT TRUE |
| `created_at`, `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |

**`categories`** — kategori menu.

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | TEXT | PRIMARY KEY |
| `payload` | JSONB | NOT NULL — `{ id, emoji, label }` |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |
| `deleted` | BOOLEAN | NOT NULL, DEFAULT FALSE (tombstone) |
| `device_id` | TEXT | nullable, asal perubahan |

**`products`** — katalog menu. Kolom ringkas dipakai server untuk hitung harga/stok; `payload` dikirim apa adanya ke klien.

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | TEXT | PRIMARY KEY |
| `name` | TEXT | NOT NULL, maks. 120 karakter (validasi server) |
| `category_id` | TEXT | nullable, **tanpa FK**; diisi dari `payload.category` |
| `price` | INTEGER | NOT NULL, `CHECK (price >= 0)` |
| `stock` | INTEGER | nullable — `NULL` berarti **tanpa batas** |
| `available` | BOOLEAN | NOT NULL, DEFAULT TRUE |
| `description`, `emoji` | TEXT | nullable |
| `payload` | JSONB | NOT NULL (bentuk lengkap untuk klien) |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |
| `deleted`, `device_id` | BOOLEAN / TEXT | tombstone / asal perubahan |

**`settings`** — **tepat satu baris**, `id = 'main'`.

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | TEXT | PRIMARY KEY, DEFAULT `'main'` |
| `payload` | JSONB | NOT NULL, DEFAULT `'{}'::jsonb` |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |
| `deleted`, `device_id` | BOOLEAN / TEXT | tombstone / asal perubahan |

#### B. Transaksi & antrean kasir

**`transactions`** — satu baris per struk. Harga **dihitung ulang server** dari `products`, bukan dipercaya dari klien.

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | TEXT | PRIMARY KEY — nomor struk `MPJ-YYYYMMDD-xxxxx` |
| `client_txn_id` | UUID | NOT NULL, UNIQUE — kunci idempotency dari perangkat |
| `created_at` | TIMESTAMPTZ | NOT NULL (dari klien) |
| `order_date` | DATE | NOT NULL — diambil dari pola id, fallback `createdAt` UTC |
| `order_type`, `table_number` | TEXT | nullable |
| `subtotal` | INTEGER | NOT NULL, `>= 0` |
| `discount` | INTEGER | NOT NULL, DEFAULT 0, `>= 0`, dibatasi `≤ subtotal` |
| `tax_rate` | NUMERIC(5,2) | NOT NULL, DEFAULT 0 — dibaca dari `settings.payload.taxRate`, dibatasi 0–100. **Metadata; tidak menambah `total`.** |
| `total` | INTEGER | NOT NULL, `>= 0` — `subtotal - discount` |
| `payment` | TEXT | NOT NULL — `cash` / `qris` / `transfer` / `card` (selain itu → `cash`) |
| `paid_amount`, `change_amount` | INTEGER | NOT NULL, DEFAULT 0 |
| `status` | TEXT | NOT NULL, DEFAULT `'paid'` |
| `cashier`, `note`, `device_id` | TEXT | nullable |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |
| `deleted` | BOOLEAN | NOT NULL, DEFAULT FALSE — tombstone soft delete |

Index: `idx_txn_created`, `idx_txn_date`, `idx_txn_updated`.

**`transaction_items`** — snapshot nama & harga saat transaksi, sehingga struk lama tidak berubah bila menu diedit.

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY |
| `transaction_id` | TEXT | NOT NULL, FK → `transactions(id)` ON DELETE CASCADE |
| `product_id` | TEXT | nullable |
| `name` | TEXT | NOT NULL (snapshot) |
| `price` | INTEGER | NOT NULL, `>= 0` (snapshot) |
| `qty` | INTEGER | NOT NULL, `> 0` |
| `total` | INTEGER | NOT NULL, `>= 0` |
| `note` | TEXT | nullable |

Index: `idx_items_txn`.

**`pending_orders`** dan **`online_orders`** — struktur identik:

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | TEXT | PRIMARY KEY — `HOLD-…` untuk pending, `ONL-<prefix>-…` untuk online |
| `payload` | JSONB | NOT NULL (bentuk di §6.5) |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |
| `deleted` | BOOLEAN | NOT NULL, DEFAULT FALSE (tombstone) |
| `device_id` | TEXT | nullable |

Untuk `online_orders`, `deleted = true` berarti pesanan **ditutup** (selesai/dibatalkan); webhook susulan tidak menghidupkannya kembali.

#### C. Audit & integrasi online

**`stock_movements`** — jejak setiap perubahan stok.

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY |
| `product_id` | TEXT | NOT NULL (logical FK, tanpa constraint) |
| `qty` | INTEGER | NOT NULL — negatif = stok keluar |
| `reason` | TEXT | NOT NULL — `sale` / `restock` / `adjust` / `reconcile` |
| `ref` | TEXT | nullable — id transaksi, atau `'catalog'` untuk adjust dari menu |
| `device_id` | TEXT | nullable |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |

**`audit_log`** — jejak aksi penting (login, hapus transaksi, stok konflik, aksi online, dll).

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY |
| `actor` | TEXT | nullable — username, atau `'sistem'` |
| `action` | TEXT | NOT NULL — mis. `order.deleted`, `stock.conflict`, `online:accept` |
| `target` | TEXT | nullable — id objek yang berubah |
| `detail` | JSONB | nullable |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |

**`online_menu_map`** — terjemahan id menu mitra → produk iPo.

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | TEXT | PRIMARY KEY — `"<source>:<partner_menu_id>"` |
| `source` | TEXT | NOT NULL — `gofood` / `grab` / `shopee` |
| `partner_menu_id` | TEXT | NOT NULL, UNIQUE bersama `source` |
| `partner_menu_name` | TEXT | nullable |
| `product_id` | TEXT | FK → `products(id)` ON DELETE SET NULL |
| `auto_matched` | BOOLEAN | NOT NULL, DEFAULT FALSE (hasil cocok-nama otomatis) |
| `created_at`, `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |

Index: `uq_menu_map_source_menu(source, partner_menu_id)` (UNIQUE), `idx_menu_map_product(product_id)`.

**`webhook_events`** — log mentah tiap notifikasi mitra (audit + debug).

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY |
| `source` | TEXT | NOT NULL |
| `event_type` | TEXT | nullable |
| `entity_id` | TEXT | nullable |
| `idempotency_key` | TEXT | nullable, UNIQUE per `source` (partial index, hanya yang non-null) |
| `signature_ok` | BOOLEAN | NOT NULL, DEFAULT FALSE |
| `status` | TEXT | NOT NULL — `accepted` / `duplicate` / `ignored` / `rejected` / `error` |
| `note` | TEXT | nullable |
| `raw` | JSONB | nullable — body asli hasil parse |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |

Index: `idx_webhook_created(source, created_at DESC)`, `uq_webhook_idempotency(source, idempotency_key) WHERE idempotency_key IS NOT NULL`.

**`online_order_actions`** — antrean aksi balik ke mitra (terima/tolak/siap). Aksi tidak hilang walau jaringan mitra mati.

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY |
| `source` | TEXT | NOT NULL |
| `order_id` | TEXT | NOT NULL — id baris di `online_orders` |
| `partner_order_id`, `order_type` | TEXT | nullable — `delivery` / `pickup` |
| `action` | TEXT | NOT NULL — `accept` / `reject` / `ready` / `cancel-review` |
| `status` | TEXT | NOT NULL, DEFAULT `'queued'` — `queued` / `sent` / `failed` / `manual` / `ignored` |
| `attempts` | INTEGER | NOT NULL, DEFAULT 0 |
| `reason_code`, `reason_text`, `error` | TEXT | nullable — alasan tolak & log gagal kirim |
| `payload` | JSONB | nullable |
| `created_at`, `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` |

Index: `idx_online_actions_queue(status, created_at)`, `idx_online_actions_order(order_id)`.

### 6.5 Bentuk payload JSON

**`settings`** (`id = 'main'`) — `DEFAULT_SETTINGS` di `www/js/pos.js`:

```json
{
  "businessName": "Mie Pangsit Jakarta",
  "businessAddress": "Jl. Siradj Salman, Air Putih, Kec. Samarinda Ulu, Kota Samarinda, Kalimantan Timur 75124, Indonesia",
  "businessPhone": "",
  "taxRate": 11,
  "qrisStaticPayload": "",
  "receiptPaperSize": "58mm",
  "receiptFooter": "",
  "onlineRejectionMessage": "Mohon maaf stok habis"
}
```

> `taxRate` adalah metadata PPN (sudah termasuk dalam harga). Server membacanya untuk `transactions.tax_rate`, lalu dihitung ulang: **`total` tetap `subtotal - discount`**.

**`products`** — hasil validasi `validateProduct()` di server:

```json
{
  "id": "pangsit-original",
  "name": "Pangsit Original",
  "category": "Mie Pangsit Jakarta",
  "price": 18000,
  "stock": 40,
  "available": true,
  "description": "",
  "emoji": "🥟"
}
```

> `stock: null` = tanpa batas. Perhatikan: di `payload` kuncinya **`category`**, sedangkan kolom SQL-nya **`category_id`**.

**`categories`**:

```json
{ "id": "mie-pangsit", "emoji": "🥟", "label": "Mie Pangsit Jakarta" }
```

**`pending_orders`** — pesanan "Bayar nanti" (`mpj_pos_pending`):

```json
{
  "id": "HOLD-20261119-48123",
  "createdAt": "2026-11-19T07:12:03.000Z",
  "orderType": "dine-in",
  "tableNumber": "3",
  "items": [
    { "productId": "pangsit-original", "name": "Pangsit Original", "price": 18000, "qty": 2, "total": 36000, "note": "" }
  ],
  "subtotal": 36000,
  "discount": 0,
  "total": 36000,
  "status": "pending",
  "payment": null,
  "cashier": "Kasir",
  "note": ""
}
```

**`online_orders`** — payload yang disimpan server setelah webhook dinormalisasi & dicocokkan dengan katalog:

```json
{
  "id": "ONL-GF-2174",
  "source": "gofood",
  "partnerOrderId": "2174",
  "partnerOutletId": "",
  "externalOutletId": "",
  "orderType": "delivery",
  "code": "GF-2174",
  "customer": "Dina",
  "driverName": "",
  "driverPin": "",
  "note": "Pedas level 2",
  "status": "baru",
  "createdAt": "2026-11-19T07:00:00.000Z",
  "items": [
    { "productId": "pangsit-original", "qty": 2, "note": "" }
  ],
  "unmappedItems": [],
  "partnerTotal": 87000,
  "pickupCode": "A12"
}
```

Status lokal: `baru` → `dibuat` → `siap` → `selesai`. Status dari webhook **tidak pernah mundur** dari status yang sudah dilangkahi kasir. `pickupCode` hanya ada setelah status `siap`.

**`transactions`** — hasil `buildPayload()` di `services/orders.js` (bentuk sama dengan `mpj_pos_orders`):

```json
{
  "id": "MPJ-20261119-48123",
  "clientTxnId": "9f1c…(UUID)",
  "createdAt": "2026-11-19T07:12:03.000Z",
  "items": [
    { "productId": "pangsit-original", "name": "Pangsit Original", "price": 18000, "qty": 2, "total": 36000, "note": "" }
  ],
  "orderType": "dine-in",
  "tableNumber": "3",
  "subtotal": 36000,
  "discount": 0,
  "total": 36000,
  "taxRate": 11,
  "taxIncluded": true,
  "payment": "cash",
  "paidAmount": 40000,
  "changeAmount": 4000,
  "status": "paid",
  "cashier": "Kasir",
  "note": ""
}
```

> Untuk transaksi online, `payment` diisi `gofood` / `grab` / `shopee` di perangkat, tetapi server mengubah nilai di luar daftar `cash|qris|transfer|card` menjadi **`cash`** saat menyimpan.

**`webhook_events.raw`** — body asli envelope mitra, misalnya `{ header: {…}, body: { order: {…}, service_type: "gofood" } }`. Disimpan apa adanya untuk debug.

### 6.6 Pemetaan localStorage → tabel → endpoint

| `localStorage` | Tabel server | Tulis | Baca | Hak |
|---|---|---|---|---|
| `mpj_pos_products` | `products` | `POST /api/sync/push` | `GET /api/sync/pull?table=products` | Pemilik |
| `mpj_pos_categories` | `categories` | `POST /api/sync/push` | `GET /api/sync/pull?table=categories` | Pemilik |
| `mpj_pos_settings` | `settings` (`main`) | `POST /api/sync/push` | `GET /api/sync/pull?table=settings` | Pemilik |
| `mpj_pos_orders` | `transactions` + `transaction_items` | `POST /api/orders`, `DELETE /api/orders/:id` | `GET /api/sync/pull?table=orders` | Kasir & Pemilik (hapus: Pemilik) |
| `mpj_pos_pending` | `pending_orders` | `POST /api/sync/push` | `GET /api/sync/pull?table=pending_orders` | Kasir & Pemilik |
| `mpj_pos_online` | `online_orders` | `POST /api/sync/push` | `GET /api/sync/pull?table=online_orders` | Kasir & Pemilik |
| `mpj_pos_snapshots` | — | tidak dikirim | tidak diterima | lokal saja |
| `mpj_pos_users`, `mpj_pos_session` | `users` (via CRUD `/api/users`) | `/api/users` | `/api/users`, `/api/auth/me` | Pemilik |

**Tidak termasuk snapshot.** Cadangan lokal (`mpj_pos_snapshots`), file backup JSON, theme, keranjang, dan posisi sidebar **tidak** punya tabel server. Salinan server berupa baris tersinkron, bukan file backup.

**Jalur transaksi berbeda dari tabel lain.** Daftar `SYNC_TABLES` di server hanya `products`, `categories`, `settings`, `pending_orders`, `online_orders` — **`orders` tidak termasuk**. Klien tetap mencantumkan `orders` di `TABLES` dan `GET /api/sync/tables` mengembalikan 6 nama, tetapi:
- `POST /api/sync/push` dengan `table: 'orders'` ditolak (`400 Tabel tidak dikenal`);
- `GET /api/sync/pull?table=orders` **khusus** memanggil `pullOrders()` (transaksi + itemnya);
- tulis transaksi wajib lewat `POST /api/orders` supaya harga dihitung ulang.

### 6.7 Alur tulis & aturan konsistensi

**1. Transaksi baru** — `POST /api/orders` dengan `{ order, deviceId }`:
1. Cek duplikat berdasarkan `id` **atau** `client_txn_id`; kalau ada → kembalikan transaksi lama, `duplicate: true` (tidak ada baris baru).
2. Ambil harga resmi dari `products` yang `deleted = false`. Produk yang tidak ditemukan memakai harga dari kasir + audit `order.item_unverified`.
3. Hitung ulang `subtotal`, batasi `discount` ke `0…subtotal`, `total = subtotal - discount`,ambil `tax_rate` dari `settings`.
4. Simpan `transactions` + `transaction_items` dalam **satu transaksi database** (atomik).
5. Kurangi stok hanya untuk produk dengan stok terbatas, minimum 0, lalu tulis `stock_movements` alasan `sale`. Kalau stok awal lebih kecil dari qty, dicatat `stock.conflict` di audit.
6. `paidAmount` untuk tunai dibatasi `≥ total`; kembalian = `paidAmount - total`.

**2. Hapus transaksi** — `DELETE /api/orders/:id` (Pemilik saja): soft delete (`deleted = true`, `updated_at` baru), audit `order.deleted`, tombstone ikut tersebar lewat pull. **Stok tidak dikembalikan.**

**3. Sinkronisasi katalog/antrean** — `POST /api/sync/push` dengan `{ table, rows, deviceId }`:
- maks. 1000 baris per kiriman; nama tabel dibatasi daftar putih;
- `products` dan `categories` dan `settings` hanya Pemilik (403 untuk Kasir);
- `settings` selalu dinormalisasi ke `id = 'main'`;
- upsert `ON CONFLICT (id) DO UPDATE`, `updated_at = now()`;
- perubahan stok lewat menu dicatat sebagai `stock_movements` alasan `adjust` dengan `ref = 'catalog'`;
- untuk `online_orders`, server membandingkan payload lama/baru lalu mengantrekan aksi mitra (`storeTransition`).

**4. Webhook masuk** — `POST /api/webhooks/:source`:
- verifikasi tanda tangan GoBiz dari **raw body** (`X-Go-Signature`) terhadap `GOFOOD_NOTIFICATION_SECRET`; tanda tangan salah → `rejected`, tetap dicatat;
- `idempotency_key` dari `X-Go-Idempotency-Key` atau `header.event_id`; duplikat → status `duplicate`, pesanan tidak digandakan;
- payload dinormalisasi → menu dicocokkan (peta manual → id sama → nama persis → nama dasar → awalan unik) → `online_orders` di-upsert dengan id deterministik `ONL-<prefix>-<idMitra>`;
- perubahan status kasir menghasilkan baris `online_order_actions` dengan status awal `queued` (pengirim ke mitra butuh kredensial GoBiz).

**5. Tombstone** — hapus baris katalog/antrean tidak menghapus fisik: `deleted = true` + `updated_at` baru. Untuk `online_orders` dan transaksi online, tombstone hanya `{ id }`; karena itu server hanya mengirim aksi `reject` otomatis bila status sebelumnya masih `baru` — untuk pesanan yang sudah diterima server sengaja tidak mengirim apa pun daripada salah membatalkan.

### 6.8 Variabel lingkungan (`.env` server)

| Variabel | Wajib | Default / catatan |
|---|---|---|
| `DATABASE_URL` | ✅ | Connection string Neon pooled, `sslmode=require` |
| `JWT_SECRET` | ✅ | Rahasia penandatanganan token |
| `JWT_TTL_HOURS` | — | `720` |
| `PORT` | — | `8080` |
| `NODE_ENV` | — | `development` |
| `CORS_ORIGINS` | — | Daftar origin dipisah koma |
| `LOGIN_RATE_LIMIT` | — | `20` |
| `TRUST_PROXY` | — | `0` (set `1` di behind proxy) |
| `GOFOOD_AUTH_URL` | — | sandbox `https://integration-goauth.gojekapi.com/oauth2/token` |
| `GOFOOD_API_BASE` | — | sandbox `https://api.partner-sandbox.gobiz.co.id` |
| `GOFOOD_CLIENT_ID`, `GOFOOD_CLIENT_SECRET`, `GOFOOD_OUTLET_ID` | ⚠️ produksi | kosong → adapter tidak bisa dipakai |
| `GOFOOD_NOTIFICATION_SECRET` | ⚠️ produksi | verifikasi `X-Go-Signature` |
| `GOFOOD_WEBHOOK_URL` | ⚠️ produksi | URL HTTPS publik untuk langganan notifikasi |
| `GOFOOD_AUTO_ACCEPT` | — | `0` |
| `GOFOOD_REJECT_REASON_CODE` | — | `OTHERS` |
| `GOFOOD_SCOPE` | — | `partner:outlet:read gofood:order:read gofood:order:write gofood:catalog:read gofood:catalog:write` |
| `SEED_OWNER_USERNAME`, `SEED_OWNER_PASSWORD` | ⚠️ seed | default username `pemilik`; sandi default kosong (script hanya mencetak catatan, jadi **wajib diisi manual** sebelum produksi) |
| `SEED_CASHIER_USERNAME`, `SEED_CASHIER_PASSWORD` | ⚠️ seed | default username `kasir`; sandi default kosong, sama seperti di atas |

> Status saat ini: `DATABASE_URL` di `server/.env` masih placeholder `postgresql://contoh:contoh@127.0.0.1:5432/ipos_placeholder`, sehingga seluruh tabel di atas **belum** tersambung ke database sungguhan. Kredensial GoBiz juga belum ada.

---

## 7. Requirement non-fungsional

| Aspek | Requirement |
|---|---|
| Offline | Seluruh alur kasir (kecuali sinkron & webhook) harus bisa tanpa internet |
| Privasi | Foto QRIS diproses di perangkat; tidak dikirim ke server mana pun |
| Keamanan | Tidak ada kredensial DB di frontend; query parameter; daftar putih tabel; rate limit login; token JWT; HMAC webhook; CORS whitelist; log tidak memuat body/token |
| Reliabilitas | Penulisan gagal tidak boleh diam-diam — muncul pita peringatan; stok/transaksi utama diprioritaskan daripada cadangan |
| Kapasitas | localStorage ±5 MB; satu snapshot ≈ ≤600 KB |
| Kompatibilitas | Android minimal API 24; QRIS foto JPG/PNG ≤12 MB |
| Cache | Setiap perubahan `pos.js`/`sw.js` wajib bump `pos.html?v=N` dan `CACHE_NAME` |
| Build | APK **hanya dibangun atas perintah pemilik** |

---

## 8. Status saat ini (jujur, bukan rencana)

| Item | Status | Keterangan |
|---|---|---|
| Web POS, kasir, QRIS foto, laporan, backup, tab gabungan | ✅ Selesai | Sudah diuji di browser (`pos.js?v=96`, cache `mpj-pos-v105`) |
| APK termasuk perubahan terakhir | ❌ Belum | `ipos_mie_v17.apk` (versionCode 27) **belum** memuat tab "Server & cadangan" dan upload QRIS foto |
| Backend berjalan | ⚠️ | API `:8080` dan web `:8031` bisa dinyalakan; health 200 |
| Database Neon | ❌ | `DATABASE_URL` masih `postgresql://contoh:contoh@127.0.0.1:5432/ipos_placeholder`; migrasi/seed belum jalan |
| Login server & sinkron | ⚠️ | Kode ada, tapi tidak aktif karena DB dan alamat API belum diisi |
| Kredensial GoBiz | ❌ | Belum ada `GOFOOD_CLIENT_ID`, `GOFOOD_CLIENT_SECRET`, `GOFOOD_OUTLET_ID`, notification secret, webhook URL HTTPS |
| GrabFood / ShopeeFood | ❌ | Sengaja ditunda |
| Midtrans | ❌ | Sengaja tidak dipakai |

---

## 9. Kriteria penerimaan (uji)

| ID | Skenario | Hasil yang diharapkan |
|---|---|---|
| AC-01 | Kasir menekan menu saat tab "Bayar nanti" aktif | Panel otomatis ke tab Keranjang, item masuk keranjang |
| AC-02 | Transaksi tunai selesai | Riwayat bertambah, stok berkurang, struk muncul, keranjang kosong |
| AC-03 | Hapus transaksi | Transaksi hilang dari tampilan, stok **tidak** bertambah |
| AC-04 | Upload foto QRIS valid | Textarea terisi payload yang sama, status menampilkan nama merchant |
| AC-05 | Upload QR bukan QRIS | Textarea tidak berubah, pesan "bukan kode QRIS" |
| AC-06 | Upload gambar tanpa QR | Textarea tidak berubah, pesan "QR tidak terbaca" |
| AC-07 | Simpan QRIS lalu buat QRIS dinamis | QR bernominal sesuai total, CRC valid |
| AC-08 | Buat cadangan 3× | Jumlah cadangan tetap **1** |
| AC-09 | Klik Hapus pada cadangan | Hanya cadangan itu hilang, data POS tidak berubah |
| AC-10 | Klik Kembalikan | Data kembali ke titik cadangan, kondisi sebelum restore disimpan sebagai cadangan |
| AC-11 | Buka Pengaturan | 5 tab, "Server & cadangan" berisi kartu Server + Cadangkan data |
| AC-12 | Kasir membuka Menu/Pengaturan | Ditolak dengan pesan, tetap di Dashboard |
| AC-13 | Webhook GoFood duplikat | Event kedua berstatus `duplicate`, tidak menggandakan pesanan |
| AC-14 | Webhook dengan tanda tangan salah | Ditolak, tercatat di `webhook_events` dengan `signature_ok = false` |
| AC-15 | Aksi terima/siap saat mitra mati | Tersimpan di `online_order_actions` status `queued`, bisa dikirim ulang |

---

## 10. Asumsi & blocker

1. **Database:** butuh connection string Neon pooled (`sslmode=require`), lalu `npm run migrate`, `npm run seed`, dan uji `npm run selftest`.
2. **GoFood:** butuh pendaftaran Partner Integration melalui `developer.gobiz.com/contact-us`; kesalahan `UnregisteredOutlet` berarti outlet belum terdaftar. Webhook harus HTTPS publik.
3. **Sandi default** `1234` harus diganti sebelum pemakaian produksi.
4. **APK** belum mengikuti perubahan terakhir; build ditunda sesuai instruksi pemilik.
5. **Tidak ada Git** di folder proyek — perubahan belum versi-terkontrol.

---

## 11. Non-goal / sengaja tidak dibuat

- Gateway pembayaran Midtrans atau payment gateway lain.
- Adapter resmi GrabFood/ShopeeFood.
- Endpoint unggah file backup ke server (salinan server saat ini berupa **baris tersinkron**, bukan file backup).
- Multi-outlet/manajemen cabang.
- Sinkron realtime WebSocket (memakai polling).
- Build APK otomatis tanpa perintah.
