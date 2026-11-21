# Analisis + Prompt Big Pickle — Halaman Katalog Menu

Tanggal: 17 Oktober 2026
Referensi: foto tablet (landscape) halaman **Katalog Warung → Menu**
Kode yang dibandingkan: `www/pos.html` (view-menu), `www/js/pos.js`, `www/css/pos.css`, `www/css/style.css`

---

## 1. Temuan penting: bedanya itu disengaja

Halaman di foto memakai **grid kartu**. sementara hasil build sekarang memakai **tabel polos**.

Ini bukan bug. Di `www/js/pos.js` baris 3231–3232 ada catatan eksplisit:

```js
// v12: katalog menu selalu berupa tabel polos, sama seperti di layar lebar.
// Mode daftar kartu untuk layar sempit sudah dihapus agar tampilannya seragam.
```

Jadi grid kartu di foto itu adalah **mode lama (sebelum v12)** yang sengaja dihapus karena permintaan waktu itu: *"Katalog Menu = tabel polos di semua ukuran layar."*

Artinya: kalau mau balik ke gaya foto, itu **membatalkan keputusan v12** dan perlu builder (tabel) dimatikan. Saya tidak mengubah kode apa pun — hanya menulis prompt.

---

## 2. Analisis visual dari foto

### 2.1 Warna (hasil baca dari foto)

| Peran | Nilai estimasi |
|---|---|
| Latar aplikasi | `#F1F5F9` (abu-abu dingin sangat muda) |
| Permukaan kartu / panel | `#FFFFFF` |
| Garis / border | `#E2E8F0`, `#E8EDF3` |
| Aksen utama (tombol, harga, judul bagian) | `#2563EB` (biru royal) |
| Judul besar | `#0F172A` (navy hampir hitam) |
| Teks isi | `#334155` |
| Teks redup / label kecil | `#64748B`, `#94A3B8` |
| Bayangan | netral `rgba(15,23,42,0.04–0.06)` — **tidak** bernuansa biru |

### 2.2 Tipografi

- Sans modern geometris, ritme lebar. Di kode sekarang sudah pakai **Plus Jakarta Sans** — cocok dengan foto, tidak perlu diganti.
- Eyebrow: 11–12 px, weight 800, `letter-spacing: 0.14em`, uppercase, biru.
- Judul utama: 30–34 px, weight 800, navy.
- Nama menu: 16–17 px, weight 800, navy, clamp 2 baris.
- Deskripsi: 13 px, `line-height 1.5`, abu, clamp 2 baris.
- Label kecil (KATEGORI / HARGA JUAL): 10 px, weight 800, `letter-spacing 0.1em`, uppercase, `#94A3B8`.

### 2.3 Bentuk & jarak

- Grid 8 px. Radius: kartu 16 px, panel besar 20 px, tile ikon 12 px, tombol/filter **pill** (999 px).
- Bayangan sangat tipis dan lembut — kesan "soft UI", bukan material gelap.
- Jarak antar kartu 16–20 px, padding kartu 16–18 px.

### 2.4 Anatomi kartu menu (dari atas ke bawah)

1. **Baris meta atas** — kiri: label stok (`Tanpa batas`), kanan: badge status pill
   (`Tersedia` hijau `#DCFCE7`/`#15803D`, `Stok menipis` amber, `Habis` merah)
2. **Baris tombol ikon** — 3 tombol 44×44, latar `#F1F5F9`: mata (lihat), klip kertas (gambar), × (hapus)
3. **Blok identitas** — tile emoji 64×64 (`#F8FAFC` + border) di kiri; di kanan nama + deskripsi 2 baris
4. **Baris kaki** — border atas tipis, dua kolom: `KATEGORI` di kiri, `HARGA JUAL` di kanan (harga biru besar)

### 2.5 Isi contoh dari foto

| Nama | Deskripsi | Kategori | Harga | Status | Stok |
|---|---|---|---|---|---|
| Mie Pangsit Telur Puyuh | Pangsit dalam isi telur puyuh. | Mie Pangsit | Rp 25.000 | Tersedia | Tanpa batas |
| Mie Pangsit Komplit | Isi lengkap: Pentol, Telur Puyuh, dan Ceker. | Mie Pangsit | Rp 30.000 | Tersedia | Tanpa batas |
| Mie Kering (Level 1, 2, 3) | Mie kering dengan level kepedasan 1 sampai 3. | Mie Kering | Rp 20.000 | Tersedia | Tanpa batas |

---

## 3. Perbandingan: foto vs build sekarang

| Aspek | Foto (target) | Build sekarang (`pos.html`) |
|---|---|---|
| Penyajian menu | Grid kartu 3 kolom | **Tabel** 6 kolom |
| Judul halaman | Eyebrow `KATALOG WARUNG` + H1 `Menu` | Eyebrow `Katalog` + H2 `Menu warung` + paragraf |
| Klaster status kanan atas | `Shift aktif` (hijau), `Lokal` (indigo), tombol tema, tanggal | Tidak ada di halaman ini |
| Kartu statistik | 4 kartu + tile ikon pastel + angka besar | `menu-summary` — struktur & ikon **sudah sama** |
| Panel filter | Search + chip pills | Sudah sama |
| Jumlah menu | Tidak terlihat | Ada hint `25 menu` |
| Aksi per menu | 3 tombol ikon | Kolom `Aksi` |
| Stok | Label di dalam kartu | Kolom `Stok` |
| Harga | Label + nilai biru di kaki kartu | Kolom `Harga jual` |
| Aksen warna | Biru royal `#2563EB` | Teal/sky `#0EA5E9`, ink `#0C4A6E` |

Jadi perbedaannya besar karena dua hal: **tabel vs kartu**, dan nada warna teal vs biru royal.

---

## 4. Prompt untuk Big Pickle

Salin blok di bawah ini (bahasa Inggris — sebagian besar AI builder jauh lebih akurat dengan istilah desain dalam bahasa Inggris; semua teks antarmuka tetap bahasa Indonesia).

```
Build a single page: "Katalog Warung → Menu" (menu catalog management) for an Indonesian
food-stall POS called "iPo Mie Pangsit". Target device: Android tablet in LANDSCAPE
(~16:10), light theme only. Language of ALL UI copy: Indonesian. Currency: Indonesian
Rupiah with thousand separators, e.g. "Rp 25.000".

DESIGN LANGUAGE
Soft, airy "modern SaaS" UI. Everything rounded. Neutral cool shadows, NO blue-tinted
shadows. Generous whitespace. Cool light-gray canvas with pure-white floating cards.
Accent color is royal blue. Feel premium but friendly — not corporate, not playful.

COLOR TOKENS (use exactly these)
  --canvas        #F1F5F9   app background
  --surface       #FFFFFF   cards & panels
  --border        #E2E8F0   card borders
  --border-soft   #F1F5F9   internal dividers
  --accent        #2563EB   primary buttons, section title, price, active chip
  --accent-dark   #1D4ED8   hover / pressed primary
  --heading       #0F172A   titles & product names
  --body          #334155   descriptions
  --muted         #64748B   secondary labels
  --faint         #94A3B8   uppercase micro-labels
  --success       #16A34A   "Tersedia" dot & badge text
  --success-bg    #DCFCE7   "Tersedia" badge background
  --warn          #D97706   "Stok menipis" badge text
  --warn-bg       #FEF3C7   "Stok menipis" badge background
  --danger        #DC2626   "Habis" badge text
  --danger-bg     #FEE2E2   "Habis" badge background
  --tile-bg       #F1F5F9   icon-button background
  --shadow-sm     0 2px 8px rgba(15,23,42,.04)
  --shadow-md     0 8px 24px rgba(15,23,42,.06)

TYPOGRAPHY
Font family: "Plus Jakarta Sans" (fallback Inter / system-ui).
  eyebrow        11px / 800 / uppercase / letter-spacing .14em / --accent
  page title     32px / 800 / --heading / line-height 1.1
  section title  21px / 800 / --accent
  card number    24px / 800 / --heading
  card label     13px / 500 / --muted
  product name   16px / 800 / --heading
  description    13px / 1.5 / --muted
  micro label    10px / 800 / uppercase / letter-spacing .1em / --faint
  price          17px / 800 / --accent
  chip / button  14px / 600–700

RADII & SPACING
  8px spacing grid. Card radius 16px. Large panel radius 20px. Icon-tile radius 12px.
  All buttons, chips and badges are FULL PILLS (border-radius 999px).
  Card padding 16–18px. Grid gap 16–20px. Main page padding 24px.

LAYOUT — top to bottom

1) TOP BAR (white, sticky, 64px, padding 0 24px, bottom border --border)
   LEFT: hamburger icon button (3 lines, --heading, 44x44 tap target, no border).
   Next to it a title block, stacked:
     - eyebrow "KATALOG WARUNG"
     - title "Menu"
   RIGHT (single row, gap 16px, vertically centered):
     - status chip: 8px solid green dot (#16A34A) + text "Shift aktif", 13px / 600 / --body
     - status chip: 8px solid indigo dot (#6366F1) + text "Lokal", 13px / 600 / --body
     - icon button 40x40, radius 12px, white, 1px --border, sun / theme icon, --body
     - date text "Sabtu, 17 Okt 2026", 14px / 700 / --heading

2) SECTION HEADER (flex row, space-between, align center, margin 24px 0 18px)
   LEFT: "Menu warung" 21px / 800 / --accent
   RIGHT: two pill buttons, gap 10px
     - "🏷  Edit kategori"  -> ghost: white bg, 1px --border, --heading text, 14px / 600
     - "+ Tambah menu"     -> primary: --accent bg, white text, 14px / 700, --shadow-sm

3) STATISTICS ROW — grid, 4 equal columns (auto-fit minmax(200px,1fr)), gap 16px
   Each card: white, radius 16px, 1px --border, --shadow-sm, padding 18px 20px.
   Inside: horizontal — a 40x40 rounded-square icon tile (radius 12px) then a text block
   with a big number (24px / 800 / --heading) above a small label (13px / 500 / --muted).
   The four cards, with their exact tile colors:
     (a) tile #E0ECFF, icon #2563EB (list/grid icon) -> "25" / "menu terdaftar"
     (b) tile #FFF3D6, icon #F59E0B (check icon)     -> "25" / "bisa dijual"
     (c) tile #D9F5EA, icon #10B981 (exclamation)     -> "0"  / "stok menipis"
     (d) tile #FFE1E6, icon #EF4444 (x icon)          -> "0"  / "habis / nonaktif"

4) FILTER PANEL — one white card, radius 20px, 1px --border, --shadow-sm, padding 16px
   ONE row, align center, gap 16px, wraps on narrow screens.
   LEFT: search input, flex 1, min-width 260px, height 44px, radius 12px, white,
     1px --border, magnifier icon 18px #94A3B8 at 14px inset,
     placeholder "Cari nama menu..." 14px #94A3B8.
   RIGHT: pill chip group, height 40px, gap 8px, radius 999px:
     - "Semua"        ACTIVE  -> --accent bg, white text, 700
     - "Tersedia"      idle    -> white bg, 1px --border, --body text, 600
     - "Stok menipis"  idle    -> white bg, 1px --border, --body text, 600
     - "Nonaktif"      idle    -> white bg, 1px --border, --body text, 600

5) PRODUCT GRID — cards, NOT a table.
   `display:grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap:18px;`
   On a landscape tablet this renders as exactly 3 columns.
   Each product card is white, radius 16px, 1px --border, --shadow-sm, padding 16px,
   and is built from FOUR stacked zones:

   ZONE A — meta row (flex, space-between, align center)
     LEFT : stock label, 13px / 500 / --muted. Text is "Tanpa batas" when stock is
            unlimited, otherwise the remaining count, e.g. "Sisa 4".
     RIGHT: status badge, pill, 12px / 700, padding 4px 12px
              "Tersedia"      -> #DCFCE7 bg, #15803D text
              "Stok menipis"  -> #FEF3C7 bg, #B45309 text
              "Habis"         -> #FEE2E2 bg, #B91C1C text

   ZONE B — icon action row (flex, gap 10px, margin-top 10px, left aligned)
     Three 44x44 buttons, radius 12px, background --tile-bg, icon 18px #475569:
       eye       -> lihat detail
       paperclip -> ganti gambar
       x         -> hapus (icon #94A3B8)
     On hover the whole card lifts 2px and the shadow deepens.

   ZONE C — identity block (flex row, gap 14px, margin-top 14px)
     LEFT : 64x64 rounded-square (radius 16px, bg #F8FAFC, 1px #EEF2F7) holding a
            30px emoji for that product.
     RIGHT: product name 16px / 800 / --heading, clamped to 2 lines,
            then description 13px / 1.5 / --muted, clamped to 2 lines.

   ZONE D — footer meta (border-top 1px --border-soft, padding-top 12px, margin-top 14px,
            flex row, space-between, align end)
     LEFT : micro label "KATEGORI" then value "🥟 Mie Pangsit" 13px / 600 / --body
     RIGHT: micro label "HARGA JUAL" then value "Rp 25.000" 17px / 800 / --accent

6) SAMPLE DATA — use exactly these three products
     name "Mie Pangsit Telur Puyuh"     desc "Pangsit dalam isi telur puyuh."
       category "Mie Pangsit"  price 25000  emoji "🥚"  stock null  status "Tersedia"
     name "Mie Pangsit Komplit"        desc "Isi lengkap: Pentol, Telur Puyuh, dan Ceker."
       category "Mie Pangsit"  price 30000  emoji "🎯"  stock null  status "Tersedia"
     name "Mie Kering (Level 1, 2, 3)" desc "Mie kering dengan level kepedasan 1 sampai 3."
       category "Mie Kering"    price 20000  emoji "🍜"  stock null  status "Tersedia"
   Plus 22 more placeholder products so the four statistics read 25 / 25 / 0 / 0.

BEHAVIOUR
- Typing in the search box filters cards live by name or category (case-insensitive).
- Each filter chip filters the grid: Semua / Tersedia / Stok menipis / Nonaktif.
- Active chip is solid royal blue; the others are white with a light border.
- Empty result shows a centered muted message "Tidak ada menu yang cocok."
- All tap targets at least 44px. Whole card is not clickable; only the three icon buttons
  and the "+ Tambah menu" / "Edit kategori" buttons act.
- Accessible: chips are toggle buttons with aria-pressed, badges carry aria-label.

DELIVERABLE
Responsive HTML/CSS (Tailwind or plain CSS with the tokens above as CSS custom
properties). Must look correct at 1280x800, 1024x768 and 1440x900 landscape, and collapse
to 2 columns at <=900px and 1 column at <=560px. No data-table anywhere on this page.
```

---

## 5. Catatan kalau ingin langsung diterapkan ke iPo

Kalau ternyata Anda mau iPo memakai gaya kartu ini (bukan cuma prompt untuk Big Pickle), ada satu hal yang harus diputuskan lebih dulu:

- `www/js/pos.js:3223` `renderMenuTable()` menulis ke `#menuTableBody` (tabel).
- `www/pos.html` view-menu hanya punya `<table class="data-table menu-table">`.
- CSS `.menu-list` / kartu menu lama sudah dibuang saat v12.

Untuk balik ke kartu: tambah fungsi render baru (mis. `renderMenuCards()`), ganti markup
tabel jadi `<div id="menuCardGrid">`, tambahkan CSS kartu, dan **papus** aturan
"selalu tabel polos" di baris 3231–3232. Setelah ada perubahan `www/`, APK harus
dibuild ulang (tetap v12 / versionCode 22, tanda tangan sama).
