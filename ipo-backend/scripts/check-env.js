// Jalankan: npm run check  -> cek konfigurasi tanpa mencetak rahasia.
import { config, configProblems } from '../src/config.js';

const mark = (ok) => (ok ? 'OK ' : 'BELUM');
console.log(`DATABASE_URL            ${mark(config.dbConfigured)}`);
console.log(`JWT_SECRET (>=32 char)  ${mark(config.jwtOk)}`);
console.log(`CORS_ORIGINS            ${config.corsOrigins.length ? config.corsOrigins.join(', ') : '(kosong)'}`);
console.log(`CRON_SECRET             ${mark(config.cronSecret.length >= 16)}`);
console.log(`GoFood API kredensial   ${mark(config.gofood.apiReady)}`);
console.log(`GoFood notif secret     ${mark(Boolean(config.gofood.notificationSecret))}`);
console.log(`GoFood webhook URL      ${config.gofood.webhookUrl || '(kosong)'}`);
const p = configProblems();
console.log(p.length ? `\nCatatan:\n- ${p.join('\n- ')}` : '\nSemua konfigurasi utama siap.');
