import { processQueue } from '../services/gofood.js';

/** Jalankan setelah respons dikirim (waitUntil di Vercel; fire-and-forget di lokal). */
export function kickQueue() {
  const job = processQueue(5).catch((e) => console.error(JSON.stringify({ level: 'error', msg: 'queue', code: e?.code })));
  import('@vercel/functions').then((m) => { try { m.waitUntil(job); } catch { /* bukan di Vercel */ } }).catch(() => {});
}
