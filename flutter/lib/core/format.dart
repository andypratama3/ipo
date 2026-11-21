import 'package:intl/intl.dart';

final NumberFormat _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final NumberFormat _number = NumberFormat.decimalPattern('id_ID');

String formatRupiah(num value) => _rupiah.format(value.isFinite ? value : 0);

String formatNumber(num value) {
  if (!value.isFinite) return '0';
  return _number.format(value);
}

/// Ringkas: "1,2 jt", "25 rb", "900".
String formatRupiahShort(num value) {
  final amount = (value.isFinite ? value : 0).abs().round();
  if (amount >= 1000000) {
    final millions = amount / 1000000;
    final text = amount % 1000000 == 0
        ? millions.toStringAsFixed(0)
        : millions.toStringAsFixed(1);
    return '${text.replaceAll('.', ',')} jt';
  }
  if (amount >= 1000) return '${(amount / 1000).round()} rb';
  return formatNumber(amount);
}

/// "2026-11-20" memakai tanggal lokal perangkat.
String dateKey([DateTime? date]) {
  final d = date ?? DateTime.now();
  final year = d.year.toString().padLeft(4, '0');
  final month = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime? safeDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value)?.toLocal();
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

String orderDateKey(String createdAt) {
  final date = safeDate(createdAt);
  return date == null ? '' : dateKey(date);
}

String formatTime(String iso) {
  final date = safeDate(iso);
  if (date == null) return '-';
  return DateFormat('HH:mm', 'id_ID').format(date);
}

String formatDateTime(String iso) {
  final date = safeDate(iso);
  if (date == null) return '-';
  return DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(date);
}

String formatDateLong(DateTime date) =>
    DateFormat('EEEE, d MMM yyyy', 'id_ID').format(date);

String formatDateShort(DateTime date) =>
    DateFormat('d MMM yyyy', 'id_ID').format(date);

/// "20 Nov" — versi ringkas untuk kolom tanggal di daftar transaksi.
String formatDayMonth(String iso) {
  final date = safeDate(iso);
  if (date == null) return '-';
  return DateFormat('d MMM', 'id_ID').format(date);
}

/// "1,00" — dua desimal gaya struk minimarket.
String receiptQty(num value) =>
    NumberFormat('#,##0.00', 'id_ID').format(value.isFinite ? value : 0);

bool isDateKey(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parts = value.split('-').map(int.parse).toList();
  final date = DateTime(parts[0], parts[1], parts[2]);
  return date.year == parts[0] && date.month == parts[1] && date.day == parts[2];
}
