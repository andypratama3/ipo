import 'package:collection/collection.dart';

/// Port dari `qris.js`: TLV EMVCo, CRC16-CCITT, dan konversi statis → dinamis.
class QrisElement {
  QrisElement({
    required this.tag,
    required this.value,
    this.name = '',
    this.children,
  });

  final String tag;
  final String value;
  final String name;
  final List<QrisElement>? children;

  int get numericTag => int.tryParse(tag) ?? -1;
}

class QrisValidation {
  const QrisValidation(this.valid, this.errors);
  final bool valid;
  final List<String> errors;
}

class QrisParseResult {
  QrisParseResult({
    required this.version,
    required this.method,
    required this.merchantName,
    required this.merchantCity,
    required this.amount,
    required this.currency,
    required this.countryCode,
    required this.crc,
    required this.elements,
  });

  final String version;
  final String method; // 'static' | 'dynamic'
  final String merchantName;
  final String merchantCity;
  final String? amount;
  final String currency;
  final String countryCode;
  final String crc;
  final List<QrisElement> elements;

  bool get isDynamic => method == 'dynamic';
}

class QrisService {
  static const Map<String, String> _tagNames = {
    '00': 'Payload Format Indicator',
    '01': 'Point of Initiation Method',
    '26': 'Merchant Account Information',
    '27': 'Merchant Account Information',
    '28': 'Merchant Account Information',
    '29': 'Merchant Account Information',
    '30': 'Merchant Account Information',
    '51': 'Merchant Account Information',
    '52': 'Merchant Category Code',
    '53': 'Transaction Currency',
    '54': 'Transaction Amount',
    '55': 'Tip or Convenience Indicator',
    '56': 'Value of Convenience Fee Fixed',
    '57': 'Value of Convenience Fee Percentage',
    '58': 'Country Code',
    '59': 'Merchant Name',
    '60': 'Merchant City',
    '61': 'Postal Code',
    '62': 'Additional Data Field',
    '63': 'CRC',
  };

  static bool _isNested(String tag) {
    final n = int.tryParse(tag) ?? -1;
    return (n >= 26 && n <= 51) || tag == '62';
  }

  /// Sama dengan `qris.js`: hanya memangkas spasi di ujung, tidak mengubah isi
  /// payload (spasi di nama merchant adalah bagian dari data).
  static String sanitize(String raw) => raw.trim();

  static List<QrisElement> parseTlv(String data) {
    final elements = <QrisElement>[];
    var pos = 0;
    while (pos < data.length) {
      if (pos + 4 > data.length) break;
      final tag = data.substring(pos, pos + 2);
      final length = int.tryParse(data.substring(pos + 2, pos + 4));
      if (length == null || pos + 4 + length > data.length) break;
      final value = data.substring(pos + 4, pos + 4 + length);
      elements.add(QrisElement(
        tag: tag,
        value: value,
        name: _tagNames[tag] ?? 'Unknown ($tag)',
        children: _isNested(tag) ? parseTlv(value) : null,
      ));
      pos += 4 + length;
    }
    return elements;
  }

  static QrisParseResult parse(String payload) {
    final raw = parseTlv(sanitize(payload));
    QrisElement? findTag(String tag) {
      for (final element in raw) {
        if (element.tag == tag) return element;
      }
      return null;
    }

    final methodValue = findTag('01')?.value ?? '';
    return QrisParseResult(
      version: findTag('00')?.value ?? '01',
      method: methodValue == '12' ? 'dynamic' : 'static',
      merchantName: findTag('59')?.value ?? '',
      merchantCity: findTag('60')?.value ?? '',
      amount: findTag('54')?.value,
      currency: findTag('53')?.value ?? '360',
      countryCode: findTag('58')?.value ?? 'ID',
      crc: findTag('63')?.value ?? '',
      elements: raw,
    );
  }

  static QrisValidation validate(String payload) {
    final errors = <String>[];
    final str = sanitize(payload);
    if (str.isEmpty) return const QrisValidation(false, ['String QRIS kosong']);
    if (!str.startsWith('000201')) {
      errors.add('QRIS harus diawali Payload Format Indicator "000201"');
    }
    if (str.length < 20) {
      errors.add('String QRIS terlalu pendek');
      return QrisValidation(false, errors);
    }
    final dataWithoutCrc = str.substring(0, str.length - 4);
    final declaredCrc = str.substring(str.length - 4).toUpperCase();
    final calculated = crc16(dataWithoutCrc);
    if (declaredCrc != calculated) {
      errors.add('CRC tidak cocok: diharapkan $calculated, ditemukan $declaredCrc');
    }
    final elements = parseTlv(str);
    if (elements.isEmpty) {
      errors.add('Gagal membaca struktur TLV');
      return QrisValidation(false, errors);
    }
    final tags = {for (final element in elements) element.tag};
    const required = {
      '00': 'Payload Format Indicator',
      '01': 'Point of Initiation Method',
      '52': 'Merchant Category Code',
      '53': 'Transaction Currency',
      '58': 'Country Code',
      '59': 'Merchant Name',
      '60': 'Merchant City',
      '63': 'CRC',
    };
    required.forEach((tag, name) {
      if (!tags.contains(tag)) errors.add('Tag wajib $tag ($name) tidak ada');
    });
    final method = elements.where((element) => element.tag == '01').firstOrNull;
    if (method != null && method.value != '11' && method.value != '12') {
      errors.add('Point of Initiation Method tidak valid: "${method.value}" (harus "11" atau "12")');
    }
    final hasMerchant = elements.any((element) {
      final n = element.numericTag;
      return n >= 26 && n <= 51;
    });
    if (!hasMerchant) {
      errors.add('Tidak ada Merchant Account Information (tag 26-51)');
    }
    return QrisValidation(errors.isEmpty, errors);
  }

  static String buildTlv(List<QrisElement> elements) {
    final buffer = StringBuffer();
    for (final element in elements) {
      final value = element.children != null
          ? buildTlv(element.children!)
          : element.value;
      final length = value.length.toString().padLeft(2, '0');
      buffer
        ..write(element.tag)
        ..write(length)
        ..write(value);
    }
    return buffer.toString();
  }

  /// QRIS statis + nominal → QRIS dinamis (tag 01 = "12", tag 54 = nominal).
  static String convert(String payload, {required int amount}) {
    if (amount <= 0) {
      throw const FormatException('Nominal QRIS tidak valid.');
    }
    if (amount > 99999999) {
      throw const FormatException('Nominal melebihi batas QRIS (maks Rp 99.999.999).');
    }
    final elements = parseTlv(sanitize(payload));
    final result = <QrisElement>[];
    var amountInserted = false;
    const insertBefore = {'58', '59', '60', '61', '62', '63'};
    const managedTags = {'54', '55', '56', '57', '63'};

    void pushAmount() {
      result.add(QrisElement(tag: '54', value: amount.toString(), name: 'Transaction Amount'));
    }

    for (final element in elements) {
      if (managedTags.contains(element.tag)) continue;
      if (element.tag == '01') {
        result.add(QrisElement(
          tag: '01',
          value: '12',
          name: 'Point of Initiation Method',
        ));
        continue;
      }
      if (!amountInserted && insertBefore.contains(element.tag)) {
        pushAmount();
        amountInserted = true;
      }
      result.add(element);
    }
    if (!amountInserted) pushAmount();

    final withoutCrc = buildTlv(result);
    final crcInput = '${withoutCrc}6304';
    return '$crcInput${crc16(crcInput)}';
  }

  static String crc16(String input) {
    var crc = 0xFFFF;
    for (var i = 0; i < input.length; i += 1) {
      crc ^= (input.codeUnitAt(i) & 0xFF) << 8;
      for (var j = 0; j < 8; j += 1) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }
}
