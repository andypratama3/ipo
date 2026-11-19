import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { config } from '../config.js';

export const securityHeaders = helmet({
  contentSecurityPolicy: { directives: { defaultSrc: ["'none'"], frameAncestors: ["'none'"] } },
  crossOriginResourcePolicy: { policy: 'same-site' },
  referrerPolicy: { policy: 'no-referrer' },
  hsts: { maxAge: 63072000, includeSubDomains: true },
});

const DEV_ORIGINS = ['http://localhost:8031', 'http://127.0.0.1:8031', 'http://localhost:3000'];

export const corsMiddleware = cors({
  origin(origin, cb) {
    if (!origin) return cb(null, true); // non-browser (webhook, curl, cron)
    const allowed = config.corsOrigins.length ? config.corsOrigins : config.isProd ? [] : DEV_ORIGINS;
    cb(null, allowed.includes(origin));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type'],
  credentials: false,
  maxAge: 86400,
});

export function noStore(req, res, next) {
  res.set('Cache-Control', 'no-store');
  next();
}

/** Lapis kasar per-instance (lapis utama untuk login/webhook ada di DB: lib/ratelimit.js). */
export const globalLimiter = rateLimit({
  windowMs: 60_000,
  limit: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'rate_limited', message: 'Terlalu banyak permintaan.' },
});

export function requestLog(req, res, next) {
  const t = Date.now();
  res.on('finish', () => {
    console.log(JSON.stringify({ m: req.method, p: req.path, s: res.statusCode, ms: Date.now() - t, u: req.user?.username }));
  });
  next();
}

/** POST/PUT/DELETE dengan body harus JSON. */
export function requireJson(req, res, next) {
  if (['POST', 'PUT'].includes(req.method) && Number(req.headers['content-length'] || 0) > 0) {
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'unsupported_media_type', message: 'Content-Type harus application/json.' });
    }
  }
  next();
}
