/* ===========================================================================
 * js/sync.js — Sinkronisasi antar-perangkat POS Mie Pangsit Jakarta
 * ----------------------------------------------------------------------------
 * Aplikasi tidak lagi menghubungi Supabase. Semua lalu lintas melewati
 * backend IPOS (Node + Express), yang menyimpan ke Neon PostgreSQL.
 * Tidak ada kredensial database di berkas ini — hanya token sesi pengguna.
 *
 * Cara kerja (local-first, tetap seperti semangat POS ini):
 *   1. Aplikasi jalan penuh tanpa internet — data lokal selalu utuh.
 *   2. Setiap perubahan lokal masuk antrean di IndexedDB (js/localdb.js) dengan
 *      status pending/syncing/synced/failed, lalu dikirim begitu bisa.
 *   3. Transaksi (orders) punya jalur khusus ke POST /api/orders; server
 *      menghitung ulang harga & total, jadi retry tidak menggandakan.
 *   3. Berkala aplikasi menarik baris baru (GET /api/sync/pull) lalu
 *      menyatukannya ke data lokal.
 *   4. Konflik katalog diselesaikan "baris terakhir menang" (updated_at server).
 *
 * Bentuk API tetap sederhana untuk dipakai pos.js tanpa mengikatnya ke backend.
 * =========================================================================== */
(function () {
  'use strict';

  const TABLES = ['products', 'categories', 'settings', 'orders', 'pending_orders', 'online_orders'];
  const EPOCH = '1970-01-01T00:00:00.000Z';
  const PULL_MS = 45000;
  const PUSH_DELAY_MS = 1500;
  const TIMEOUT_MS = 20000;
  const LIMIT = 1000;
  const MAX_BACKOFF_MS = 5 * 60 * 1000;
  const LS = {
    device: 'mpj_sync_device_id',
    cursor: 'mpj_sync_cursor',
    lastAt: 'mpj_sync_last_at',
    enabled: 'mpj_sync_enabled'
  };

  const hooks = { onRows: null, onStatus: null, getEntries: null };
  let queue = {};      // table -> { id: baris yang menunggu dikirim }
  let pushed = {};     // table -> { id: JSON payload terakhir yang sudah sinkron }
  let deviceId = '';
  let started = false;
  let busy = false;
  let error = '';
  let bootstrapChecked = false;
  let pushTimer = null;
  let pullTimer = null;
  let retryTimer = null;
  let backoffMs = 0;

  /* ---------- util kecil ---------- */
  function lsGet(key, fallback) {
    try { const v = localStorage.getItem(key); return v === null ? fallback : v; } catch (e) { return fallback; }
  }
  function lsSet(key, value) { try { localStorage.setItem(key, value); } catch (e) { /* diabaikan */ } }
  function safeJson(value) { try { return JSON.stringify(value); } catch (e) { return ''; } }
  function apiBase() {
    try { return (window.MPJConfig && window.MPJConfig.getApiBase()) || ''; } catch (e) { return ''; }
  }
  function token() {
    try { return localStorage.getItem('mpj_api_token') || ''; } catch (e) { return ''; }
  }
  function configured() { return Boolean(apiBase() && token()); }
  function isOffline() { return typeof navigator !== 'undefined' && navigator.onLine === false; }

  function localdb() {
    if (typeof window !== 'undefined' && window.MPJLocalDB) return window.MPJLocalDB;
    return {
      queueRows: async () => 0,
      loadQueue: async () => [],
      removeRows: async () => 0,
      markRows: async () => 0,
      outboxKey: (table, id) => `${table}:${id}`
    };
  }
  function outboxKey(table, id) { return localdb().outboxKey(table, id); }

  function ensureDevice() {
    let id = lsGet(LS.device, '');
    if (!id) {
      id = 'dev-' + Math.random().toString(36).slice(2, 10);
      lsSet(LS.device, id);
    }
    return id;
  }

  /* ---------- status untuk ditampilkan aplikasi ---------- */
  function queuedCount() {
    return TABLES.reduce((sum, table) => sum + (queue[table] ? Object.keys(queue[table]).length : 0), 0);
  }

  function status() {
    const queued = queuedCount();
    let state = 'idle';
    if (!started) state = 'off';
    else if (!isEnabled()) state = 'disabled';
    else if (!configured()) state = 'off';       // belum ada server/token -> mode lokal
    else if (isOffline()) state = 'offline';
    else if (busy) state = 'busy';
    else if (error) state = 'error';
    else if (queued) state = 'queued';
    return { state, queued, lastAt: lsGet(LS.lastAt, ''), error, deviceId, tables: TABLES.length, base: apiBase() };
  }
  function emit() {
    if (typeof hooks.onStatus === 'function') {
      try { hooks.onStatus(status()); } catch (e) { /* UI tidak boleh mematikan sync */ }
    }
  }

  /* ---------- permintaan jaringan dengan batas waktu + token ---------- */
  async function request(path, options) {
    const base = apiBase();
    if (!base) throw new Error('Alamat server belum diatur.');
    const canAbort = typeof AbortController === 'function';
    const ctrl = canAbort ? new AbortController() : null;
    const timer = ctrl ? setTimeout(() => { try { ctrl.abort(); } catch (e) { /* diabaikan */ } }, TIMEOUT_MS) : null;
    try {
      const headers = Object.assign({ 'Content-Type': 'application/json' }, (options && options.headers) || {});
      const t = token();
      if (t) headers.Authorization = 'Bearer ' + t;
      const res = await fetch(apiBase() + path, Object.assign({}, options, { headers, signal: ctrl ? ctrl.signal : undefined }));
      if (!res.ok) {
        let detail = '';
        try { const body = await res.json(); detail = body && body.error ? body.error : ''; } catch (e) { /* tanpa badan JSON */ }
        const err = new Error('HTTP ' + res.status + (detail ? ' — ' + detail : ''));
        err.status = res.status;
        throw err;
      }
      return res;
    } finally {
      if (timer) clearTimeout(timer);
    }
  }

  /* ---------- ANTREAN KIRIM (perubahan lokal -> server) ----------
     `entries` selalu [{ id, payload }] mewakili DAFTAR LENGKAP satu tabel,
     supaya baris yang hilang dari daftar bisa ditandai hapus (tombstone). */
  function pushList(table, entries) {
    if (!started || !isEnabled() || !Array.isArray(entries)) return 0;
    const q = queue[table] || (queue[table] = {});
    const pm = pushed[table] || (pushed[table] = {});
    const live = new Set();
    const newRows = [];
    let added = 0;

    entries.forEach((entry) => {
      if (!entry || entry.id === undefined || entry.id === null || !entry.payload) return;
      const id = String(entry.id);
      live.add(id);
      const json = safeJson(entry.payload);
      if (pm[id] === json) return; // tidak berubah sejak terakhir terkirim
      q[id] = { id, payload: entry.payload, deleted: false, device_id: deviceId };
      newRows.push({ table, id, payload: entry.payload, deleted: false, deviceId });
      added += 1;
    });

    // Baris yang dulu ada tetapi kini hilang -> tombstone. Baris yang dibuat
    // lalu dihapus SEBELUM sempat terkirim dibuang diam-diam.
    Object.keys(q).forEach((id) => {
      if (!live.has(id) && !pm[id] && !q[id].deleted) delete q[id];
    });
    Object.keys(pm).forEach((id) => {
      if (!live.has(id) && !q[id]) {
        q[id] = { id, payload: { id }, deleted: true, device_id: deviceId };
        newRows.push({ table, id, payload: { id }, deleted: true, deviceId });
        added += 1;
      }
    });

    if (added) {
      localdb().queueRows(newRows).catch(() => { /* antrean lokal gagal ditulis — sync dicoba lagi */ });
      emit();
      schedulePush();
    }
    return added;
  }

  function schedulePush() {
    if (!started || !isEnabled() || !configured()) return;
    if (pushTimer) clearTimeout(pushTimer);
    pushTimer = setTimeout(() => { pushTimer = null; syncNow(); }, PUSH_DELAY_MS);
  }

  function scheduleRetry() {
    if (!started || !isEnabled()) return;
    backoffMs = Math.min(backoffMs ? backoffMs * 2 : PUSH_DELAY_MS, MAX_BACKOFF_MS);
    if (retryTimer) clearTimeout(retryTimer);
    retryTimer = setTimeout(() => { retryTimer = null; syncNow(); }, backoffMs);
  }

  async function removeQueueRow(table, row) {
    if (queue[table]) delete queue[table][row.id];
    const pm = pushed[table] || (pushed[table] = {});
    if (row.deleted) delete pm[row.id];
    else pm[row.id] = safeJson(row.payload);
    try { await localdb().removeRows([outboxKey(table, row.id)]); } catch (e) { /* diabaikan */ }
  }

  async function markRowsFailed(table, rows, err) {
    const keys = rows.map((row) => outboxKey(table, row.id));
    const nextAt = Date.now() + Math.max(backoffMs, PUSH_DELAY_MS);
    try {
      await localdb().markRows(keys, {
        status: 'failed',
        lastError: String((err && err.message) || err).slice(0, 200),
        nextAt
      });
    } catch (e) { /* diabaikan */ }
  }

  /* Kirim satu tabel transaksi.
     v12: transaksi boleh dihapus oleh pemilik (miss pembayaran). Tombstone
     dikirim ke DELETE /api/orders/:id supaya server menandai deleted = true,
     lalu perangkat lain ikut menghapusnya saat menarik data. */
  async function flushOrders(rows) {
    for (const row of rows) {
      if (row.deleted) {
        try {
          await request('/api/orders/' + encodeURIComponent(row.id), { method: 'DELETE', body: JSON.stringify({ deviceId }) });
        } catch (e) {
          // 404 = sudah tidak ada di server, anggap selesai. Selain itu dilempar
          // ke pemanggil agar dicoba lagi (atau dibuang bila 403).
          if (!e || e.status !== 404) throw e;
        }
        await removeQueueRow('orders', row);
        continue;
      }
      await request('/api/orders', { method: 'POST', body: JSON.stringify({ order: row.payload, deviceId }) });
      await removeQueueRow('orders', row);
    }
  }

  async function flush() {
    if (!configured() || isOffline()) { emit(); return false; }
    const tables = Object.keys(queue).filter((table) => queue[table] && Object.keys(queue[table]).length);
    if (!tables.length) return true;

    for (const table of tables) {
      const rows = Object.values(queue[table]);
      try {
        if (table === 'orders') {
          await flushOrders(rows);
        } else {
          await request('/api/sync/push', {
            method: 'POST',
            body: JSON.stringify({ table, rows, deviceId })
          });
          for (const row of rows) await removeQueueRow(table, row);
        }
        error = '';
        backoffMs = 0;
        notifyRows(table, rows);
      } catch (e) {
        const status = e && e.status;
        // 403 berarti peran pengguna saat ini memang tidak boleh menulis tabel
        // ini (mis. kasir vs katalog). Menunggu tidak akan menolong dan justru
        // memacetkan tabel lain (transaksi!), jadi baris dibuang dari antrean
        // lokal lalu lanjut. Data aslinya tetap ada di localStorage.
        if (status === 403) {
          for (const row of rows) {
            if (queue[table]) delete queue[table][row.id];
            try { await localdb().removeRows([outboxKey(table, row.id)]); } catch (dropError) { /* diabaikan */ }
          }
          error = String((e && e.message) || e);
          emit();
          continue;
        }
        error = String((e && e.message) || e);
        await markRowsFailed(table, rows, e);
        scheduleRetry();
        emit();
        return false; // berhenti dulu, coba lagi nanti — jangan membanjiri server
      }
    }
    emit();
    return true;
  }

  function notifyRows(table, rows) {
    if (typeof hooks.onRows !== 'function') return;
    const payload = rows.map((row) => ({
      id: row.id, payload: row.payload, deleted: !!row.deleted,
      updated_at: null, device_id: row.device_id || deviceId
    }));
    try { hooks.onRows(table, payload); } catch (e) { /* aplikasi menolak baris */ }
  }

  /* ---------- TARIK (server -> data lokal) ---------- */
  async function pull() {
    if (!configured() || isOffline()) { emit(); return; }
    const cursor = lsGet(LS.cursor, EPOCH);
    const isFirst = cursor === EPOCH;
    const emptyTables = [];
    let maxTs = cursor;
    let total = 0;

    for (const table of TABLES) {
      try {
        const res = await request(
          '/api/sync/pull?table=' + encodeURIComponent(table) +
          '&cursor=' + encodeURIComponent(cursor) +
          '&limit=' + LIMIT
        );
        const body = await res.json();
        const rows = body && Array.isArray(body.rows) ? body.rows : [];
        if (!rows.length) {
          if (isFirst) emptyTables.push(table);
          continue;
        }
        total += rows.length;
        rows.forEach((row) => {
          if (row.updated_at && row.updated_at > maxTs) maxTs = row.updated_at;
          const pm = pushed[table] || (pushed[table] = {});
          if (row.deleted) delete pm[String(row.id)];
          else if (row.payload) pm[String(row.id)] = safeJson(row.payload);
        });
        if (typeof hooks.onRows === 'function') hooks.onRows(table, rows);
      } catch (e) {
        error = String((e && e.message) || e);
      }
    }

    if (total && maxTs > cursor) lsSet(LS.cursor, maxTs);
    lsSet(LS.lastAt, new Date().toISOString());

    // Perangkat pertama menyambung server yang masih kosong: unggah daftar lokal.
    if (isFirst && !bootstrapChecked) {
      bootstrapChecked = true;
      if (typeof hooks.getEntries === 'function') {
        emptyTables.forEach((table) => {
          let entries = [];
          try { entries = hooks.getEntries(table); } catch (e) { entries = []; }
          if (entries && entries.length) pushList(table, entries);
        });
      }
    }
    emit();
  }

  /* ---------- satu siklus: tarik dulu, lalu kirim ---------- */
  async function syncNow() {
    if (!started || !isEnabled() || busy) return false;
    if (!configured()) { emit(); return false; }
    if (isOffline()) { emit(); return false; }
    busy = true;
    error = '';
    emit();
    let flushed = false;
    try {
      await pull();
      flushed = await flush();
    } finally {
      busy = false;
      emit();
    }
    return flushed;
  }

  function isEnabled() { return lsGet(LS.enabled, '1') !== '0'; }
  function setEnabled(value) {
    lsSet(LS.enabled, value ? '1' : '0');
    if (value) { if (started) syncNow(); }
    else {
      if (pushTimer) { clearTimeout(pushTimer); pushTimer = null; }
      if (retryTimer) { clearTimeout(retryTimer); retryTimer = null; }
      emit();
    }
  }

  async function loadQueueFromStore() {
    try {
      const rows = await localdb().loadQueue();
      queue = {};
      rows.forEach((row) => {
        if (TABLES.indexOf(row.table) === -1) return;
        (queue[row.table] || (queue[row.table] = {}))[row.id] = {
          id: row.id, payload: row.payload, deleted: !!row.deleted, device_id: row.deviceId
        };
      });
    } catch (e) { /* pakai antrean kosong */ }
  }

  function init(options) {
    const opts = options || {};
    hooks.onRows = typeof opts.onRows === 'function' ? opts.onRows : null;
    hooks.onStatus = typeof opts.onStatus === 'function' ? opts.onStatus : null;
    hooks.getEntries = typeof opts.getEntries === 'function' ? opts.getEntries : null;
  }

  async function start() {
    if (started) return true;
    deviceId = ensureDevice();
    started = true;
    await loadQueueFromStore();
    emit();
    if (configured()) await syncNow();
    pullTimer = setInterval(() => { syncNow(); }, PULL_MS);
    if (typeof window !== 'undefined' && typeof window.addEventListener === 'function') {
      window.addEventListener('online', () => { backoffMs = 0; syncNow(); });
      window.addEventListener('offline', () => { emit(); });
    }
    if (typeof document !== 'undefined' && typeof document.addEventListener === 'function') {
      document.addEventListener('visibilitychange', () => { if (!document.hidden) syncNow(); });
    }
    return true;
  }

  const api = {
    init, start, pushList, syncNow, status, isEnabled, setEnabled,
    tables: TABLES.slice(),
    isConfigured: configured,
    _internals: { get queue() { return queue; }, get pushed() { return pushed; } }
  };
  window.MPJSync = api;
  if (typeof globalThis !== 'undefined' && globalThis.MPJSync !== api) globalThis.MPJSync = api;
})();
