/* ===========================================================================
 * js/config.js — pengaturan alamat backend IPOS.
 * ----------------------------------------------------------------------------
 * Aplikasi kasir TIDAK memegang kredensial database apa pun. Satu-satunya
 * alamat yang disimpan di sini adalah alamat backend API (Node + Express)
 * yang menjadi jembatan aman ke Neon PostgreSQL.
 *
 * Kosongkan berarti "mode lokal" — aplikasi tetap jalan penuh, hanya tanpa
 * sinkronisasi antar-perangkat.
 * =========================================================================== */
(function () {
  'use strict';

  // Nilai bawaan bila belum diatur dari Pengaturan. Bisa diedit langsung di
  // sini saat membangun APK, atau diisi lewat Pengaturan di perangkat.
  const DEFAULT_API_BASE = '';
  const LS_KEY = 'mpj_api_base';

  function stored() {
    try { return (localStorage.getItem(LS_KEY) || '').trim(); } catch (e) { return ''; }
  }

  function normalize(value) {
    return String(value || '').trim().replace(/\/+$/, '');
  }

  window.MPJConfig = {
    tokenKey: 'mpj_api_token',
    getApiBase() {
      return normalize(stored() || DEFAULT_API_BASE);
    },
    setApiBase(value) {
      try { localStorage.setItem(LS_KEY, normalize(value)); } catch (e) { /* diabaikan */ }
    },
    isConfigured() {
      return Boolean(this.getApiBase());
    }
  };
})();
