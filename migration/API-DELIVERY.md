# Cara Mendapatkan API GoFood, GrabFood, ShopeeFood

> Ditulis 17 Okt 2026. Semua tautan & aturan di bawah diambil dari **halaman
> resmi** masing-masing platform (GoBiz Developer Portal, Grab Developer Docs,
> ShopeeFood Open Platform). Kalau platform mengubah syarat, dokumen resmi
> yang berlaku.

---

## 0. Ringkasan 30 detik (baca ini dulu)

| Platform | Ada API resmi? | Siapa yang boleh akses | Tingkat kesulitan |
|---|---|---|---|
| **GoFood** | Ya — GoBiz API | Merchant GoBiz (self-serve, **Direct Integration**) **atau** POS/agregator sebagai **GoBiz Partner** (Facilitator Model) | Paling mungkin untuk kita |
| **GrabFood** | Ya — GrabFood POS API | Hanya **partner POS/integrasi** yang lolos onboarding Grab | Sulit (butuh approval) |
| **ShopeeFood** | Ya — ShopeeFood OpenAPI | **Vendor/ISV** yang lolos onboarding (VendorID + VendorSecret) | Sulit (butuh approval) |

Tiga hal penting yang harus dipahami lebih dulu:

1. **Tidak ada** API yang bisa dipakai dengan cara "daftar hari ini, besok dapat
   kunci" untuk umum. Ketiganya memberi akses lewat **program partner**.
2. Semua butuh **server HTTPS publik** (untuk menerima webhook pesanan).
   Neon itu **database**, bukan server — jadi tetap perlu hosting
   (Railway/Render/VPS/domain).
3. Ada **jalan pintas legal**: pakai **agregator resmi** yang sudah punya izin
   ketiga platform (daftar di bagian 6). Bayar bulanan, tapi tidak perlu
   membangun integrasi sendiri.

---

## 1. GoFood (Gojek / GoBiz) — paling realistis untuk kita

Portal: **https://developer.gobiz.com** (GoBiz Developer Portal)

### Dua model integrasi

**A. Direct Integration** — untuk merchant GoFood yang mau sistemnya bicara
langsung ke GoFood (host-to-host).

- Syarat: Anda sudah punya akun **GoBiz** (<https://gobiz.co.id/daftar>) dan
  masuk ke Developer Portal memakai **peran owner**.
- Cara dapat kunci: di Developer Portal → **"Create a new API integration"** →
  isi nama integrasi → halaman *credential & scope* → klik
  **Generate App ID & Secret** → Anda dapat `client_id` + `client_secret`.
- Di portal yang sama ada menu **Sandbox Test Account** → *Start here* untuk
  dibuatkan akun uji + **Outlet ID** sandbox (butuh produk GoFood + menu yang
  aktif di akun GoBiz Anda). Proses pembuatannya bisa perlu beberapa saat —
  klik **Refresh data** berkala.
- Catatan dari dokumen resmi: portal ini dinyatakan untuk **GoFood direct
  integration**; kalau Anda **POS atau OFA (agregator)**, dokumen mengarahkan
  ke **Facilitator Model**.
- Token: OAuth2.0 `grant_type=client_credentials`.

**B. Facilitator Model** — untuk penyedia POS / OFA yang melayani banyak
merchant.

- Harus jadi **GoBiz Partner** dulu (isi formulir kerja sama dari halaman
  Facilitator / hubungi tim GoBiz).
- Token: `grant_type=authorization_code` (menautkan outlet merchant) dan
  `client_credentials` untuk aksi berikutnya.
- Scope yang dipakai:
  `openid`, `offline`, `partner:outlet:read`, `partner:outlet:write`,
  `gofood:catalog:read`, `gofood:catalog:write`, `gofood:order:read`,
  `gofood:order:write`, `gofood:outlet:write`.

### Auth (kedua model, OAuth 2.0 Gojek)

```bash
curl -X POST "https://accounts.go-jek.com/oauth2/token" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --user 'CLIENT_ID:CLIENT_SECRET' \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "scope=gofood:order:read gofood:order:write gofood:catalog:read gofood:catalog:write"
```

Balasan: `{ "access_token": "...", "expires_in": 3600, "token_type": "Bearer", "scope": "..." }`

### Alur yang harus dibangun (sesuai dokumen "Food Integration")

1. Pastikan semua **outlet** terdaftar di GoBiz.
2. **Tautkan outlet** agar webhook pesanan sampai ke outlet yang benar:
   `PUT /integrations/partner/outlets/{outlet_id}/v1/link/gofood`
3. **Sinkron menu** (perhatikan: PUT = **menimpa** seluruh menu):
   - lihat menu: `GET  https://api.partner-sandbox.gobiz.co.id/integrations/gofood/outlets/{outlet_id}/v2/catalog`
   - kirim menu: `PUT  .../outlets/{outlet_id}/v1/catalog`
4. **Langganan event pesanan (webhook)** → pesanan masuk otomatis ke server kita.
5. Promo (opsional, kalau mau atur promo dari sistem sendiri).

Kalau integrasi sudah jalan, dokumen GoBiz menyatakan **tidak perlu lagi memasang
GoBiz app di outlet** (tapi mereka tetap menyarankan app sebagai cadangan).

Sandbox: `https://api.partner-sandbox.gobiz.co.id/...`

---

## 2. GrabFood — GrabFood POS API

Portal: **https://developer.grab.com** → Food → **GrabFood API** (versi 1.1.3)

Sifatnya **partner (POS) onboarding** — bukan self-serve. Gambaran langkahnya
(menurut dokumen Grab):

1. Klik **"Integrate now"** / hubungi tim Grab. Partner akan menerima
   *onboarding deck* + diberi **Integration Manager**.
2. Dibuatkan **project staging**; Anda menerima kredensial sandbox.
3. Bangun integrasi. **Webhook yang harus disediakan di sisi kita**:
   - *Push integration status* — Grab memberi tahu status integrasi outlet.
   - *Get menu* — Grab minta menu terbaru dari sistem kita.
   - *Submit orders* — **Grab mengirim detail pesanan** ke sistem kita.
   - *Push order state* — Grab mengabari perubahan status pesanan.
4. Uji di **staging**: `https://partner-api.grab.com/grabfood-sandbox`
5. Sertifikasi → **produksi**: `https://partner-api.grab.com`

SDK resmi (mempermudah): <https://github.com/grab/grabfood-api-sdk-python>

Kegunaan (kutipan dokumen): menghilangkan entri pesanan manual, menu selalu
sinkron, dan mempermudah rekonsiliasi pembayaran.

---

## 3. ShopeeFood — ShopeeFood Open Platform

Portal: **https://developer.shopeefood.co.id** (ada dokumentasi OpenAPI +
**Postman collection** yang bisa diunduh)

Sifatnya **vendor/ISV onboarding**: Anda dapat **VendorID** + **VendorSecret**.

- Environment:
  - Staging: `https://food-open.uat.shopee.co.id`
  - Produksi: `https://food-open.shopee.co.id`
- **Token**: `POST /api/adaptor/:vendor_id/v1/auth/token`
  Header wajib di semua request: `X-SF-RequestID`, `X-SF-AccessToken`,
  `X-SF-Timestamp`, `X-SF-AppID`.
- Contoh ambil katalog toko:
  `GET https://food-open.shopee.co.id/api/adaptor/stores/:store_id/catalogs`
- **Ubah status pesanan**: `PUT /api/adaptor/:vendor_id/v1/orders/:order_id`
  (dipakai untuk pesanan *merchant self delivery*).
- Ada **Submit Order - Light API**: versi ringkas data pesanan (hanya field
  penting) — lebih enak dipakai untuk merchant.
- Portalnya punya **log debug** bawaan: Order Submission Log, Order Receiving
  Log, Menu Sync Task, Store Status Log, Store Info Log — sangat membantu saat
  uji coba.

Untuk **jadi merchant** ShopeeFood (tidak perlu jadi developer) daftarnya lewat
aplikasi **Shopee Partner**: <https://www.shopeefood.co.id/en/merchants/about-merchants>

---

## 4. Checklist "apa yang saya harus siapkan"

**Legal & akun**

- NIB / akta perusahaan / NPWP (wajib kalau mau jadi partner resmi;
  beberapa program hanya menerima PT/CV, bukan perorangan).
- KTP pemilik, rekening bank atas nama pemilik, foto menu (JPG/PNG).
- Akun merchant aktif: **GoBiz**, **GrabMerchant**, **Shopee Partner**.

**Teknis**

- Domain + hosting **HTTPS publik** yang hidup 24 jam (webhook harus dijawab
  cepat, kalau lambat pesanan bisa gagal masuk).
- Log & pemantauan, sandbox → produksi, dan uji gagal/kirim ulang.
- **Pemetaan menu**: id menu di platform ↔ id produk di katalog iPo.
- Sertifikasi/uji terima dari masing-masing platform sebelum produksi.

**Waktu & biaya (perkiraan, tanyakan ke perwakilan platform)**

- GoFood: paling cepat (bisa minggu), karena ada jalur self-serve.
- GrabFood & ShopeeFood: proses partner, umumnya minggu sampai bulan.
- Platform biasanya tidak memungut biaya khusus API (yang ada: komisi per
  pesanan + biaya server/hosting Anda). Sebagian program partner bisa punya
  skema bagi hasil — pastikan saat pendaftaran.

---

## 5. Yang JANGAN dilakukan

- ❌ Jasa/script tidak resmi yang mengaku "bisa sambung GoFood/Grab/Shopee",
  apalagi yang **minta username & password akun merchant**. Itu melanggar
  ketentuan platform dan akun bisa ditutup.
- ❌ Otomasi layar (scraping aplikasi / ADB tap otomatis) untuk produksi:
  rapuh, gampang terdeteksi, dan tetap melanggar ketentuan.
- ❌ Memakai akun orang lain / data merchant orang lain — pelanggaran berat.

---

## 6. Jalan pintas legal: agregator/middleware resmi

GoBiz mencantumkan daftar **GoBiz Authorized Partners** di halaman resminya:

> Hubster · klikit · majoo · Runchise · ESB · Mokapos · iSeller · Ravintola ·
> vireo · HashMicro

Cara kerja: Anda tidak menghubungi GoFood/Grab/ShopeeFood, tapi menghubungi
agregator ini. Mereka sudah punya izin resmi ke platform, dan meneruskan
pesanan ke sistem Anda lewat API/webhook mereka (satu integrasi untuk semua
channel).

- ➕ Cepat, tidak perlu urus approval 3 platform, menu & status tersinkron.
- ➖ Bayar bulanan (biasanya per outlet), data lewat pihak ketiga, dan sistem
  kita harus mengikuti API mereka (bukan API asli platform).

Beberapa nama di daftar itu juga penjual POS (majoo, iSeller, ESB, Mokapos,
Runchise) — tanyakan apakah mereka mau melayani **POS pihak lain** atau hanya
POS mereka sendiri.

---

## 7. Menempel ke aplikasi iPo (kesiapan di sisi kita)

Kabar baik: **aplikasi kita sudah siap secara struktur.** Tabel `online_orders`
sudah ada dan sudah ikut sinkron.

- Tabel di Neon (`server/migrations/001_init.sql`):
  `online_orders (id TEXT PRIMARY KEY, payload JSONB, updated_at, deleted, device_id)`
- Sinkron: `server/src/services/sync.js` (whitelist `online_orders`) →
  ditarik aplikasi lewat `/api/sync` → `www/js/pos.js` mengubahnya menjadi
  daftar "Pesanan Online".

Jadi integrasi platform **tidak perlu mengubah UI kasir**: webhook cukup
menulis/memperbarui baris di `online_orders` dengan bentuk `payload` seperti ini:

```json
{
  "id": "ONL-GF-2174",
  "source": "gofood",
  "code": "GF-2174",
  "customer": "Dina",
  "note": "Pedas level 2",
  "status": "baru",
  "createdAt": "2026-10-17T05:22:00.000Z",
  "items": [
    { "productId": "pangsit-original", "qty": 2 },
    { "productId": "teh-es-panas", "qty": 2 }
  ]
}
```

Aturan penting:

- `source` harus salah satu: `gofood`, `grab`, `shopee` (label & filter di UI
  mengikuti ini).
- `status` mengikuti alur kasir: `baru` → `dibuat` → `siap`; setelah "Selesai
  diambil" pesanan pindah ke transaksi/laporan.
- `productId` **harus sama** dengan id produk di katalog iPo. Karena itu perlu
  tabel pemetaan menu platform ↔ menu iPo (menyimpan id menu platform per
  outlet). Ini bagian yang paling sering bikin repot — kerjakan sejak awal.

Endpoint yang **sudah dibuat** (17 Okt 2026) di `server/src/routes/`:

- `POST /api/webhooks/gofood` → terima notifikasi pesanan GoBiz → normalisasi →
  tulis ke `online_orders` (tabel yang sudah disinkronkan ke kasir).
- Aksi balik: **terima** (`accepted`), **tolak** (`cancelled`), **siap ambil**
  (`food-prepared`) — dikirim dari antrean `online_order_actions`.
- Keamanan: verifikasi `X-Go-Signature` (HMAC-SHA256 body mentah) wajib;
  setiap notifikasi disimpan mentah di `webhook_events`; idempotency key mitra
  mencegah pesanan kembar.
- Adapter Grab/ShopeeFood belum dibuat (route-nya sudah siap menerima, tetapi
  pengiriman aksi masih khusus GoFood).

---

## 8. Kalau butuh jalan hari ini (paling cepat, 0 risiko)

1. Terima pesanan lewat aplikasi resmi masing-masing di HP
   (**GoBiz** / **GrabMerchant** / **Shopee Partner**).
2. Kasir memasukkan pesanan ke iPo → tab **Pesanan Online** (sudah lengkap:
   status Baru → Dibuat → Siap diambil, tombol maju, **Cetak struk pelanggan**,
   **Batalkan pesanan**).
3. Integrasi API resmi dikerjakan **paralel** (mulai dari GoFood, karena ada
   jalur self-serve).

---

## 9. Sumber resmi (diverifikasi 17 Okt 2026)

- GoFood / GoBiz
  - Facilitator Model: <https://developer.gobiz.com/docs/docs/food-integration/facilitator/>
  - Authentication (OAuth2): <https://developer.gobiz.com/docs/docs/authentication/>
  - Mengenal GoBiz Developer Portal: <https://developer.gobiz.com/docs/docs/introducing-to-gobiz-developer-portal/>
  - Alur Food Integration: <https://developer.gobiz.com/docs/api/food-integration>
  - Daftar akun GoBiz: <https://gobiz.co.id/daftar>
- GrabFood
  - Panduan POS API: <https://developer.grab.com/docs/grabfood/api/v1-1-3/>
  - Halaman produk: <https://developer.grab.com/products/food-pos-model>
  - SDK: <https://github.com/grab/grabfood-api-sdk-python>
- ShopeeFood
  - Open Platform: <https://developer.shopeefood.co.id>
  - Dokumen API: <https://developer.shopeefood.co.id/vendor/api-docs>
  - Daftar merchant: <https://www.shopeefood.co.id/en/merchants/about-merchants>
- GoFood — rujukan teknis yang dipakai saat membuat adapter (diverifikasi 17 Okt 2026)
  - Terima order: `PUT /integrations/gofood/outlets/{outlet_id}/v1/orders/{order_type}/{order_id}/accepted`
  - Tolak order: `.../cancelled` — body `{ cancel_reason_code, cancel_reason_description }`
    (kode: `HIGH_DEMAND`, `RESTAURANT_CLOSED`, `ITEMS_OUT_OF_STOCK`, `OTHERS`)
  - Siap ambil: `.../food-prepared` — body `{ "country_code": "ID" }`
  - Daftar event: <https://developer.gobiz.com/docs/api/event-list>
  - Verifikasi webhook: <https://developer.gobiz.com/docs/api/webhooks/receiving-notifications>
  - Bentuk payload & objek: <https://developer.gobiz.com/docs/api/objects-glossary>

---

## 10. Apa yang SUDAH disiapkan di iPo (17 Okt 2026)

### Berkas baru

| Berkas | Guna |
| --- | --- |
| `server/migrations/002_online_integration.sql` | Tabel `online_menu_map`, `webhook_events`, `online_order_actions` |
| `server/src/services/online.js` | Normalisasi payload mitra, pencocokan menu, simpan ke `online_orders`, antrean aksi |
| `server/src/services/gofood.js` | Adapter GoFood (OAuth2 + terima/tolak/siap) sesuai dokumen resmi |
| `server/src/routes/webhooks.js` | `POST /api/webhooks/gofood` (+ grab/shopee) — publik, wajib tanda tangan |
| `server/src/routes/online.js` | Endpoint pemilik: pesanan, pemetaan menu, antrean aksi, log webhook |
| `server/scripts/mock-gofood-order.js` | Kirim webhook GoFood palsu untuk uji tanpa akun GoBiz |

### Alur yang sudah jalan

```
GoBiz  --webhook-->  /api/webhooks/gofood
                        |  (verifikasi X-Go-Signature, log mentah, cegah duplikat)
                        v
                 cocokkan menu mitra -> produk iPo (online_menu_map + cocok nama)
                        v
                 tulis ke online_orders  --sinkronisasi-->  kasir (tab Pesanan Online)
                        ^
   kasir menekan Terima / Siap  --> online_order_actions --> PUT ke GoFood
```

Status pesanan di kasir diterjemahkan menjadi aksi ke GoFood:

| Di kasir | Ke GoFood |
| --- | --- |
| Terima (`baru` → `dibuat`) | `accept` |
| Siap diambil (`dibuat` → `siap`) | `ready` (`food-prepared`) |
| Tolak pesanan yang masih `baru` | `reject` (`cancelled`) |
| Pesanan yang sudah diterima lalu hilang dari daftar | **tidak dikirim** (bisa berarti selesai — server tidak menebak) |

Untuk membatalkan pesanan **setelah** diterima, lakukan di aplikasi GoBiz
sampai aplikasi kasir punya tombol batal khusus yang mengirim sinyal eksplisit.

### Yang perlu Anda isi di `server/.env`

```
GOFOOD_CLIENT_ID=...            # dari GoBiz Developer Portal
GOFOOD_CLIENT_SECRET=...
GOFOOD_OUTLET_ID=...            # outlet GoFood (sandbox dulu)
GOFOOD_NOTIFICATION_SECRET=...  # untuk memverifikasi webhook
GOFOOD_AUTO_ACCEPT=0            # 1 = terima otomatis
GOFOOD_REJECT_REASON_CODE=OTHERS
```

### Cara menguji sekarang (tanpa akun GoBiz)

```bash
cd server
npm run migrate                       # bikin tabel baru (butuh DATABASE_URL asli)
node scripts/mock-gofood-order.js     # kirim webhook contoh
node scripts/mock-gofood-order.js --unsigned   # pastikan tanda tangan palsu ditolak (401)
npm run selftest                      # uji logika (tanpa database)
```

Sudah **terbukti** tanpa database: tanda tangan palsu/kosong ditolak **401**,
`GET /api/health` normal, dan `npm run selftest` **19 uji lulus** (termasuk
normalisasi payload GoFood, pencocokan menu, dan terjemahan status → aksi).

Belum terbukti (menunggu `DATABASE_URL` Neon asli): penulisan `online_orders`,
pencatatan pemetaan menu, antrean aksi, dan pengiriman sungguhan ke GoFood
(menunggu kredensial portal + server HTTPS publik untuk webhook).
