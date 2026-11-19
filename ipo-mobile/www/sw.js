const CACHE_NAME = 'mpj-pos-v105';
// POS saja yang dipakai offline di tablet: logo + file POS.
// Halaman depan website sudah dihapus; aplikasi selalu masuk ke pos.html.
const APP_SHELL = [
  './pos.html',
  './css/pos.css',
  './css/android.css',
  './js/pos.js',
  './js/qrcode.js',
  './js/qris.js',
  './js/jsQR.js',
  './js/config.js',
  './js/localdb.js',
  './js/sync.js',
  './manifest.webmanifest',
  './assets/img/pangsitmie.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).then((response) => {
      const copy = response.clone();
      caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
      return response;
    }).catch(() => caches.match(event.request).then((cached) => cached || caches.match('./pos.html'))));
    return;
  }

  const requestUrl = new URL(event.request.url);
  if (requestUrl.origin !== self.location.origin) return;

  // Aset selalu diambil dari jaringan dulu supaya tampilan tidak pernah
  // campur versi lama-baru; kalau offline, baru pakai cadangan cache.
  event.respondWith(fetch(event.request).then((response) => {
    if (response.ok) {
      const copy = response.clone();
      caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
    }
    return response;
  }).catch(() => caches.match(event.request)));
});
