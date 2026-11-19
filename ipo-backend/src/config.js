import 'dotenv/config';

const env = process.env;

const bool = (v, d = false) =>
  v == null || v === '' ? d : ['1', 'true', 'yes', 'on'].includes(String(v).toLowerCase());
const int = (v, d, min = -Infinity, max = Infinity) => {
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : d;
};
const list = (v) => String(v || '').split(',').map((s) => s.trim()).filter(Boolean);

const isProd = env.NODE_ENV === 'production' || env.VERCEL_ENV === 'production';
const onVercel = Boolean(env.VERCEL);

const databaseUrl = (env.DATABASE_URL || '').trim();
const PLACEHOLDER_DB = /ipos_placeholder|contoh:contoh|user:password@host|your-db|example\.com/i;

const jwtSecret = env.JWT_SECRET || '';
const WEAK_SECRET = /(change[-_ ]?me|placeholder|contoh|example|secret123|password)/i;

const REJECT_CODES = ['HIGH_DEMAND', 'RESTAURANT_CLOSED', 'ITEMS_OUT_OF_STOCK', 'OTHERS'];
const rejectCode = (env.GOFOOD_REJECT_REASON_CODE || 'OTHERS').toUpperCase();

export const config = {
  isProd,
  onVercel,
  port: int(env.PORT, 8080, 1, 65535),

  databaseUrl,
  dbConfigured: databaseUrl !== '' && !PLACEHOLDER_DB.test(databaseUrl),
  dbLocal: /@(localhost|127\.0\.0\.1|\[::1\])(:|\/|$)/.test(databaseUrl),

  jwtSecret,
  jwtOk: jwtSecret.length >= 32 && !WEAK_SECRET.test(jwtSecret),
  jwtTtlHours: int(env.JWT_TTL_HOURS, 24, 1, 720),
  jwtIssuer: 'ipo-pos',
  jwtAudience: 'ipo-pos-app',

  corsOrigins: list(env.CORS_ORIGINS),
  trustProxy: int(env.TRUST_PROXY, onVercel ? 1 : 0, 0, 5),
  loginRateLimit: int(env.LOGIN_RATE_LIMIT, 20, 3, 1000),
  cronSecret: env.CRON_SECRET || '',
  webhookRetentionDays: int(env.WEBHOOK_RETENTION_DAYS, 90, 7, 3650),

  gofood: {
    authUrl: env.GOFOOD_AUTH_URL || 'https://integration-goauth.gojekapi.com/oauth2/token',
    apiBase: (env.GOFOOD_API_BASE || 'https://api.partner-sandbox.gobiz.co.id').replace(/\/+$/, ''),
    clientId: env.GOFOOD_CLIENT_ID || '',
    clientSecret: env.GOFOOD_CLIENT_SECRET || '',
    outletId: env.GOFOOD_OUTLET_ID || '',
    notificationSecret: env.GOFOOD_NOTIFICATION_SECRET || '',
    webhookUrl: env.GOFOOD_WEBHOOK_URL || '',
    autoAccept: bool(env.GOFOOD_AUTO_ACCEPT, false),
    rejectReasonCode: REJECT_CODES.includes(rejectCode) ? rejectCode : 'OTHERS',
    scope:
      env.GOFOOD_SCOPE ||
      'partner:outlet:read gofood:order:read gofood:order:write gofood:catalog:read gofood:catalog:write',
  },
};

config.gofood.apiReady = Boolean(
  config.gofood.clientId && config.gofood.clientSecret && config.gofood.outletId,
);

/** Daftar masalah konfigurasi (untuk log & `npm run check`; tidak pernah memuat nilai rahasia). */
export function configProblems() {
  const p = [];
  if (!config.dbConfigured) p.push('DATABASE_URL belum diisi / masih placeholder');
  if (!config.jwtOk) p.push('JWT_SECRET kosong, <32 karakter, atau memakai nilai contoh');
  if (config.isProd && config.corsOrigins.length === 0)
    p.push('CORS_ORIGINS kosong: hanya same-origin/non-browser yang bisa mengakses');
  if (config.isProd && !config.cronSecret) p.push('CRON_SECRET kosong: endpoint cron akan menolak semua panggilan');
  if (config.isProd && !config.gofood.notificationSecret)
    p.push('GOFOOD_NOTIFICATION_SECRET kosong: semua webhook GoFood akan ditolak');
  if (config.gofood.webhookUrl && !/^https:\/\//i.test(config.gofood.webhookUrl))
    p.push('GOFOOD_WEBHOOK_URL harus HTTPS');
  return p;
}
