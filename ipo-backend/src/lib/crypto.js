import crypto from 'node:crypto';

/** Bandingkan dua string dengan waktu konstan (panjang berbeda pun tidak bocor). */
export function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

export const sha256Hex = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

/**
 * Verifikasi X-Go-Signature = HMAC-SHA256(notification_secret, raw body).
 * Menerima hex atau base64 (dokumentasi GoBiz tidak menegaskan encoding).
 */
export function verifyGoSignature(rawBody, headerValue, secret) {
  if (!secret || !headerValue || !Buffer.isBuffer(rawBody)) return false;
  const mac = crypto.createHmac('sha256', secret).update(rawBody).digest();
  const given = String(headerValue).trim().replace(/^sha256=/i, '');
  const hex = mac.toString('hex');
  const b64 = mac.toString('base64');
  // Bandingkan keduanya tanpa short-circuit agar waktu tetap konstan.
  const okHex = safeEqual(given.toLowerCase(), hex);
  const okB64 = safeEqual(given, b64);
  return okHex || okB64;
}
