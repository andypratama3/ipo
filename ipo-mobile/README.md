# iPo Mie Pangsit — Mobile (Android / Capacitor)

Aplikasi kasir iPo Mie Pangsit versi Android. Ini adalah **pembungkus Capacitor 8**
dari folder `www/` yang sama dengan versi web/PWA, sehingga seluruh logika kasir,
QRIS offline, laporan, dan cadangan ada di satu sumber kode.

- App ID: `com.ipomiepangsit.pos`
- Nama aplikasi: `iPo Mie Pangsit`
- Versi saat ini: `versionCode 27` / `versionName 17` (`android/app/build.gradle`)
- Dokumen produk: [`PRD.md`](./PRD.md)

## Struktur

```
ipo-mobile/
├── www/                       # sumber web POS (HTML/CSS/JS, service worker, jsQR)
├── android/                   # proyek native Capacitor + plugin printer Bluetooth
├── capacitor.config.json
├── package.json
└── package-lock.json
```

File hasil build (`*.apk`, `android/app/build/`, `android/.gradle/`, aset yang
disalin Capacitor) **sengaja tidak disimpan di repo**. Demikian pula keystore,
`local.properties`, dan berkas `.env`.

## Menyiapkan build

```powershell
npm install
npx cap sync android
cd android
.\gradlew.bat assembleRelease
```

Hasil rilis ada di `android/app/build/outputs/apk/release/app-release.apk`.

### Menandatangani APK rilis

`android/app/build.gradle` **tidak** menyimpan kata sandi keystore. Siapkan
secara lokal (file ini tidak ikut terunggah):

```powershell
Copy-Item android\keystore\signing.properties.example android\keystore\signing.properties
```

Lalu isi `storePassword` dan `keyPassword` di `signing.properties`. Alternatif:
set environment variable `IPOS_KEYSTORE_PASSWORD` dan `IPOS_KEY_PASSWORD`.

File `ipomiepangsit.keystore` juga tidak ikut diunggah — harus disalin dari
pemiliknya secara pribadi. Tanpa keystore yang sama, APK baru dianggap aplikasi
berbeda oleh Android dan data lokal di HP tidak bisa dilanjutkan.

## Catatan penting

- Setiap perubahan `www/js/*.js` wajib menaikkan `?v=N` di `www/pos.html` dan
  `CACHE_NAME` di `www/sw.js`, kalau tidak perangkat lama memakai cache lama.
- Naikkan `versionCode`/`versionName` di `android/app/build.gradle` sebelum
  build rilis.
- Build APK hanya dilakukan atas perintah pemilik.
- Backend ada di repo yang sama, folder `ipo-backend/`.
