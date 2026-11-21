# Rencana Peralihan (Cutover) — Supabase → Neon + Backend IPOS

Dokumen ini adalah panduan bertahap untuk memindahkan POS Mie Pangsit Jakarta
dari Supabase ke **backend IPOS (Node + Express)** dengan **Neon PostgreSQL**,
tanpa menghentikan operasional warung.

Aturan emas:
1. **Supabase tetap sumber kebenaran** sampai migrasi terbukti benar.
2. Jangan hapus data apa pun dari Supabase sebelum verifikasi selesai.
3. Setiap tahap punya rencana mundur (rollback). Jangan lompat tahap.
4. Jangan melaporkan "berhasil" untuk langkah yang belum diuji di perangkat nyata.

---

## Ringkasan arsitektur

| Sebelum | Sesudah |
| --- | --- |
| Aplikasi → REST Supabase (kunci publik) | Aplikasi → REST backend IPOS + token JWT |
| Tabel generik `(id, payload jsonb, …)` | Skema relasional: `products`, `transactions`, `transaction_items`, `users`, dst. |
| Login di aplikasi (sandi `1234`) | Login di server (bcrypt + JWT, peran Pemilik/Kasir) |
| Harga dipercaya dari klien | Harga & total **dihitung ulang di server** |
| Antrean sinkron di `localStorage` | Antrean di **IndexedDB** dengan status & backoff |

Data lokal di perangkat tetap menjadi sumber utama saat offline (local-first).
Sinkronisasi hanya menyalin perubahan saat ada koneksi.

---

## Tahap 0 — Persiapan (tanpa mengubah apa pun)

- [ ] Cadangkan Supabase: `node migration/export-supabase.js`
      → periksa `migration/backups/supabase-export-*.json`.
- [ ] Hitung jumlah baris tiap tabel di backup (alat ini mencetaknya).
- [ ] Siapkan proyek Neon + connection string (pooled, `sslmode=require`).
- [ ] Siapkan `.env` backend dari `.env.example` (JWT_SECRET acak, sandi seed kuat).
- [ ] **Rollback tahap ini:** tidak ada (belum ada perubahan).

---

## Tahap 1 — Bangun & uji backend secara lokal

- [ ] `cd server && npm install`
- [ ] `npm run migrate` → tabel terbuat.
- [ ] `npm run seed` → akun Pemilik & Kasir terbuat.
- [ ] `npm run selftest` → semua uji lulus.
- [ ] `npm start` → `/api/health` membalas `{ ok: true }`.
- [ ] Uji manual dengan curl/REST: login, `/api/sync/pull?table=products`,
      `POST /api/orders` (transaksi contoh), `GET /api/orders`.
- [ ] **Rollback:** hentikan server, hapus branch Neon uji. Aplikasi belum tersentuh.

> Status di lingkungan pengembangan ini: migrasi/seed/impor **belum dijalankan**
> karena tidak ada `DATABASE_URL` dan tidak ada PostgreSQL/Docker. Yang sudah
> diuji: sintaks semua berkas, pemuatan modul, dan `npm run selftest` (9 uji).

---

## Tahap 2 — Impor data ke Neon (salin, bukan pindah)

- [ ] `cd server && npm run import:supabase`
- [ ] Bandingkan jumlah baris: `products`, `categories`, `settings`, `transactions`,
      `transaction_items` dengan backup Tahap 0.
- [ ] Periksa acak beberapa produk & transaksi (nama, harga, stok, tanggal).
- [ ] **Rollback:** kosongkan tabel Neon (`TRUNCATE … RESTART IDENTITY CASCADE`)
      dan impor ulang. Supabase belum berubah.

Catatan: tabel `orders`/`pending_orders`/`online_orders` di Supabase saat ini
berisi **tombstone** (sudah dihapus) sehingga tidak ada transaksi untuk dipindah.
Transaksi baru akan mengalir setelah aplikasi memakai backend.

---

## Tahap 3 — Uji aplikasi terhadap backend (satu perangkat uji)

- [ ] Deploy backend ke Render/Railway/Fly (atau jalankan lokal + tunnel).
- [ ] Di aplikasi uji: **Pengaturan → Server & pengguna → Alamat server** diisi URL backend.
- [ ] Keluar, lalu masuk memakai akun **server** (Pemilik).
- [ ] Periksa:
  - [ ] Katalog terisi (tidak kosong setelah sinkron pertama).
  - [ ] Buat satu transaksi uji → muncul di tabel `transactions` Neon.
  - [ ] Ubah satu harga produk → berubah di Neon.
  - [ ] Tambah pengguna Kasir → bisa masuk dan hanya melihat layar kasir.
  - [ ] Matikan internet → transaksi tetap tersimpan lokal, antre di IndexedDB.
  - [ ] Nyalakan internet → antrean terkirim otomatis (status "queued" → "Tersinkron").
- [ ] **Rollback:** kosongkan alamat server di Pengaturan → aplikasi kembali mode
      lokal; Supabase masih utuh.

---

## Tahap 4 — Uji dua perangkat (konflik stok & antrean)

- [ ] Perangkat A: jual 1 menu berstok; Perangkat B: lakukan hal sama sambil offline.
- [ ] Setelah keduanya online, periksa:
  - [ ] Stok di Neon berkurang sesuai total penjualan (tidak minus).
  - [ ] Ada baris `stock_movements` untuk tiap penjualan.
  - [ ] Bila stok sempat bentrok, ada catatan `audit_log` (`stock.conflict`).
  - [ ] Transaksi tidak pernah tergandakan (uji ulang / retry).
- [ ] Uji printer Bluetooth tetap berfungsi di perangkat nyata.
- [ ] **Rollback:** kembalikan alamat server ke kosong; data lokal tetap utuh.

> Status: pengujian dua perangkat & printer **belum** dilakukan di sini
> (tidak ada perangkat native). Wajib diuji sebelum cutover final.

---

## Tahap 5 — Cutover

- [ ] Bangun APK versi **12** (`versionCode 22`), pasang di perangkat.
- [ ] Isi alamat server di APK, masuk lewat server.
- [ ] Operasikan satu hari penuh. Bandingkan rekap penjualan aplikasi vs Neon.
- [ ] Pastikan cadangan Neon harian berjalan.
- [ ] **Rollback:** pasang kembali APK versi 11.3 (masih memakai Supabase) dan
      isi ulang alamat server ke kosong. Data lokal di perangkat tidak hilang.

---

## Tahap 6 — Menghapus Supabase (MANUAL, hanya setelah yakin)

> Jangan lakukan sebelum minimal **satu minggu** operasi stabil di backend baru
> dan cadangan Neon sudah diverifikasi bisa dipulihkan.

1. **Simpan arsip terakhir.** Buat satu cadangan Supabase terakhir dan simpan
   di luar perangkat (Google Drive/USB):
   `node migration/export-supabase.js`
2. **Pastikan tidak ada klien lama.** Semua perangkat sudah APK versi 12
   (tidak lagi menghubungi Supabase).
3. **Hentikan akses dari dashboard Supabase:**
   - Rotasi/revoke API key proyek (Project Settings → API).
   - Atau nonaktifkan proyek sementara dan pantau (jangan langsung hapus).
4. **Pantau 3–7 hari.** Bila tidak ada keluhan "data tidak sinkron" dari perangkat
   lama, lanjut.
5. **Hapus proyek Supabase:**
   - Dashboard Supabase → pilih proyek → **Settings → General → Delete project**.
   - Ketik nama proyek untuk konfirmasi. Tindakan ini **tidak bisa dibatalkan**.
6. **Bersihkan kode:** kode lama Supabase sudah tidak dipakai (aplikasi kini
   memanggil backend IPOS). Berkas `migration/export-supabase.js` boleh disimpan
   sebagai arsip (baca-saja) atau dihapus setelah arsip data aman.
7. **Catat di buku besar warung** tanggal cutover dan tanggal penghapusan.

---

## Daftar hal yang TIDAK boleh diklaim "selesai" sebelum diuji

- [ ] Migrasi & seed dijalankan terhadap Neon asli.
- [ ] Impor data diverifikasi jumlahnya.
- [ ] Sinkron dua arah di dua perangkat nyata.
- [ ] Konflik stok terdeteksi & rekonsiliasi.
- [ ] Printer Bluetooth tetap jalan.
- [ ] APK versi 12 dibangun, ditandatangani, dan dipasang.
- [ ] Cadangan Neon dibuat & diuji pulih.

Semua butir di atas menandai batas antara "sudah ditulis" dan "sudah terbukti".
