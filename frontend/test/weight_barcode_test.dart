import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/utils/weight_barcode.dart';

void main() {
  group('WeightBarcode.resolvePrefix', () {
    test('uses explicit prefix when set', () {
      expect(
        WeightBarcode.resolvePrefix(prefix: '123456', productBarcode: '999'),
        '123456',
      );
    });

    test('uses last 6 digits when explicit prefix is longer', () {
      expect(
        WeightBarcode.resolvePrefix(prefix: '12345678', productBarcode: '999'),
        '345678',
      );
    });

    test('uses leading 6 digits when requested', () {
      expect(
        WeightBarcode.resolvePrefix(prefix: '12345678', productBarcode: '999', preferLeading: true),
        '123456',
      );
    });

    test('uses last 6 digits of product barcode when prefix empty', () {
      expect(
        WeightBarcode.resolvePrefix(prefix: '', productBarcode: '4012345678901'),
        '678901',
      );
    });

    test('pads short barcode to 6 digits', () {
      expect(
        WeightBarcode.resolvePrefix(prefix: '', productBarcode: '1234'),
        '001234',
      );
    });

    test('returns null when no prefix and no digits in barcode', () {
      expect(WeightBarcode.resolvePrefix(prefix: '', productBarcode: ''), isNull);
      expect(WeightBarcode.resolvePrefix(prefix: '', productBarcode: 'ABC'), isNull);
    });
  });

  group('WeightBarcode.parseReceiptBarcode', () {
    test('1.2 kg from prefix barcode', () {
      final parsed = WeightBarcode.parseReceiptBarcode('1234560012000');
      expect(parsed, isNotNull);
      expect(parsed!.prefix, '123456');
      expect(parsed.weightGrams, 1200);
    });

    test('2.333 kg from prefix barcode', () {
      final parsed = WeightBarcode.parseReceiptBarcode('2375400023330');
      expect(parsed, isNotNull);
      expect(parsed!.prefix, '237540');
      expect(parsed.weightGrams, 2333);
    });

    test('returns null for too few digits', () {
      expect(WeightBarcode.parseReceiptBarcode('123456'), isNull);
    });

    test('does not treat EAN-13 product barcodes as receipt barcodes', () {
      expect(WeightBarcode.parseReceiptBarcode('5070002375401'), isNull);
      expect(WeightBarcode.parseReceiptBarcode('5070002375407'), isNull);
    });

    test('normalizePrefixScan pads short prefix', () {
      expect(WeightBarcode.normalizePrefixScan('1234'), '001234');
      expect(WeightBarcode.normalizePrefixScan('123456'), '123456');
    });

    test('normalizePrefixScan rejects long scans', () {
      expect(WeightBarcode.normalizePrefixScan('1234567'), isNull);
    });
  });

  group('WeightBarcode.formatReceiptBarcode', () {
    test('1.2 kg', () {
      expect(
        WeightBarcode.formatReceiptBarcode(prefix: '123456', weightGrams: 1200),
        '1234560012000',
      );
    });

    test('2.333 kg', () {
      expect(
        WeightBarcode.formatReceiptBarcode(prefix: '237540', weightGrams: 2333),
        '2375400023330',
      );
    });

    test('3.21 kg', () {
      expect(
        WeightBarcode.formatReceiptBarcode(prefix: '123456', weightGrams: 3210),
        '1234560032100',
      );
    });

    test('0.21 kg', () {
      expect(
        WeightBarcode.formatReceiptBarcode(prefix: '123456', weightGrams: 210),
        '1234560002100',
      );
    });

    test('pads short prefix to 6 digits', () {
      expect(
        WeightBarcode.formatReceiptBarcode(prefix: '1234', weightGrams: 1200),
        '0012340012000',
      );
    });

    test('falls back to last 6 digits of product barcode', () {
      expect(
        WeightBarcode.formatReceiptBarcode(
          prefix: '',
          productBarcode: '4012345678901',
          weightGrams: 1200,
        ),
        '6789010012000',
      );
    });

    test('truncates 7-digit weight barcode to leading 6 digits', () {
      expect(
        WeightBarcode.formatReceiptBarcode(
          prefix: '2375401',
          weightGrams: 2333,
        ),
        '2375400023330',
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
