/** CRC16-CCITT (poly 0x1021, init 0xFFFF) sesuai EMVCo/QRIS. */
export function crc16(str) {
  let crc = 0xffff;
  for (let i = 0; i < str.length; i++) {
    crc ^= str.charCodeAt(i) << 8;
    for (let j = 0; j < 8; j++) crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/** Validasi struktur TLV + CRC. String kosong dianggap "belum diatur" (valid). */
export function isValidQris(payload) {
  if (payload === '' || payload == null) return true;
  if (typeof payload !== 'string' || payload.length < 20 || payload.length > 1024) return false;
  if (!/^[\x20-\x7E]+$/.test(payload)) return false;
  if (!payload.startsWith('000201')) return false;
  if (payload.slice(-8, -4) !== '6304') return false;
  // Jalan melalui TLV: tag(2) len(2) value(len)
  let i = 0;
  while (i < payload.length) {
    if (i + 4 > payload.length) return false;
    const len = Number.parseInt(payload.slice(i + 2, i + 4), 10);
    if (!Number.isInteger(len) || len < 0) return false;
    i += 4 + len;
  }
  if (i !== payload.length) return false;
  return crc16(payload.slice(0, -4)) === payload.slice(-4).toUpperCase();
}
