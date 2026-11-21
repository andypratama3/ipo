import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';

/// Ekspor/impor cadangan JSON. Bentuk payload dipertahankan sama dengan versi
/// web (`version: 4`) supaya file backup lama tetap bisa dipulihkan.
class BackupService {
  static const int version = 4;

  Map<String, dynamic> buildPayload({
    required List<Product> products,
    required List<Order> orders,
    required AppSettings settings,
    required List<Category> categories,
    required List<PendingOrder> pendingOrders,
    required List<OnlineOrder> onlineOrders,
  }) =>
      {
        'app': 'Mie Pangsit Jakarta POS',
        'version': version,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'products': products.map((item) => item.toJson()).toList(),
        'orders': orders.map((item) => item.toJson()).toList(),
        'settings': settings.toJson(),
        'categories': categories.map((item) => item.toJson()).toList(),
        'pendingOrders': pendingOrders.map((item) => item.toJson()).toList(),
        'onlineOrders': onlineOrders.map((item) => item.toJson()).toList(),
      };

  String encode(Map<String, dynamic> payload) =>
      const JsonEncoder.withIndent('  ').convert(payload);

  Future<void> shareBackup({
    required Map<String, dynamic> payload,
    required String businessName,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(encode(payload)));
    final stamp = DateTime.now();
    final filename = 'backup-pos-${stamp.year}'
        '${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}-'
        '${stamp.hour.toString().padLeft(2, '0')}'
        '${stamp.minute.toString().padLeft(2, '0')}.json';
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(bytes, mimeType: 'application/json'),
      ],
      fileNameOverrides: [filename],
      subject: 'Backup $businessName',
    ));
  }

  /// Membuka pemilih file dan mengembalikan isi JSON yang valid.
  Future<Map<String, dynamic>?> pickBackup() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('File backup tidak berisi objek JSON.');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
