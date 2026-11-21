#!/usr/bin/env node
/* ===========================================================================
 * migration/export-supabase.js
 * ----------------------------------------------------------------------------
 * Menarik SELURUH isi tabel Supabase IPOS (termasuk baris tombstone `deleted`)
 * lalu menuliskannya sebagai satu file JSON cadangan di migration/backups/.
 *
 * Script ini HANYA MEMBACA (GET). Tidak ada operasi tulis/hapus.
 *
 * Pakai:
 *   node migration/export-supabase.js
 *
 * Kredensial bisa ditimpa lewat environment (disarankan untuk arsip baru):
 *   SUPABASE_URL=https://xxxx.supabase.co
 *   SUPABASE_ANON_KEY=sb_publishable_xxx
 *
 * Catatan: kunci publishable bawaan aplikasi bersifat PUBLIK (memang dipakai
 * di browser). Script ini tidak memakai service_role/secret key.
 * =========================================================================== */

const fs = require('fs');
const path = require('path');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://nktpdurnmdrktgsaslpy.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_ANON_KEY || 'sb_publishable_yXISfxLFSHhsTeuEF181Ng_DhSKa9ry';
const TABLES = ['products', 'categories', 'settings', 'orders', 'pending_orders', 'online_orders'];
const PAGE = 1000;

const headers = {
  apikey: SUPABASE_KEY,
  Authorization: 'Bearer ' + SUPABASE_KEY,
  'Content-Type': 'application/json'
};

async function fetchTable(table) {
  const rows = [];
  let offset = 0;
  for (;;) {
    const url = `${SUPABASE_URL}/rest/v1/${table}` +
      `?select=id,payload,updated_at,deleted,device_id` +
      `&order=updated_at.asc&limit=${PAGE}&offset=${offset}`;
    const res = await fetch(url, { headers });
    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      throw new Error(`GET ${table} -> HTTP ${res.status} ${detail.slice(0, 160)}`);
    }
    const batch = await res.json();
    if (!Array.isArray(batch) || batch.length === 0) break;
    rows.push(...batch);
    if (batch.length < PAGE) break;
    offset += PAGE;
  }
  return rows;
}

async function main() {
  const outDir = path.join(__dirname, 'backups');
  fs.mkdirSync(outDir, { recursive: true });

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const snapshot = {
    exportedAt: new Date().toISOString(),
    source: SUPABASE_URL,
    tables: {}
  };

  for (const table of TABLES) {
    process.stdout.write(`memuat ${table} ... `);
    const rows = await fetchTable(table);
    snapshot.tables[table] = rows;
    const live = rows.filter((r) => !r.deleted).length;
    console.log(`${rows.length} baris (${live} aktif, ${rows.length - live} tombstone)`);
  }

  const file = path.join(outDir, `supabase-export-${stamp}.json`);
  fs.writeFileSync(file, JSON.stringify(snapshot, null, 2));

  const totals = Object.fromEntries(
    Object.entries(snapshot.tables).map(([t, rows]) => [t, { total: rows.length, active: rows.filter((r) => !r.deleted).length }])
  );
  console.log('\nCadangan tersimpan:', file);
  console.log('Ringkasan:', JSON.stringify(totals));
}

main().catch((err) => {
  console.error('Gagal mengekspor:', err.message);
  process.exit(1);
});
