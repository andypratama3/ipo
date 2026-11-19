/* ===========================================================================
 * js/localdb.js — database lokal perangkat (IndexedDB) untuk antrean sinkron.
 * ----------------------------------------------------------------------------
 * Dipakai bersama oleh js/sync.js. Menyimpan:
 *   - outbox : baris yang belum berhasil dikirim ke server (dengan status
 *              pending | syncing | synced | failed, jumlah percobaan, dan
 *              waktu coba berikutnya).
 *   - meta   : penanda kecil (mis. id perangkat).
 *
 * Kalau IndexedDB tidak tersedia (lingkungan sangat tua), otomatis jatuh ke
 * penyimpanan sementara di memori supaya aplikasi tetap berjalan.
 *
 * Bentuk API sinkron (status()) tetap dijaga di sync.js; berkas ini asinkron.
 * =========================================================================== */
(function () {
  'use strict';

  const DB_NAME = 'ipos_local';
  const DB_VERSION = 1;
  const STORE_OUTBOX = 'outbox';
  const STORE_META = 'meta';

  const available = typeof indexedDB !== 'undefined';
  const memOutbox = new Map(); // fallback: key -> row
  const memMeta = new Map();

  let dbPromise = null;

  function openDB() {
    if (!available) return Promise.resolve(null);
    if (dbPromise) return dbPromise;
    dbPromise = new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(STORE_OUTBOX)) {
          const store = db.createObjectStore(STORE_OUTBOX, { keyPath: 'key' });
          store.createIndex('status', 'status', { unique: false });
          store.createIndex('table', 'table', { unique: false });
        }
        if (!db.objectStoreNames.contains(STORE_META)) {
          db.createObjectStore(STORE_META, { keyPath: 'key' });
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error || new Error('gagal membuka IndexedDB'));
    }).catch(() => null); // gagal buka -> pakai memori
    return dbPromise;
  }

  function req(request) {
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async function withStore(name, mode, fn) {
    const db = await openDB();
    if (!db) return fn(null);
    return new Promise((resolve, reject) => {
      let settled = null;
      const tx = db.transaction(name, mode);
      const store = tx.objectStore(name);
      Promise.resolve(fn(store)).then((value) => { settled = value; }).catch(reject);
      tx.oncomplete = () => resolve(settled);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  }

  const outboxKey = (table, id) => `${table}:${id}`;

  /* Menambahkan/memperbarui baris antrean. rows = [{table,id,payload,deleted,deviceId}] */
  async function queueRows(rows) {
    const stamp = new Date().toISOString();
    const records = (rows || []).filter(Boolean).map((row) => ({
      key: outboxKey(row.table, row.id),
      table: row.table,
      id: String(row.id),
      payload: row.payload,
      deleted: Boolean(row.deleted),
      deviceId: row.deviceId || null,
      status: 'pending',
      tries: 0,
      nextAt: 0,
      lastError: '',
      updatedAt: stamp
    }));
    if (!records.length) return 0;
    if (!available) {
      records.forEach((record) => {
        const prev = memOutbox.get(record.key);
        memOutbox.set(record.key, prev ? { ...prev, ...record, tries: prev.tries } : record);
      });
      return records.length;
    }
    return withStore(STORE_OUTBOX, 'readwrite', async (store) => {
      for (const record of records) {
        const prev = await req(store.get(record.key));
        store.put(prev ? { ...prev, ...record, tries: prev.tries, status: prev.status === 'synced' ? 'pending' : 'pending' } : record);
      }
      return records.length;
    });
  }

  async function loadQueue() {
    if (!available) return Array.from(memOutbox.values());
    return withStore(STORE_OUTBOX, 'readonly', (store) => req(store.getAll()));
  }

  async function removeRows(keys) {
    if (!keys || !keys.length) return 0;
    if (!available) { keys.forEach((key) => memOutbox.delete(key)); return keys.length; }
    return withStore(STORE_OUTBOX, 'readwrite', (store) => {
      keys.forEach((key) => store.delete(key));
      return keys.length;
    });
  }

  /* Mengubah status/tries/nextAt beberapa baris sekaligus (satu transaksi). */
  async function markRows(keys, patch) {
    if (!keys || !keys.length) return 0;
    if (!available) {
      keys.forEach((key) => {
        const prev = memOutbox.get(key);
        if (prev) memOutbox.set(key, { ...prev, ...patch });
      });
      return keys.length;
    }
    return withStore(STORE_OUTBOX, 'readwrite', async (store) => {
      for (const key of keys) {
        const prev = await req(store.get(key));
        if (prev) store.put({ ...prev, ...patch });
      }
      return keys.length;
    });
  }

  async function countByStatus() {
    const rows = await loadQueue();
    const counts = { pending: 0, syncing: 0, failed: 0, total: rows.length };
    rows.forEach((row) => {
      if (row.status === 'failed') counts.failed += 1;
      else if (row.status === 'syncing') counts.syncing += 1;
      else counts.pending += 1;
    });
    return counts;
  }

  async function getMeta(key) {
    if (!available) return memMeta.has(key) ? memMeta.get(key) : null;
    const row = await withStore(STORE_META, 'readonly', (store) => req(store.get(key)));
    return row ? row.value : null;
  }

  async function setMeta(key, value) {
    if (!available) { memMeta.set(key, value); return; }
    return withStore(STORE_META, 'readwrite', (store) => { store.put({ key, value }); return true; });
  }

  window.MPJLocalDB = {
    available,
    queueRows,
    loadQueue,
    removeRows,
    markRows,
    countByStatus,
    getMeta,
    setMeta,
    outboxKey
  };
})();
