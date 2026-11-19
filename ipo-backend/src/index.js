// Entry point. Vercel mendeteksi Express dari `import express` + default export `app`.
import express from 'express';
import { pathToFileURL } from 'node:url';
import { config, configProblems } from './config.js';
import { securityHeaders, corsMiddleware, noStore, globalLimiter, requestLog, requireJson } from './middleware/security.js';
import { notFoundHandler, errorHandler } from './middleware/error.js';
import { webhookHandler } from './routes/webhooks.js';
import healthRoutes from './routes/health.js';
import authRoutes from './routes/auth.js';
import userRoutes from './routes/users.js';
import syncRoutes from './routes/sync.js';
import orderRoutes from './routes/orders.js';
import onlineRoutes from './routes/online.js';
import cronRoutes from './routes/cron.js';

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', config.trustProxy); // Vercel: 1 (IP klien dari X-Forwarded-For)
app.set('etag', false);

app.use(securityHeaders);
app.use(corsMiddleware);
app.use(requestLog);
app.use('/api', noStore);

// Webhook SEBELUM parser JSON: butuh byte mentah untuk HMAC.
app.post('/api/webhooks/:source', express.raw({ type: () => true, limit: '256kb' }), webhookHandler);

app.use('/api', globalLimiter);
app.use('/api', requireJson);
app.use(express.json({ limit: '2mb', strict: true }));

app.use('/api/health', healthRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/sync', syncRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/online', onlineRoutes);
app.use('/api/cron', cronRoutes);

app.get('/', (req, res) => res.json({ name: 'iPo Mie Pangsit API', ok: true }));
app.use(notFoundHandler);
app.use(errorHandler);

const problems = configProblems();
if (problems.length) console.warn(JSON.stringify({ level: 'warn', msg: 'config', problems }));

// Jalankan listener hanya bila file ini dieksekusi langsung (npm start / dev); di Vercel cukup default export.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  app.listen(config.port, () => console.log(`iPo API listening on :${config.port}`));
}

export default app;
