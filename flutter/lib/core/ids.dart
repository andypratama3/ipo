import 'dart:math';

final Random _random = Random.secure();

/// ID acak pendek untuk menu/kategori lokal.
String uid([String prefix = 'id']) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final buffer = StringBuffer(prefix)..write('-');
  for (var i = 0; i < 8; i += 1) {
    buffer.write(chars[_random.nextInt(chars.length)]);
  }
  return buffer.toString();
}

/// Nomor transaksi: MPJ-YYYYMMDD-xxxxx (5 digit terakhir dari waktu).
String newOrderId([DateTime? at]) {
  final now = at ?? DateTime.now();
  final date = '${now.year}${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  final suffix = (now.millisecondsSinceEpoch % 100000).toString().padLeft(5, '0');
  return 'MPJ-$date-$suffix';
}

/// Nomor pesanan "simpan nanti": HOLD-YYYYMMDD-xxxxx.
String newHoldId([DateTime? at]) {
  final now = at ?? DateTime.now();
  final date = '${now.year}${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  final suffix = (now.millisecondsSinceEpoch % 100000).toString().padLeft(5, '0');
  return 'HOLD-$date-$suffix';
}

const String _hex = '0123456789abcdef';

/// UUID v4 sederhana untuk `clientTxnId` (kunci idempotensi transaksi).
String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i += 1) {
    if (i == 4 || i == 6 || i == 8 || i == 10) buffer.write('-');
    buffer.write(_hex[bytes[i] >> 4]);
    buffer.write(_hex[bytes[i] & 0x0f]);
  }
  return buffer.toString();
}

/// Kode pickup 4 digit untuk pesanan online yang siap diambil.
String pickupCode() => (_random.nextInt(9000) + 1000).toString();
