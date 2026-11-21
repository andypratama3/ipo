import 'package:flutter_test/flutter_test.dart';
import 'package:ipomiepangsit_pos/core/format.dart';
import 'package:ipomiepangsit_pos/core/ids.dart';
import 'package:ipomiepangsit_pos/models/models.dart';
import 'package:ipomiepangsit_pos/services/qris_service.dart';

void main() {
  group('format', () {
    test('dateKey memakai tanggal lokal', () {
      expect(dateKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    });

    test('formatRupiah menampilkan rupiah tanpa desimal', () {
      final text = formatRupiah(20000);
      expect(text, contains('20.000'));
      expect(text, isNot(contains(',00')));
    });

    test('formatRupiahShort meringkas nominal besar', () {
      expect(formatRupiahShort(25000), '25 rb');
      expect(formatRupiahShort(1200000), '1,2 jt');
    });
  });

  group('id', () {
    test('newOrderId mengikuti pola backend', () {
      expect(
        newOrderId(DateTime(2026, 11, 20)),
        matches(RegExp(r'^MPJ-20261120-\d{5}$')),
      );
    });

    test('newHoldId mengikuti pola backend', () {
      expect(
        newHoldId(DateTime(2026, 11, 20)),
        matches(RegExp(r'^HOLD-20261120-\d{5}$')),
      );
    });

    test('uuidV4 berformat UUID v4', () {
      expect(
        uuidV4(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });

  group('model', () {
    test('ServerUser membaca displayName, peran, dan status aktif', () {
      final user = ServerUser.fromJson({
        'id': '7',
        'username': 'kasir2',
        'displayName': 'Kasir Dua',
        'role': 'Pemilik',
        'active': false,
      });
      expect(user.id, '7');
      expect(user.name, 'Kasir Dua');
      expect(user.isOwner, isTrue);
      expect(user.active, isFalse);
    });

    test('OnlineOrder mempertahankan field backend yang tidak dikenal', () {
      final order = OnlineOrder.fromJson({
        'id': 'ONL-GF-1',
        'source': 'gofood',
        'status': 'baru',
        'createdAt': '2026-11-20T10:00:00.000Z',
        'partnerOrderId': 'P-123',
        'orderType': 'delivery',
        'items': [
          {'productId': 'mie-kering', 'qty': 2, 'name': 'Mie Kering'},
        ],
      });
      expect(order.extra['partnerOrderId'], 'P-123');
      expect(order.items.single.extra['name'], 'Mie Kering');
      final json = order.toJson();
      expect(json['partnerOrderId'], 'P-123');
      expect((json['items'] as List).single['name'], 'Mie Kering');
    });
  });

  group('QRIS', () {
    test('crc16 cocok dengan vektor uji CCITT', () {
      expect(QrisService.crc16('123456789'), '29B1');
    });

    test('payload kosong ditolak', () {
      expect(QrisService.validate('').valid, isFalse);
    });

    test('TLV hasil bangun ulang bisa dibaca dan divalidasi', () {
      final elements = [
        QrisElement(tag: '00', value: '01'),
        QrisElement(tag: '01', value: '11'),
        QrisElement(tag: '26', value: '0014ID.CO.QRIS.WWW'),
        QrisElement(tag: '52', value: '5812'),
        QrisElement(tag: '53', value: '360'),
        QrisElement(tag: '58', value: 'ID'),
        QrisElement(tag: '59', value: 'MIE PANGST'),
        QrisElement(tag: '60', value: 'JAKARTA'),
      ];
      final withoutCrc = QrisService.buildTlv(elements);
      final payload = '${withoutCrc}6304${QrisService.crc16('${withoutCrc}6304')}';
      final parsed = QrisService.parse(payload);
      expect(parsed.merchantCity, 'JAKARTA');
      expect(QrisService.validate(payload).valid, isTrue);
    });
  });
}
