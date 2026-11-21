import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/defaults.dart';
import '../core/format.dart';
import '../models/models.dart';

enum ReceiptAlign { left, center, right }

class ReceiptLine {
  const ReceiptLine(
    this.text, {
    this.bold = false,
    this.big = false,
    this.align = ReceiptAlign.left,
    this.divider = false,
  });

  final String text;
  final bool bold;
  final bool big;
  final ReceiptAlign align;
  final bool divider;

  const ReceiptLine.divider()
      : text = '',
        bold = false,
        big = false,
        align = ReceiptAlign.left,
        divider = true;
}

/// Menyusun isi struk (dipakai bersama oleh printer Bluetooth dan PDF).
class ReceiptBuilder {
  static const Map<String, String> paymentLabels = {
    'cash': 'Tunai',
    'qris': 'QRIS',
    'transfer': 'Transfer',
    'card': 'Kartu',
    'gofood': 'GoFood',
    'shopee': 'ShopeeFood',
    'grab': 'GrabFood',
    'other': 'Online',
  };

  static String paymentLabel(String? value) =>
      paymentLabels[value ?? ''] ?? (value == null || value.isEmpty ? 'Tunai' : value);

  static String orderTypeLabel(String? value) {
    switch (value) {
      case 'dine-in':
        return 'Makan di tempat';
      case 'takeaway':
        return 'Bungkus / dibawa pulang';
      case 'online':
        return 'Pesanan online';
      default:
        return value ?? '-';
    }
  }

  static List<ReceiptLine> forOrder(Order order, AppSettings settings) {
    final lines = <ReceiptLine>[];
    lines.addAll(_header(settings));
    lines.add(const ReceiptLine.divider());
    lines.add(ReceiptLine('No. transaksi  ${order.id}'));
    lines.add(ReceiptLine('Waktu          ${formatDateTime(order.createdAt)}'));
    if (order.cashier.isNotEmpty) {
      lines.add(ReceiptLine('Kasir          ${order.cashier}'));
    }
    lines.add(ReceiptLine('Pesanan        ${orderTypeLabel(order.orderType)}'));
    if (order.tableNumber.isNotEmpty) {
      lines.add(ReceiptLine('Meja           ${order.tableNumber}'));
    }
    lines.add(const ReceiptLine.divider());

    for (final item in order.items) {
      lines.add(ReceiptLine(item.name, bold: true));
      lines.add(ReceiptLine(
        '${receiptQty(item.qty)} PCS x ${formatNumber(item.price)} =',
        align: ReceiptAlign.left,
      ));
      lines.add(ReceiptLine(formatNumber(item.total), align: ReceiptAlign.right));
      if (item.note.trim().isNotEmpty) {
        lines.add(ReceiptLine('  * ${item.note.trim()}'));
      }
    }

    lines.add(const ReceiptLine.divider());
    lines.add(ReceiptLine('Subtotal', align: ReceiptAlign.left));
    lines.add(ReceiptLine(formatNumber(order.subtotal), align: ReceiptAlign.right));
    if (order.discount > 0) {
      lines.add(const ReceiptLine('Diskon'));
      lines.add(ReceiptLine('-${formatNumber(order.discount)}', align: ReceiptAlign.right));
    }
    lines.add(ReceiptLine('TOTAL', bold: true, big: true));
    lines.add(ReceiptLine(formatNumber(order.total), bold: true, big: true, align: ReceiptAlign.right));

    if (order.payment == 'cash') {
      lines.add(ReceiptLine('Tunai', align: ReceiptAlign.left));
      lines.add(ReceiptLine(formatNumber(order.paidAmount), align: ReceiptAlign.right));
      if (order.changeAmount > 0) {
        lines.add(const ReceiptLine('Kembali'));
        lines.add(ReceiptLine(formatNumber(order.changeAmount), align: ReceiptAlign.right));
      }
    } else {
      lines.add(ReceiptLine('Metode bayar   ${paymentLabel(order.payment)}'));
    }

    if (order.note.trim().isNotEmpty) {
      lines.add(const ReceiptLine.divider());
      lines.add(ReceiptLine('Catatan: ${order.note.trim()}'));
    }
    lines.add(const ReceiptLine.divider());
    lines.addAll(_footer(settings));
    return lines;
  }

  static List<ReceiptLine> forOnlineTicket(
    OnlineOrder order,
    AppSettings settings, {
    required List<OrderItem> items,
    required int subtotal,
    required int total,
  }) {
    final platform = kOnlinePlatforms[order.source] ?? kOnlinePlatforms['other']!;
    final lines = <ReceiptLine>[];
    lines.addAll(_header(settings));
    lines.add(const ReceiptLine.divider());
    lines.add(ReceiptLine(
      'No. pesanan    ${order.code.isEmpty ? order.id : order.code}',
    ));
    lines.add(ReceiptLine('Platform       $platform'));
    if (order.customer.isNotEmpty) {
      lines.add(ReceiptLine('Pelanggan      ${order.customer}'));
    }
    lines.add(ReceiptLine('Waktu          ${formatDateTime(order.createdAt)}'));
    if (order.status == 'siap' && order.pickupCode.isNotEmpty) {
      lines.add(ReceiptLine('Kode ambil     ${order.pickupCode}', bold: true));
    }
    lines.add(const ReceiptLine.divider());

    for (final item in items) {
      lines.add(ReceiptLine(item.name, bold: true));
      lines.add(ReceiptLine(
        '${receiptQty(item.qty)} PCS x ${formatNumber(item.price)} =',
      ));
      lines.add(ReceiptLine(formatNumber(item.total), align: ReceiptAlign.right));
      if (item.note.trim().isNotEmpty) {
        lines.add(ReceiptLine('  * ${item.note.trim()}'));
      }
    }

    lines.add(const ReceiptLine.divider());
    lines.add(ReceiptLine('Subtotal', align: ReceiptAlign.left));
    lines.add(ReceiptLine(formatNumber(subtotal), align: ReceiptAlign.right));
    lines.add(ReceiptLine('Total', bold: true, big: true));
    lines.add(ReceiptLine(
      formatNumber(total),
      bold: true,
      big: true,
      align: ReceiptAlign.right,
    ));

    if (order.note.trim().isNotEmpty) {
      lines.add(const ReceiptLine.divider());
      lines.add(ReceiptLine('Catatan: ${order.note.trim()}'));
    }
    lines.add(const ReceiptLine.divider());
    lines.addAll(_footer(
      settings,
      fallback: 'Terima kasih sudah memesan!\n'
          'Simpan struk ini sebagai bukti transaksi.',
    ));
    return lines;
  }

  static List<ReceiptLine> _header(AppSettings settings) {
    final lines = <ReceiptLine>[
      ReceiptLine(settings.businessName, bold: true, big: true, align: ReceiptAlign.center),
    ];
    final addressLines = settings.businessAddress
        .split('\n')
        .map((row) => row.trim())
        .where((row) => row.isNotEmpty);
    for (final row in addressLines) {
      lines.add(ReceiptLine(row, align: ReceiptAlign.center));
    }
    if (settings.businessPhone.trim().isNotEmpty) {
      lines.add(ReceiptLine('Telp/WA: ${settings.businessPhone.trim()}', align: ReceiptAlign.center));
    }
    return lines;
  }

  static List<ReceiptLine> _footer(AppSettings settings, {String? fallback}) {
    final text = settings.receiptFooter.trim().isEmpty
        ? (fallback ??
            'Terima kasih sudah makan di tempat!\n'
                'Simpan struk ini sebagai bukti transaksi.')
        : settings.receiptFooter.trim();
    return text
        .split('\n')
        .map((row) => ReceiptLine(row.trim(), align: ReceiptAlign.center))
        .toList();
  }
}

class PrintService {
  /// Daftar printer Bluetooth yang sudah dipasangkan (bonded).
  Future<List<BluetoothDevice>> bondedDevices() async {
    return FlutterBluetoothSerial.instance.getBondedDevices();
  }

  Future<bool> requestEnableBluetooth() async {
    final enabled = await FlutterBluetoothSerial.instance.requestEnable();
    return enabled ?? false;
  }

  Future<bool> isBluetoothEnabled() async {
    return await FlutterBluetoothSerial.instance.isEnabled ?? false;
  }

  /// Kirim struk langsung ke printer thermal 58/80 mm lewat Bluetooth SPP.
  Future<void> printEscPos({
    required String address,
    required List<ReceiptLine> lines,
    required String paperSize,
    int copies = 1,
  }) async {
    final profile = await CapabilityProfile.load();
    final paper = paperSize == '80mm' ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paper, profile);
    final bytes = <int>[];
    for (var copy = 0; copy < copies; copy += 1) {
      for (final line in lines) {
        if (line.divider) {
          bytes.addAll(generator.hr(ch: '-'));
          continue;
        }
        bytes.addAll(generator.text(
          line.text,
          styles: PosStyles(
            bold: line.bold,
            align: switch (line.align) {
              ReceiptAlign.center => PosAlign.center,
              ReceiptAlign.right => PosAlign.right,
              ReceiptAlign.left => PosAlign.left,
            },
            height: line.big ? PosTextSize.size2 : PosTextSize.size1,
            width: line.big ? PosTextSize.size2 : PosTextSize.size1,
          ),
        ));
      }
      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());
    }

    final connection = await BluetoothConnection.toAddress(address);
    try {
      connection.output.add(Uint8List.fromList(bytes));
      await connection.output.allSent;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } finally {
      await connection.finish();
    }
  }

  /// Bagikan struk sebagai PDF (cadangan bila printer Bluetooth tidak siap).
  Future<void> sharePdf({
    required List<ReceiptLine> lines,
    required String filename,
    required String title,
    required String paperSize,
  }) async {
    final doc = pw.Document(title: title);
    final format = switch (paperSize) {
      '80mm' => PdfPageFormat.roll80,
      'A4' => PdfPageFormat.a4,
      _ => PdfPageFormat.roll57,
    };
    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        build: (context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: lines.map((line) {
              if (line.divider) {
                return pw.Divider(thickness: 0.5, height: 6);
              }
              final align = switch (line.align) {
                ReceiptAlign.center => pw.TextAlign.center,
                ReceiptAlign.right => pw.TextAlign.right,
                ReceiptAlign.left => pw.TextAlign.left,
              };
              return pw.Text(
                line.text,
                textAlign: align,
                style: pw.TextStyle(
                  fontSize: line.big ? 11 : 8,
                  fontWeight: line.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  font: pw.Font.courier(),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
