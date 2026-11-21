import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../models/models.dart';
import 'print_service.dart';

class ReportSummary {
  ReportSummary({
    required this.orders,
    required this.from,
    required this.to,
  });

  final List<Order> orders;
  final String from;
  final String to;

  int get revenue => orders.fold(0, (sum, order) => sum + order.total);
  int get itemCount => orders.fold(0, (sum, order) => sum + order.itemCount);
  double get average => orders.isEmpty ? 0 : revenue / orders.length;

  Map<String, ReportGroup> get daily => _groupBy((order) => orderDateKey(order.createdAt));
  Map<String, ReportGroup> get monthly =>
      _groupBy((order) => orderDateKey(order.createdAt).substring(0, 7));

  Map<String, ReportGroup> _groupBy(String Function(Order) keyOf) {
    final map = <String, ReportGroup>{};
    for (final order in orders) {
      final key = keyOf(order);
      if (key.isEmpty) continue;
      final group = map.putIfAbsent(key, ReportGroup.new);
      group.count += 1;
      group.items += order.itemCount;
      group.total += order.total;
    }
    return map;
  }
}

class ReportGroup {
  int count = 0;
  int items = 0;
  int total = 0;
}

/// Laporan XLSX dengan struktur yang sama seperti versi web:
/// ringkasan → rekap harian → rekap bulanan → rincian transaksi.
class ReportService {
  List<int> buildXlsx({
    required ReportSummary summary,
    required String businessName,
    required String title,
    required String kindLabel,
  }) {
    final excel = Excel.createExcel();
    const sheetName = 'Laporan';
    if (excel.sheets.keys.contains('Sheet1')) {
      excel.rename('Sheet1', sheetName);
    }
    final sheet = excel[sheetName];

    final bold = CellStyle(bold: true);
    final titleStyle = CellStyle(bold: true, fontSize: 14);
    final sectionStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('FFE0F2FE'),
    );
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('FFF1F5F9'),
    );
    final moneyStyle = CellStyle(numberFormat: NumFormat.standard_3);
    final moneyBoldStyle = CellStyle(bold: true, numberFormat: NumFormat.standard_3);

    var row = 0;

    void put(int column, CellValue? value, {CellStyle? style}) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: column,
        rowIndex: row,
      ));
      cell.value = value;
      if (style != null) cell.cellStyle = style;
    }

    void mergeRow(int fromCol, int toCol) {
      if (toCol > fromCol) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: fromCol, rowIndex: row),
          CellIndex.indexByColumnRow(columnIndex: toCol, rowIndex: row),
        );
      }
    }

    void section(String label) {
      put(0, TextCellValue(label), style: sectionStyle);
      mergeRow(0, 6);
      row += 1;
    }

    void tableHeader(List<String> labels) {
      for (var i = 0; i < labels.length; i += 1) {
        put(i, TextCellValue(labels[i]), style: headerStyle);
      }
      row += 1;
    }

    void groupRows(
      Map<String, ReportGroup> groups,
      String Function(String) labelOf,
    ) {
      final keys = groups.keys.toList()..sort();
      for (var i = 0; i < keys.length; i += 1) {
        final group = groups[keys[i]]!;
        put(0, IntCellValue(i + 1));
        put(1, TextCellValue(labelOf(keys[i])));
        put(2, IntCellValue(group.count));
        put(3, IntCellValue(group.items));
        put(4, IntCellValue(group.total), style: moneyStyle);
        row += 1;
      }
      put(0, TextCellValue('TOTAL'), style: bold);
      mergeRow(0, 1);
      put(2, IntCellValue(summary.orders.length), style: bold);
      put(3, IntCellValue(summary.itemCount), style: bold);
      put(4, IntCellValue(summary.revenue), style: moneyBoldStyle);
      row += 2;
    }

    // 1) Judul
    put(0, TextCellValue(businessName), style: titleStyle);
    mergeRow(0, 6);
    row += 1;
    put(0, TextCellValue(title), style: bold);
    mergeRow(0, 6);
    row += 1;
    put(0, TextCellValue(
      'Jenis: $kindLabel (${summary.from == summary.to ? '1 hari' : 'beberapa hari'})',
    ));
    mergeRow(0, 6);
    row += 1;
    put(0, TextCellValue('Periode: ${summary.from} s.d. ${summary.to}'));
    mergeRow(0, 6);
    row += 1;
    put(0, TextCellValue('Diunduh: ${formatDateTime(DateTime.now().toIso8601String())}'));
    mergeRow(0, 6);
    row += 2;

    // 2) Ringkasan
    section('RINGKASAN');
    put(0, TextCellValue('Total omzet'), style: bold);
    put(1, IntCellValue(summary.revenue), style: moneyStyle);
    put(3, TextCellValue('Transaksi'), style: bold);
    put(4, IntCellValue(summary.orders.length));
    row += 1;
    put(0, TextCellValue('Item terjual'), style: bold);
    put(1, IntCellValue(summary.itemCount));
    put(3, TextCellValue('Rata-rata / transaksi'), style: bold);
    put(4, IntCellValue(summary.average.round()), style: moneyStyle);
    row += 2;

    // 3) Rekap harian
    section('REKAP HARIAN');
    tableHeader(['No', 'Tanggal', 'Transaksi', 'Item', 'Omzet']);
    groupRows(summary.daily, (key) => key);

    // 4) Rekap bulanan bila lintas bulan
    if (summary.monthly.length > 1) {
      section('REKAP BULANAN');
      tableHeader(['No', 'Bulan', 'Transaksi', 'Item', 'Omzet']);
      groupRows(summary.monthly, (key) {
        final parts = key.split('-');
        if (parts.length < 2) return key;
        final month = int.tryParse(parts[1]) ?? 0;
        const names = [
          'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
          'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
        ];
        final name = month >= 1 && month <= 12 ? names[month - 1] : key;
        return '$name ${parts[0]}';
      });
    }

    // 5) Rincian transaksi
    section('RINCIAN TRANSAKSI');
    tableHeader([
      'No', 'Tanggal', 'Jam', 'No. Transaksi', 'Pesanan', 'Pembayaran', 'Total',
    ]);
    // Sama seperti web: rincian diurutkan dari transaksi terlama ke terbaru.
    final sorted = [...summary.orders]
      ..sort((a, b) {
        final left = safeDate(a.createdAt)?.millisecondsSinceEpoch ?? 0;
        final right = safeDate(b.createdAt)?.millisecondsSinceEpoch ?? 0;
        return left.compareTo(right);
      });
    for (var i = 0; i < sorted.length; i += 1) {
      final order = sorted[i];
      final items = order.items.map((item) => '${item.qty}x ${item.name}').join(', ');
      put(0, IntCellValue(i + 1));
      put(1, TextCellValue(orderDateKey(order.createdAt)));
      put(2, TextCellValue(formatTime(order.createdAt)));
      put(3, TextCellValue(order.id));
      put(4, TextCellValue(items));
      put(5, TextCellValue(ReceiptBuilder.paymentLabel(order.payment)));
      put(6, IntCellValue(order.total), style: moneyStyle);
      row += 1;
    }
    put(0, TextCellValue('TOTAL'), style: bold);
    mergeRow(0, 5);
    put(6, IntCellValue(summary.revenue), style: moneyBoldStyle);

    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 12);
    sheet.setColumnWidth(2, 10);
    sheet.setColumnWidth(3, 20);
    sheet.setColumnWidth(4, 42);
    sheet.setColumnWidth(5, 15);
    sheet.setColumnWidth(6, 13);

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('Gagal membuat file XLSX.');
    }
    return bytes;
  }

  Future<void> shareXlsx({
    required List<int> bytes,
    required String filename,
  }) async {
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      fileNameOverrides: [filename],
      subject: filename,
    ));
  }
}
