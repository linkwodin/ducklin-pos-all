import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/utils/product_barcode.dart';

void main() {
  final weightProduct = {
    'id': 1,
    'name': 'Apples',
    'barcode': '11111111',
    'sell_by_qty': 0,
    'sell_by_weight': 1,
    'weight_barcode_prefix': '12345678',
  };

  final dualProduct = {
    'id': 2,
    'name': 'Cheese',
    'barcode': '22222222',
    'weight_barcode': '33333333',
    'sell_by_qty': 1,
    'sell_by_weight': 1,
    'weight_barcode_prefix': '87654321',
  };

  group('resolveProductScanFromList prefix-only', () {
    test('matches 8-digit weight prefix', () {
      final result = resolveProductScanFromList('12345678', [weightProduct]);
      expect(result, isNotNull);
      expect(result!['id'], 1);
      expect(result['_scan_mode'], 'weight');
      expect(parsedWeightGramsFromScan(result), isNull);
    });

    test('matches short prefix padded to 8 digits', () {
      final product = Map<String, dynamic>.from(weightProduct)
        ..['weight_barcode_prefix'] = '1234';
      final result = resolveProductScanFromList('1234', [product]);
      expect(result, isNotNull);
      expect(result!['_scan_mode'], 'weight');
    });

    test('does not match qty barcode via prefix when product sells by qty', () {
      final qtyProduct = {
        'id': 3,
        'name': 'Bottle',
        'barcode': '12345678',
        'sell_by_qty': 1,
        'sell_by_weight': 0,
      };
      final result = resolveProductScanFromList('12345678', [qtyProduct, weightProduct]);
      expect(result, isNotNull);
      expect(result!['id'], 3);
      expect(result['_scan_mode'], 'qty');
    });

    test('dual-inventory product resolves by weight prefix', () {
      final result = resolveProductScanFromList('87654321', [dualProduct]);
      expect(result, isNotNull);
      expect(result!['id'], 2);
      expect(result['_scan_mode'], 'weight');
    });

    test('matches EAN-13 when only check digit differs', () {
      final product = {
        'id': 4,
        'name': 'Scallop',
        'barcode': '5070002472197',
        'sell_by_qty': 1,
        'sell_by_weight': 0,
      };
      // Scanner may send corrected check digit (3) while DB has 7.
      final result = resolveProductScanFromList('5070002472193', [product]);
      expect(result, isNotNull);
      expect(result!['id'], 4);
      expect(result['_scan_mode'], 'qty');
    });

    test('returns blocked flag when barcode matches but qty sale disabled', () {
      final product = {
        'id': 5,
        'name': 'Weight only',
        'barcode': '5070002472197',
        'sell_by_qty': 0,
        'sell_by_weight': 1,
      };
      final result = resolveProductScanFromList('5070002472197', [product]);
      expect(result, isNotNull);
      expect(result!['_sale_mode_blocked'], isTrue);
    });
  });
}
