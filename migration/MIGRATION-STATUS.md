# Status Migrasi & Apa yang Belum Terbukti

Terakhir diperbarui: **15 Oktober 2026** · Aplikasi versi target: **12** (versionCode 22)

> Dokumen ini jujur memisahkan **sudah ditulis** dari **sudah terbukti**.
> Jangan menganggap migrasi "selesai" sebelum butir di bagian *Belum terbukti*
> lolos di perangkat dan database sungguhan.

---

## 1. Ringkasan satu layar

| Area | Status |
| --- | --- |
| Audit penggunaan Supabase | ✅ Selesai |
| Cadangan data Supabase (baca-saja) | ✅ Ada di `migration/backups/` |
| Backend Node/Express (kode) | ✅ Lengkap, sintaks bersih |
| Skema Neon (`001_init.sql`) | ✅ Ditulis (belum dijalankan di DB asli) |
| Uji logika backend (`npm run selftest`) | ✅ **19/19** lulus, tanpa database |
| Integrasi pesanan mitra (GoFood) — sisi iPo | ✅ Kode lengkap (webhook, peta menu, antrean aksi); tanda tangan & normalisasi **terbukti**, tulis DB belum diuji |
| Kredensial GoBiz / GoFood asli | ⛔ **Belum** (pemilik belum menyerahkan App ID/Secret) |
| Frontend: IndexedDB + klien sinkron baru | ✅ Ditulis & diuji di browser (mode lokal + gagal server) |
| Manajemen pengguna (UI + API) | ✅ Ditulis; API belum diuji terhadap DB asli |
| Bump versi 12 / versionCode 22 | ✅ Dibangun: `ipos_mie_v12.apk` (tanda tangan rilis sama) |
| Migrasi & seed di Neon asli | ⛔ **Belum** (tidak ada `DATABASE_URL`) |
| Impor data ke Neon | ⛔ **Belum** |
| Sinkron dua perangkat nyata | ⛔ **Belum** |
| Printer Bluetooth di perangkat | ⛔ **Belum** |
| Membangun APK 12 | ✅ Sudah (per 15 Okt 2026), belum dipasang/diuji di perangkat pemilik |
| Menghapus Supabase | ⛔ **Belum** (manual, lihat `CUTOVER.md`) |

---

## 2. Yang sudah dikerjakan (rinci)

### Audit & cadangan
- Hanya ada **satu** titik pemakaian Supabase: `fetch` REST di `www/js/sync.js`.
  Tidak ada SDK, tidak ada kredensial di tempat lain.
- GoFood/Grab/ShopeeFood diperiksa: **hanya UI + data dummy**, tanpa endpoint/kredensial.
  Tidak ada yang dikarang di migrasi ini.
- Cadangan cloud tersimpan di `migration/backups/supabase-export-*.json`
  (produk 27/26 aktif, kategori 6/5 aktif, settings 1, order/pending/online berupa tombstone).
- `migration/export-supabase.js` tersedia untuk membuat cadangan ulang kapan saja.

### Backend (`server/`)
- `src/` : `config`, `db`, `util`, `audit`, `auth`, `app`, `index`.
- `src/services/orders.js` : **menghitung ulang** harga/subtotal/total dari tabel
  `products`; diskon dibatasi `0..subtotal`; pajak dari `settings` server; stok
  dikurangi + dicatat di `stock_movements`; deteksi konflik stok → `audit_log`.
- `src/services/sync.js` : validasi + upsert katalog/antrean dengan **daftar putih**
  nama tabel.
- `src/routes/` : `auth` (login rate-limited, `me`, ganti sandi), `users`
  (CRUD khusus Pemilik), `sync` (push/pull), `orders` (POST idempotent, GET rekap,
  DELETE `/api/orders/:id` soft delete khusus Pemilik — **belum diuji ke DB asli**).
- `scripts/` : `migrate`, `seed`, `import-supabase`, `selftest`, `mock-gofood-order`.
- `Dockerfile`, `.dockerignore`, `.env.example`, `.gitignore`, `README.md`.
- Idempotency transaksi: `id` unik **dan** `client_txn_id` unik; transaksi lama
  tanpa UUID memakai UUID deterministik (md5 dari `order.id`) sehingga retry tetap aman.

### Integrasi pesanan mitra (kerangka GoFood) — 17 Okt 2026
- `migrations/002_online_integration.sql` : `online_menu_map` (peta menu mitra ↔
  produk iPo), `webhook_events` (log mentah + idempotency), `online_order_actions`
  (antrean aksi terima/tolak/siap). **Belum dijalankan** di DB asli.
- `src/services/online.js` : normalisasi payload mitra (GoFood resmi +
  bentuk umum), pencocokan menu berlapis (peta → id produk → nama → dasar nama →
  awalan unik), penulisan `online_orders`, antrean aksi, dan penerjemahan status
  kasir menjadi aksi mitra. Fungsi murninya diuji di `selftest`.
- `src/services/gofood.js` : adapter sesuai dokumen resmi GoBiz — OAuth2
  `client_credentials`, `accepted`, `cancelled` (+`cancel_reason_code`), dan
  `food-prepared`.
- `src/routes/webhooks.js` : `POST /api/webhooks/:source` publik, **wajib**
  `X-Go-Signature` (HMAC-SHA256 body mentah, `timingSafeEqual`); 503 bila secret
  server belum diisi, 401 bila tanda tangan salah. Log mentah selalu disimpan.
- `src/routes/online.js` : (khusus Pemilik) `config`, `orders`, `menu-map`
  (+`otomatis`), `actions` (+`kirim`), `orders/:id/aksi`, `webhooks`.
- `src/services/sync.js` : saat baris `online_orders` dikirim kasir, server
  membandingkan status lama↔baru lalu mengantrekan `accept`/`ready`; tombstone
  berstatus lama `baru` → `reject`. Status lama `dibuat`/`siap` **tidak**
  menghasilkan aksi (tombstone tidak membawa alasan — server sengaja tidak menebak).
- `scripts/mock-gofood-order.js` : kirim webhook GoFood bertanda tangan untuk uji
  lokal tanpa akun GoBiz (`--unsigned` untuk uji penolakan).
- `.env` baru: `GOFOOD_CLIENT_ID/SECRET/OUTLET_ID/NOTIFICATION_SECRET`,
  `GOFOOD_API_BASE`, `GOFOOD_AUTH_URL`, `GOFOOD_AUTO_ACCEPT`,
  `GOFOOD_REJECT_REASON_CODE` (+ `GOFOOD_SCOPE`).

### Frontend (`www/`)
- `js/config.js` (`MPJConfig`) : alamat server bisa diubah saat aplikasi berjalan
  lewat `localStorage['mpj_api_base']` — **tidak perlu build ulang** untuk ganti URL.
- `js/localdb.js` (`MPJLocalDB`) : IndexedDB `ipos_local` (`outbox` + `meta`), dengan
  fallback ke memori bila IndexedDB tidak ada.
- `js/sync.js` : ditulis ulang; API `MPJSync` dipertahankan (`init/start/pushList/
  syncNow/status/isEnabled/setEnabled/tables/_internals`). Status
  `pending/syncing/synced/failed`, backoff, antrean IndexedDB, tombol on/off.
  Bila alamat server kosong → status `off` (mode lokal, tanpa trafik jaringan).
- `js/pos.js` : login lewat server bila alamat diatur (JWT), kalau tidak tetap
  akun lokal `kasir`/`pemilik` sandi `1234`; logout menghapus token; aksi
  `load-users` dan `user-deactivate` khusus Pemilik; kartu "Server & pengguna";
  transaksi kini menyertakan `clientTxnId` (UUID perangkat).
  Baris katalog/pengaturan hanya diantrekan saat peran = Pemilik, sehingga
  antrean transaksi kasir tidak pernah macet karena server menolak (403).
- `pos.html`, `css/pos.css`, `sw.js` (cache v62) diperbarui.

### Perubahan v12 atas permintaan pemilik (15 Okt 2026)
- **Katalog Menu = tabel polos** di semua ukuran layar (aturan kartu/`.menu-list` dihapus).
- **Pembayaran langsung selesai** — transaksi lunas tidak lagi masuk antrean
  "Dibuat"; tab itu diganti nama **"Bayar nanti"** dan hanya diisi lewat tombol
  **"⏸ Simpan nanti"** (pesanan belum bayar, `HOLD-…`).
- **Hapus transaksi di Laporan (khusus Pemilik)** — tombol 🗑 di sebelah tombol
  struk, dengan konfirmasi. Hapus = soft delete: baris dibuang dari data lokal
  dan tombstone dikirim ke `DELETE /api/orders/:id` (server menandai
  `deleted = true` + catat `audit_log`) supaya perangkat lain ikut menghapus.
  Stok **tidak** dikembalikan otomatis saat transaksi dihapus.
  Diuji di browser: pemilik melihat tombol, kasir tidak (aksi dipaksa pun ditolak).
- **Pesanan online: cetak = struk pelanggan** — tombol di detail pesanan online
  (dulu "🖨 Cetak nota" yang mencetak nota dapur) sekarang mencetak **struk
  pelanggan** lengkap (kepala usaha, no. pesanan, platform, pelanggan, kode ambil,
  item + harga, subtotal/total) dan tetap tersedia di **semua tahap**
  (Baru / Dibuat / Siap diambil) — tidak perlu cetak dua kali, kertas tidak
  terbuang saat pesanan masih dibuat. Judul cetak Bluetooth jadi
  "Struk Mie Pangsit Jakarta".
- **Pesanan online: tombol "🚫 Batalkan pesanan"** — ditambahkan di **ujung kiri**
  deretan tombol detail (dipisah jauh dari tombol maju status) dan juga sebagai
  tombol **✕ di ujung kiri tiap kartu** daftar online, tersedia di **semua status
  termasuk "Siap diambil"**. Selalu ada konfirmasi; untuk pesanan berstatus "Baru"
  kalimatnya "Tolak pesanan …?". Diuji di browser: konfirmasi dibatalkan → pesanan
  tetap ada; disetujui → pesanan hilang dari daftar + `mpj_pos_online`, tidak masuk
  laporan, dan klik ✕ tidak ikut membuka detail pesanan.

### Uji yang benar-benar dijalankan di mesin ini
- `node --check` pada **semua** berkas `www/js/*.js`, `www/sw.js`, dan seluruh
  `server/**/*.js` → bersih.
- `npm run selftest` → **19/19 lulus** (tanpa database), termasuk: verifikasi
  tanda tangan webhook terima/tolak, normalisasi payload GoFood (nomor pesanan,
  pelanggan, item + varian, catatan alat makan, tipe pickup), pencocokan menu
  berlapis, penolakan item tak dikenal (dilaporkan, bukan dibuang diam-diam),
  kestabilan id pesanan lokal, dan terjemahan status kasir → aksi mitra.
- `require('./src/app')` dengan env dummy → `APP LOADED OK`.
- **Server dijalankan sungguhan** (17 Okt 2026): `npm.cmd start` di `server` →
  `GET /api/health` = `{"ok":true,"service":"ipos-api"}`; statik
  `python -m http.server 8031 --bind 127.0.0.1` di `www` → `pos.html` HTTP 200.
- **Webhook GoFood diuji di server berjalan** (tanpa database, memakai
  `GOFOOD_NOTIFICATION_SECRET` uji):
  - webhook tanpa/tanda tangan palsu → **HTTP 401** (ditolak, sesuai harapan);
  - webhook bertanda tangan benar → **HTTP 500** dan log server jelas
    `ECONNREFUSED 127.0.0.1:5432` — artinya tanda tangan lolos dan alur masuk
    berhenti **hanya** karena `DATABASE_URL` masih placeholder.
  - `GET /api/online/config` tanpa token → 401 (penjaga peran bekerja).
  Ini bukan klaim "integrasi selesai": penulisan ke DB belum terbukti.
- Browser (Chrome headless via harness), `www` disajikan di `127.0.0.1`:
  - Halaman termuat **tanpa error konsol**; `MPJConfig`, `MPJLocalDB`, `MPJSync` terdefinisi.
  - Login lokal `pemilik`/`1234` berhasil; kartu "Server & pengguna" tampil.
  - **Checkout penuh berhasil**: transaksi tersimpan, baris `orders` masuk outbox
    IndexedDB, dan `clientTxnId` berupa UUID yang sah.
  - **Peran diuji:** login `kasir` hanya mengantrekan `orders`/`pending_orders`/
    `online_orders` (katalog & pengaturan **tidak**, supaya tidak ditolak server);
    login `pemilik` juga mengantrekan `products`/`categories`/`settings`.
    Default tetap **25 menu** dan pajak **11%** (tidak ada regresi).
  - Alamat server tidak diatur → status sinkron `off` (mode lokal, tanpa trafik jaringan).
- Jalur gagal: dengan alamat server tak terjangkau, status menjadi `error`
  ("Failed to fetch", `queued` tetap utuh), aplikasi **tidak** crash dan tetap
  bisa dipakai offline.

---

## 3. Belum terbukti (butuh `DATABASE_URL` + hosting + perangkat)

Butir berikut **tidak diklaim selesai**:

1. **Migrasi & seed di Neon asli** — belum dijalankan (tidak ada `DATABASE_URL`;
   tidak ada `psql`/Docker di mesin ini).
2. **Impor data** dari cadangan ke Neon + verifikasi jumlah baris.
3. **API terhadap DB asli**: login, push/pull, pembuatan transaksi, rekap,
   **DELETE transaksi (soft delete) + tombstone-nya tersebar ke perangkat lain**.
4. **Sinkron dua arah di dua perangkat** (katalog & transaksi).
5. **Konflik stok** lintas perangkat + rekonsiliasi.
6. **Kinerja & kebersihan log** di bawah beban normal warung.
7. **Printer Bluetooth** tetap berfungsi di perangkat nyata.
8. **APK versi 12** dibangun, ditandatangani, dipasang; verifikasi `aapt badging`.
9. **Cadangan Neon dibuat dan diuji pulihkan**.
10. **Integrasi GoFood ke DB asli**: menjalankan `002_online_integration.sql`,
    lalu membuktikan webhook menulis ke `online_orders`, mempelajari pemetaan
    menu (`online_menu_map`), dan mengisi antrean `online_order_actions`.
11. **Pengiriman aksi sungguhan ke GoFood** (terima/tolak/siap) — butuh
    `GOFOOD_CLIENT_ID/SECRET/OUTLET_ID` dari portal.
12. **Server HTTPS publik** untuk menerima webhook GoFood + pendaftaran
    subscription di portal (tanpa ini, webhook hanya bisa diuji lokal).
13. Sinkronisasi katalog/harga & tanda "habis" (`PUT .../v1/catalog`) — belum dibuat.

### Catatan teknis yang perlu diketahui saat uji lanjutan
- **Rentang sinkron memakai `updated_at > cursor`.** Karena satu permintaan push
  dapat menulis banyak baris dengan `updated_at` identik, pengambilan dibatasi
  `limit` (≤1000). Untuk katalog warung ini (belasan baris) aman, tetapi bila
  suatu saat ada >1000 baris berbagi stempel waktu yang sama, baris kelebihan bisa
  terlewat. Solusi (bila perlu): paginasi berbasis kunci `(updated_at, id)`.
- **Login saat alamat server kosong tetap memakai akun lokal** (`1234`). Ini
  mempertahankan alur yang ada, tetapi berarti penerapan peran/hash baru hanya
  berlaku setelah alamat server diatur dan kasir masuk lewat server.
- **Token kedaluwarsa** (`JWT_TTL_HOURS`) membuat sinkron berstatus `error` dan
  mencoba lagi; pengguna perlu keluar–masuk lagi.

---

## 4. Cara memverifikasi tahap berikutnya

Ikuti `migration/CUTOVER.md` dari Tahap 1. Ringkasnya:

```bash
cd server
cp .env.example .env          # isi DATABASE_URL + JWT_SECRET asli
npm install
npm run migrate
npm run seed
npm run selftest
npm start                     # cek GET /api/health
npm run import:supabase       # setelah backup tersedia
```

Lalu di perangkat uji: isi **Pengaturan → Server & pengguna → Alamat server**,
keluar, masuk lewat server, dan uji transaksi, ubah menu, dan mode offline.

---

## 5. Berkas kunci

| Berkas | Guna |
| --- | --- |
| `migration/AUDIT-AND-PLAN.md` | Audit awal + rencana bertahap |
| `migration/API-DELIVERY.md` | Cara mendapatkan API GoFood/GrabFood/ShopeeFood + cara menempelnya ke iPo |
| `migration/CUTOVER.md` | Langkah operasional + rollback + cara hapus Supabase |
| `migration/export-supabase.js` | Buat cadangan cloud (baca-saja) |
| `server/README.md` | Jalankan, deploy, backup/restore, keamanan |
| `server/.env.example` | Template environment (tanpa kredensial nyata) |
| `server/migrations/001_init.sql` | Skema Neon |
| `server/migrations/002_online_integration.sql` | Peta menu mitra, log webhook, antrean aksi |
| `server/src/services/online.js` | Normalisasi pesanan mitra, pencocokan menu, antrean aksi |
| `server/src/services/gofood.js` | Adapter GoFood (OAuth2, terima/tolak/siap) |
| `server/src/routes/webhooks.js` | Penerima webhook mitra (wajib tanda tangan) |
| `server/src/routes/online.js` | Endpoint pemilik untuk pesanan/pemetaan/aksi |
| `server/scripts/mock-gofood-order.js` | Webhook GoFood palsu untuk uji lokal |
