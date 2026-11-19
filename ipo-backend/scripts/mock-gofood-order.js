// Simulasi webhook GoFood ke server Anda (untuk sandbox/lokal).
// Pakai: npm run mock:gofood [url] [event] [orderNo]
// Ambil GOFOOD_NOTIFICATION_SECRET & GOFOOD_OUTLET_ID dari .env (boleh juga dari environment).
import 'dotenv/config';
import crypto from 'node:crypto';

const base = (process.argv[2] || 'http://localhost:8080').replace(/\/+$/, '');
const event = process.argv[3] || 'gofood.order.awaiting_merchant_acceptance';
const orderNo = process.argv[4] || `F-${Date.now()}`;
const secret = process.env.GOFOOD_NOTIFICATION_SECRET;
if (!secret) { console.error('Set GOFOOD_NOTIFICATION_SECRET dulu.'); process.exit(1); }

const body = JSON.stringify({
  header: { event_name: event, event_id: crypto.randomUUID(), version: 1, timestamp: new Date().toISOString() },
  body: {
    customer: { id: 'C1', name: 'Dina' }, driver: { name: '' }, service_type: 'gofood',
    outlet: { id: process.env.GOFOOD_OUTLET_ID || 'G123456789', external_outlet_id: 'outlet01' },
    order: {
      status: event.split('.').pop().toUpperCase(), pin: '1234', order_number: orderNo, order_total: 36000,
      order_items: [{ quantity: 2, price: 18000, notes: 'pedas', name: 'Pangsit Original', id: 'uuid-1', external_id: 'pangsit-original', variants: [] }],
      currency: 'IDR', takeaway_charges: 0, created_at: new Date().toISOString(),
    },
  },
});
const sig = crypto.createHmac('sha256', secret).update(body).digest('hex');
const res = await fetch(`${base}/api/webhooks/gofood`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Go-Signature': sig }, body });
console.log(res.status, await res.text());
