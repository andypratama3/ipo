import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { crc16, isValidQris } from '../src/lib/qris.js';
import { verifyGoSignature, safeEqual } from '../src/lib/crypto.js';
import { computeTotals, orderDateFromId } from '../src/services/orders.js';
import { normalizeGoFood, matchProduct, mapStatus, baseName } from '../src/services/online.js';
import { passwordSchema, productSchema, settingsSchema, orderInputSchema } from '../src/lib/schemas.js';

const tlv = (tag, val) => tag + String(val.length).padStart(2, '0') + val;
const mkQris = () => {
  const body =
    tlv('00', '01') + tlv('01', '11') +
    tlv('26', tlv('00', 'ID.CO.QRIS.WWW') + tlv('01', 'ID1020000000001') + tlv('02', 'UMI')) +
    tlv('52', '5812') + tlv('53', '360') + tlv('58', 'ID') + tlv('59', 'MIE TEST') + tlv('60', 'JAKARTA') + '6304';
  return body + crc16(body);
};

test('QRIS: CRC valid diterima, diubah ditolak', () => {
  const q = mkQris();
  assert.equal(isValidQris(q), true);
  assert.equal(isValidQris(q.replace('MIE TEST', 'MIE TESX')), false);
  assert.equal(isValidQris('bukan qris'), false);
  assert.equal(isValidQris(''), true);
});

test('Tanda tangan GoBiz: hex & base64 valid, salah/kosong ditolak', () => {
  const raw = Buffer.from('{"a":1}');
  const mac = () => crypto.createHmac('sha256', 's3cret').update(raw);
  const hex = mac().digest('hex');
  const b64 = mac().digest('base64');
  assert.equal(verifyGoSignature(raw, hex, 's3cret'), true);
  assert.equal(verifyGoSignature(raw, b64, 's3cret'), true);
  assert.equal(verifyGoSignature(raw, hex, 'lain'), false);
  assert.equal(verifyGoSignature(Buffer.from('{"a":2}'), hex, 's3cret'), false);
  assert.equal(verifyGoSignature(raw, '', 's3cret'), false);
  assert.equal(verifyGoSignature(raw, hex, ''), false); // secret belum diset => selalu tolak
  assert.equal(safeEqual('a', 'ab'), false);
});

test('Hitung ulang total: diskon dibatasi, tunai & kembalian, metode tak dikenal => cash', () => {
  const items = [{ price: 18000, qty: 2 }, { price: 5000, qty: 1 }];
  let c = computeTotals({ items, discount: 999999, payment: 'cash', paidAmount: 50000 });
  assert.equal(c.subtotal, 41000); assert.equal(c.discount, 41000); assert.equal(c.total, 0);
  c = computeTotals({ items, discount: 1000, payment: 'cash', paidAmount: 50000 });
  assert.equal(c.total, 40000); assert.equal(c.changeAmount, 10000);
  c = computeTotals({ items, discount: 0, payment: 'cash', paidAmount: 1 });
  assert.equal(c.paidAmount, 41000); assert.equal(c.changeAmount, 0); // paidAmount >= total
  c = computeTotals({ items, discount: -5, payment: 'gofood', paidAmount: 0 });
  assert.equal(c.payment, 'cash'); assert.equal(c.discount, 0);
  c = computeTotals({ items, discount: 0, payment: 'qris', paidAmount: 0 });
  assert.equal(c.paidAmount, 41000); assert.equal(c.changeAmount, 0);
  assert.throws(() => computeTotals({ items: [{ price: 100_000_000, qty: 999 }, { price: 100_000_000, qty: 999 }], discount: 0, payment: 'cash' }));
});

test('Tanggal dari nomor struk, fallback UTC createdAt', () => {
  assert.equal(orderDateFromId('MPJ-20261119-48123', '2020-01-01T00:00:00Z'), '2026-11-19');
  assert.equal(orderDateFromId('MPJ-20261399-48123', '2026-05-05T23:00:00Z'), '2026-05-05');
});

test('Skema: sandi, produk, settings, order', () => {
  assert.equal(passwordSchema.safeParse('1234').success, false);
  assert.equal(passwordSchema.safeParse('password').success, false);
  assert.equal(passwordSchema.safeParse('x'.repeat(73)).success, false);
  assert.equal(passwordSchema.safeParse('Sandi-Kuat-2026').success, true);
  assert.equal(productSchema.safeParse({ id: 'a', name: 'Mie', price: -1 }).success, false);
  assert.equal(productSchema.safeParse({ id: 'a', name: 'Mie', price: 1.5 }).success, false);
  assert.equal(productSchema.safeParse({ id: '../x', name: 'Mie', price: 1 }).success, false);
  assert.equal(productSchema.parse({ id: 'a', name: 'Mie', price: 1, evil: 'x' }).evil, undefined);
  assert.equal(settingsSchema.safeParse({ qrisStaticPayload: 'ngawur' }).success, false);
  assert.equal(settingsSchema.safeParse({ taxRate: 11, extra: { nested: 1 } }).success, false);
  const ok = { order: { id: 'MPJ-20261119-48123', clientTxnId: crypto.randomUUID(), createdAt: new Date().toISOString(), items: [{ productId: 'a', name: 'X', price: 1, qty: 1 }] } };
  assert.equal(orderInputSchema.safeParse(ok).success, true);
  assert.equal(orderInputSchema.safeParse({ order: { ...ok.order, items: [] } }).success, false);
  assert.equal(orderInputSchema.safeParse({ order: { ...ok.order, clientTxnId: 'x' } }).success, false);
});

const envelope = (over = {}) => ({
  header: { event_name: 'gofood.order.awaiting_merchant_acceptance', event_id: 'e1', version: 1, timestamp: '2026-11-19T07:00:00+07:00' },
  body: {
    customer: { id: 'c', name: 'Dina' }, driver: { name: '' }, service_type: 'gofood', outlet: { id: 'G1', external_outlet_id: 'o1' },
    order: { status: 'AWAITING_MERCHANT_ACCEPTANCE', pin: '1234', order_number: 'F-2174', order_total: 4e4,
      order_items: [{ quantity: 2, price: 1.8e4, notes: 'pedas', name: 'Pangsit Original (Pedas)', id: 'u1', external_id: 'm1', variants: [{ name: 'Level 2' }] }],
      created_at: '2026-11-19T07:00:00+07:00' }, ...over,
  },
});

test('Normalisasi GoFood & pemetaan status tidak pernah menutup otomatis', () => {
  const ev = normalizeGoFood(envelope());
  assert.equal(ev.partnerOrderId, 'F-2174'); assert.equal(ev.orderType, 'delivery');
  assert.equal(ev.items[0].qty, 2); assert.match(ev.items[0].note, /pedas/); assert.match(ev.items[0].note, /Level 2/);
  assert.equal(normalizeGoFood({ header: { event_name: 'payment.transaction.settlement' }, body: {} }), null);
  assert.equal(normalizeGoFood({}), null);
  assert.equal(mapStatus('AWAITING_MERCHANT_ACCEPTANCE'), 'baru');
  assert.equal(mapStatus('MERCHANT_ACCEPTED'), 'dibuat');
  assert.equal(mapStatus('COMPLETED'), 'siap');
});

test('Pencocokan menu: peta manual > id > nama persis > nama dasar > awalan unik', () => {
  const products = [{ id: 'pangsit-original', name: 'Pangsit Original' }, { id: 'mie-kering', name: 'Mie Kering Ayam' }, { id: 'es-teh', name: 'Es Teh' }, { id: 'es-jeruk', name: 'Es Jeruk' }];
  const none = new Map();
  assert.equal(matchProduct({ partnerMenuId: 'm', name: 'Es Teh' }, products, new Map([['m', { product_id: 'es-jeruk' }]])).productId, 'es-jeruk');
  assert.equal(matchProduct({ partnerMenuId: 'es-teh', name: 'x' }, products, none).productId, 'es-teh');
  assert.equal(matchProduct({ partnerMenuId: 'z', name: 'pangsit  original' }, products, none).productId, 'pangsit-original');
  assert.equal(matchProduct({ partnerMenuId: 'z', name: 'Pangsit Original (Pedas)' }, products, none).productId, 'pangsit-original');
  assert.equal(matchProduct({ partnerMenuId: 'z', name: 'Mie Kering' }, products, none).productId, 'mie-kering');
  assert.equal(matchProduct({ partnerMenuId: 'z', name: 'Es' }, products, none), null); // ambigu
  assert.equal(matchProduct({ partnerMenuId: 'z', name: 'Soto' }, products, none), null);
  assert.equal(baseName('Es Teh - Large'), 'es teh');
});
