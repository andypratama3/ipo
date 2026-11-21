# Integrasi GoFood — Panduan Setup (dokumen resmi GoBiz)

Dokumen ini adalah langkah demi langkah mengaktifkan pesanan GoFood di iPo Mie
Pangsit, mengikuti dokumentasi resmi GoBiz Developer Portal:
<https://developer.gobiz.com/docs/api/intro>

## Ringkasan cara kerja

```
GoBiz ──notifikasi (webhook)──► server iPo ──► daftar pesanan di kasir
   ▲                                │
   └───── aksi (terima/tolak/siap) ─┘  lewat antrean online_order_actions
```

- Pesanan masuk lewat webhook, diverifikasi tanda tangan HMAC, lalu muncul di
  daftar pesanan kasir (status: Baru → Dibuat → Siap).
- Aksi kasir (Terima/Tolak/Tandai Siap) dikirim balik ke GoFood lewat antrean —
  tidak langsung — supaya tidak ada aksi hilang kalau jaringan/ token bermasalah.
- Pembatalan/penyelesaian dari sisi GoFood menutup pesanan (hapus dari daftar),
  tanpa mengirim aksi balik, dan **tidak mengembalikan stok** (aturan lama).

## Langkah 1 — Dapatkan kredensial (sekali saja)

1. Login ke <https://developer.gobiz.com> memakai akun GoBiz **peran owner**.
2. Buat integrasi baru: **"Create a new API integration"**.
3. Catat: `client_id`, `client_secret`, dan `notification secret`.
4. Untuk uji coba, aktifkan **sandbox** dulu (akun GoFood sandbox / outlet
   uji coba). Dokumen sandbox memakai:
   - Auth: `https://integration-goauth.gojekapi.com/oauth2/token`
   - API: `https://api.partner-sandbox.gobiz.co.id`
   - Produksi (setelah yakin): auth `https://accounts.go-jek.com/oauth2/token`,
     API `https://api-partner.gojekapi.com`

> **Penting — parameter `scope`.** Menurut dokumen GoBiz *Direct Integration*,
> token yang diminta **tanpa `scope`** diterbitkan **tanpa hak akses apa pun**.
> Nilai bawaan server sudah benar (lihat `GOFOOD_SCOPE` di `.env.example`);
> ubah hanya bila GoBiz memberi instruksi lain.

## Langkah 2 — Isi `server/.env`

Salin dari `.env.example` lalu isi:

```
GOFOOD_CLIENT_ID=...
GOFOOD_CLIENT_SECRET=...        # dari GoBiz Developer Portal
GOFOOD_OUTLET_ID=...            # id outlet GoBiz, mis. G123456789
GOFOOD_NOTIFICATION_SECRET=...  # untuk verifikasi X-Go-Signature
GOFOOD_WEBHOOK_URL=https://DOMAIN-ANDA/api/webhooks/gofood
```

`GOFOOD_WEBHOOK_URL` harus **URL publik HTTPS**. Server lokal di 8080 tidak
terjangkau GoBiz — perlu hosting publik atau terowongan (mis. Cloudflare
Tunnel) sebelum langganan bisa diuji sungguhan.

## Langkah 3 — Verifikasi koneksi

Dengan token pemilik (login aplikasi):

```
GET /api/online/gofood/cek
```

Ini memanggil `linked-outlets` dan `token-info` milik GoBiz — kalau kredensial
& scope benar, daftar outlet tertaut tampil di situ. Kalau kosong/error, periksa
kembali `client_id`/`client_secret`/`GOFOOD_OUTLET_ID`.

## Langkah 4 — Langgankan notifikasi

GoBiz hanya mengirim notifikasi untuk event yang **dilanggani**:

```
POST /api/online/gofood/langganan
```

Server mendaftarkan 9 event pesanan (`gofood.order.created`,
`awaiting_merchant_acceptance`, `merchant_accepted`, `prep_order_now`,
`driver_otw_pickup`, `driver_arrived`, `placed`, `completed`, `cancelled`) ke
`GOFOOD_WEBHOOK_URL`. Langganan yang sudah ada (event + URL sama) dilewati,
jadi perintah ini aman dijalankan berulang. Daftar langganan bisa dilihat
lewat `GET /api/online/gofood/cek`.

## Langkah 5 — Uji webhook

1. **Uji tanpa GoFood:** kirim notifikasi palsu ke `/api/webhooks/gofood`
   dengan tanda tangan yang benar (lihat `verifyGofoodSignature` — HMAC-SHA256
   hex dari body mentah dengan `GOFOOD_NOTIFICATION_SECRET`). Pesanan harus
   muncul di daftar kasir.
2. **Uji sungguhan:** di sandbox GoFood, buat pesanan uji coba; pesanan harus
   muncul di aplikasi kasir dalam hitungan detik. Tekan **Terima** → periksa
   log `webhook_events` & antrean `online_order_actions` di
   `GET /api/online/webhooks` dan `GET /api/online/actions`.

## Catatan perilaku (sudah sesuai dokumen GoBiz)

- **Duplikat:** notifikasi bisa dikirim lebih dari sekali; server mendedupe
  lewat `event_id` (tanda tangan tetap diverifikasi).
- **Status tidak mundur:** event terlambat (mis. `created` menyusul setelah
  kasir sudah menekan Terima) tidak mereset status pesanan.
- **Pembatalan/penyelesaian dari GoFood** (pelanggan/Gojek/batas waktu) menutup
  pesanan di daftar kasir tanpa aksi balik. Alasan batal ikut tercatat.
- **PIN kurir** (`order.pin`) ditampilkan di catatan pesanan — cocokkan dengan
  kurir sebelum menyerahkan makanan.
- **Pesanan ambil-sendiri** dikenali dari `service_type: "gofood_pickup"`.
- **Respons GoBiz** `{ success, data, errors }` dibaca penuh; sukses-HTTP-tapi-
  `success:false` tetap dianggap gagal dan muncul di pesan error.

## Checklist sebelum produksi

- [ ] Kredensial produksi (bukan sandbox) diisi; `GOFOOD_AUTH_URL` &
      `GOFOOD_API_BASE` diganti sesuai produksi.
- [ ] `GOFOOD_WEBHOOK_URL` HTTPS publik aktif dan diuji dari luar.
- [ ] Langganan event dijalankan ulang setelah ganti URL.
- [ ] Pemetaan menu GoFood ↔ produk iPo diperiksa (`/api/online/menu-map` +
      "cocokkan otomatis").
- [ ] Pesanan uji coba diterima & ditolak dari aplikasi kasir dengan benar.
