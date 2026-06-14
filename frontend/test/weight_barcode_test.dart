import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/utils/weight_barcode.dart';

void main() {
  group('WeightBarcode.resolvePrefix', () {
    test('uses explicit prefix when set', () {
      expect(
        WeightBarcode.resolvePrefix(prefix: '12345678', productBarcode: '999'),
        '12345678',
      );
    });

    test('uses last 8 digits of product barcode when prefix empty', () {
      expect(
        WeightBarcode.resolvePrefix(prefix: '', productBarcode: '4012345678901'),
        '45678901',
      );
    });

    test('uses full barcode when 8 digits or fewer', () {
      expect(
        WeightBarcode.resolvePrefix(prefix: '', productBarcode: '12345678'),
        '12345678',
      );
    });

    test('returns null when no prefix and no digits in barcode', () {
      expect(WeightBarcode.resolvePrefix(prefix: '', productBarcode: ''), isNull);
      expect(WeightBarcode.resolvePrefix(prefix: '', productBarcode: 'ABC'), isNull);
    });
  });

  group('WeightBarcode.parseReceiptBarcode', () {
    test('1.2 kg from prefix barcode', () {
      final parsed = WeightBarcode.parseReceiptBarcode('1234567801200');
      expect(parsed, isNotNull);
      expect(parsed!.prefix, '12345678');
      expect(parsed.weightGrams, 1200);
    });

    test('returns null for too few digits', () {
      expect(WeightBarcode.parseReceiptBarcode('12345678'), isNull);
    });

    test('normalizePrefixScan pads short prefix', () {
      expect(WeightBarcode.normalizePrefixScan('1234'), '00001234');
      expect(WeightBarcode.normalizePrefixScan('12345678'), '12345678');
    });

    test('normalizePrefixScan rejects long scans', () {
      expect(WeightBarcode.normalizePrefixScan('123456789'), isNull);
    });
  });

  group('WeightBarcode.formatReceiptBarcode', () {
    test('1.2 kg', () {
      expect(
        WeightBarcode.formatReceiptBarcode(prefix: '12345678', weightGrams: 1200),
        '1234567801200',
      );
    });

    test('3.21 kg', () {
      expect(
        WeightBarcode.formatReceiptBarcode(prefix: '12345680', weightGrams: 3210),
        '1234568003210',
      );
    });

    test('0.21 kg', () {
      expect(
        WeightBarcode.formatReceiptBarcode(prefix: '12345679', weightGrams: 210),
        '1234567900210',
      );
    });

    test('pads short prefix to 8 digits', () {
      expect(
        WeightBarcode.formatReceiptBarcode(prefix: '1234', weightGrams: 1200),
        '0000123401200',
      );
    });

    test('falls back to last 8 digits of product barcode', () {
      expect(
        WeightBarcode.formatReceiptBarcode(
          prefix: '',
          productBarcode: '4012345678901',
          weightGrams: 1200,
        ),
        '4567890101200',
      );
    });

    test('returns null without prefix or numeric barcode', () {
      expect(
        WeightBarcode.formatReceiptBarcode(prefix: '', productBarcode: '', weightGrams: 1200),
        isNull,
      );
    });
  });
}
