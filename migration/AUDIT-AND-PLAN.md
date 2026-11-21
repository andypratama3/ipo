# IPOS — Audit & Rencana Migrasi Supabase → SQLite/IndexedDB + Neon PostgreSQL

Tanggal audit: 2026-10-14
Lingkungan: `D:\web\app\ipomiepangsit`

---

## 1. Ringkasan stack saat ini (hasil pemeriksaan kode, bukan asumsi)

| Lapisan | Kenyataan di proyek |
|---|---|
| Frontend | **Vanilla JavaScript**, tanpa framework, **tanpa bundler**. Satu file besar `www/js/pos.js` (~190 KB), `www/pos.html`, `www/css/pos.css`. |
| Backend | **TIDAK ADA**. Tidak ada Express/Fastify/server, tanpa API sendiri. |
| Bahasa | JavaScript (browser) + Java (plugin native Android). |
| Database cloud | **Supabase** diakses **langsung dari frontend** lewat `fetch` REST di `www/js/sync.js` memakai *publishable key* (kunci publik, andalkan RLS). |
| Paket | Aplikasi **Capacitor 8 Android** (WebView) **sekaligus PWA** (`www/sw.js`, `manifest.webmanifest`). `webDir: www`. |
| Penyimpanan lokal | **localStorage** murni (16 pemakaian). Tidak ada SQLite, IndexedDB, ataupun plugin DB. |
| Autentikasi | **Bukan Supabase Auth.** `USERS = { kasir, pemilik }` di-hardcode di `pos.js`, kata sandi harfiah `'1234'`, role disimpan di sesi. |
| Tabel | 27 produk (26 aktif), 6 kategori (5 aktif), 1 baris settings; `orders`/`pending_orders`/`online_orders` di cloud seluruhnya **tombstone** (riwayat tersimpan lokal di perangkat). |

### Bukti kunci
- Satu-satunya panggilan jaringan di seluruh frontend: `sync.js:109` `fetch(SUPABASE_URL + path, …)`.
- Penyimpanan lokal: hanya `localStorage` (16 rujukan di `www/js`, terbanyak di `pos.js`).
- Tidak ada plugin Capacitor terdaftar: `android/app/src/main/assets/capacitor.plugins.json` = `[]`.
- `package.json` **tidak** memuat `@supabase/supabase-js` → tidak ada dependency npm Supabase untuk dihapus.
- Izin Android: hanya `INTERNET` + Bluetooth. Tidak ada konfigurasi network-security khusus.

---

## 2. Inventaris penggunaan Supabase

### 2.1 Skema database Supabase (generik "key-value per tabel")
Semua tabel memakai bentuk yang sama (dipakai pola sync, bukan skema relasional):

| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | text | Kunci utama. `settings` selalu `main`. |
| `payload` | jsonb | Isi objek/baris sesungguhnya (menu, kategori, order, dll). |
| `updated_at` | timestamptz | Kursor sinkronisasi (pull `updated_at=gt.<cursor>`). |
| `deleted` | boolean | Tombstone (penghapusan lembut). |
| `device_id` | text | Perangkat penulis (untuk deteksi "perubahan dari perangkat lain"). |

Tabel: `products`, `categories`, `settings`, `orders`, `pending_orders`, `online_orders`.

### 2.2 Yang TIDAK dipakai (penting)
- **Supabase Auth**: tidak dipakai. Login lokal hardcoded `kasir`/`pemilik`, sandi `1234`.
- **Supabase Storage**: tidak dipakai. Backup/ekspor/impor memakai file JSON + plugin native (`DocumentSharePlugin`).
- **Supabase Realtime**: tidak dipakai (sync memakai polling `setInterval` 60 detik).
- **RPC / Edge Functions / Triggers / Views**: tidak dipakai. Tidak ada migrasi SQL di repo.
- **RLS**: tidak ada definisi di repo. Karena kunci publishable dipakai langsung dari browser, tabel efektifnya terbuka untuk anon (perlu diasumsikan permissive sampai dibuktikan lain).

### 2.3 Alur sinkronisasi saat ini (`www/js/sync.js`)
- Local-first: state utama di `localStorage`; setiap `save()` menaruh baris ke antrean di memori + `localStorage`.
- Push: `POST /rest/v1/<table>` dengan `Prefer: resolution=merge-duplicates` (upsert). Tombol "tombstone" `{id}` untuk baris yang hilang.
- Pull: `GET /rest/v1/<table>?updated_at=gt.<cursor>` tiap 60 detik; perangkat pertama mem-bootstrap cloud kosong dari data lokal.
- Status: `off | disabled | offline | busy | queued | error | idle` (belum ada per-transaksi `pending/syncing/synced/failed`).
- Indikator UI: `#syncPill`, `#syncText` (topbar) dan kartu Integrasi `#supabaseStatus`/`#supabasePill` (Pengaturan).

### 2.4 Fitur yang bergantung pada Supabase
1. Sinkronisasi produk/kategori/pengaturan antar perangkat.
2. Sinkronisasi riwayat transaksi & antrean "Pesanan dibuat" antar perangkat.
3. Bootstrap cloud untuk perangkat baru.
Semua punya jalur lokal, jadi aplikasi **tetap jalan tanpa internet**; Supabase hanya lapisan berbagi antar perangkat.

---

## 3. Integrasi GoFood / GrabFood / ShopeeFood (hasil audit §12)

**Status: UI + data dummy saja. Tidak ada API resmi yang terpasang.**
- `ONLINE_PLATFORMS = { gofood, shopee, grab, maxim, other }` (label + warna).
- `DUMMY_ONLINE_ORDERS()` mengisi 3 pesanan contoh. Komentar kode: *"Belum ada API mitra"*.
- Fungsi ada: `normalizeOnlineOrder`, `resolveOnlineOrderItems` (utamakan `price` dari payload bila ada), `makePickupCode`, `renderOnlineTicket`.
- **Tidak ada**: endpoint mitra, webhook, kredensial, polling job, signature verification, mapping field platform.
- Ketergantungan Supabase: hanya lewat tabel generik `online_orders` (sama seperti tabel lain).

**Konsekuensi:** tidak ada integrasi nyata yang bisa "hilang". Yang harus dijaga adalah UI/antrean/alur (tab Online, filter, tiket, kode ambil). Tidak boleh mengarang endpoint/kredensial. Bila API resmi tidak tersedia untuk warung kecil, itu didokumentasikan sebagai batasan, bukan dibuat mock produksi.

---

## 4. Arsitektur baru yang diusulkan

```
[ APK / PWA: UI vanilla JS yang sama ]
        |  (hanya data lokal + antrean; tidak ada kredensial DB)
        v
[ Local DB: SQLite (native) / IndexedDB (web) ]  <-- repositori + transaksi lokal
        |  HTTPS + JWT (per-user token)
        v
[ Backend API: Node + Express + pg ]  <-- validasi, hitung ulang harga, idempotensi
        |  TLS, DATABASE_URL dari env (tidak pernah di frontend)
        v
[ Neon PostgreSQL ]  <-- skema relasional + migrasi berversi
```

Prinsip:
- Frontend **tidak pernah** memegang kredensial Neon; hanya token JWT pengguna.
- Server **menghitung ulang** harga/subtotal/pajak/total dari data produk di DB — tidak mempercayai angka dari klien.
- Setiap transaksi disimpan atomik (`BEGIN … COMMIT`) bersama detail item; nama & harga disimpan sebagai **snapshot** pada detail.
- Idempotensi: `client_txn_id` (UUID perangkat) `UNIQUE` → retry tidak menggandakan.
- Status transaksi: `pending → syncing → synced | failed`, dengan backoff.
- Peran: `kasir` (transaksi) dan `pemilik` (menu, laporan, pengaturan), divalidasi di server.

---

## 5. Rencana migrasi bertahap (dipetakan ke file nyata)

**Fase 1 — Audit & baseline** *(SELESAI sejauh bisa tanpa kredensial)*
- Dokumen ini + skrip ekspor `migration/export-supabase.js`.

**Fase 2 — Backup & persiapan DB** *(sebagian SELESAI)*
- ✅ Backup terverifikasi: `migration/backups/supabase-export-<stamp>.json` (27/6/1/6/6/3 baris).
- ⏳ Skema Neon + `migrations/001_init.sql`, script impor (butuh `DATABASE_URL` Neon).

**Fase 2b — Backup ulang sebelum cutover** (wajib, karena ada transaksi baru setelah migrasi).

**Fase 3 — Backend & migrasi data**
- `server/` (Express + `pg`): auth JWT, produk, kategori, settings, sync, transaksi.
- `migration/import-to-neon.js`: impor `payload` Supabase → skema relasional Neon, pertahankan id/timestamp.
- Ganti `sync.js` → klien `MPJSync` baru yang bicara ke backend (bukan Supabase), tetap API yang sama ke `pos.js`.

**Fase 4 — Local DB & sinkronisasi**
- Lapisan `www/js/localdb.js` (SQLite/IndexedDB) + antrean berstatus + UUID + backoff + rekonsiliasi stok.

**Fase 6 — Cutover & hapus Supabase** — hanya setelah uji terima lulus.

---

## 6. Risiko & hal yang BELUM bisa diverifikasi di lingkungan ini (jujur)

1. **Tidak ada kredensial Neon** → skema tidak bisa dijalankan, migrasi & sinkronisasi cloud tidak bisa diuji. Saya tidak akan mengklaim ini "selesai" tanpa bukti.
2. **Tidak ada hosting backend** → cutover produksi belum bisa dilakukan.
3. **SQLite di APK butuh plugin native** (`@capacitor-community/sqlite`) → perlu `npm install` (jaringan) + build ulang native; tidak tersedia untuk jalur PWA. Ini keputusan arsitektur.
4. **Tidak ada perangkat fisik** → uji 2 perangkat, stok bersamaan, dan printer tidak bisa dijalankan di sini.
5. **Autentikasi saat ini tidak aman** (sandi `1234` hardcoded). Migrasi akan memindahkannya ke server dengan hash; ini mengubah alur login.

---

## 7. Keputusan yang dibutuhkan sebelum menulis kode frontend/backend

Lihat pertanyaan yang diajukan bersamaan dengan dokumen ini.
