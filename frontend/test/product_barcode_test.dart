import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/utils/product_barcode.dart';

void main() {
  final weightProduct = {
    'id': 1,
    'name': 'Apples',
    'unit_type': 'weight',
    'barcode': '11111111',
    'sell_by_qty': 0,
    'sell_by_weight': 1,
    'weight_barcode_prefix': '12345678',
  };

  final weightVariantWithPrefix = {
    'id': 2,
    'name': 'Cheese',
    'unit_type': 'weight',
    'barcode': '22222222',
    'weight_barcode': '33333333',
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
        'unit_type': 'quantity',
        'barcode': '12345678',
      };
      final result = resolveProductScanFromList('12345678', [qtyProduct, weightProduct]);
      expect(result, isNotNull);
      expect(result!['id'], 3);
      expect(result['_scan_mode'], 'qty');
    });

    test('weight variant resolves by weight prefix', () {
      final result = resolveProductScanFromList('87654321', [weightVariantWithPrefix]);
      expect(result, isNotNull);
      expect(result!['id'], 2);
      expect(result['_scan_mode'], 'weight');
    });

    test('matches EAN-13 when only check digit differs', () {
      final product = {
        'id': 4,
        'name': 'Scallop',
        'unit_type': 'quantity',
        'barcode': '5070002472197',
      };
      // Scanner may send corrected check digit (3) while DB has 7.
      final result = resolveProductScanFromList('5070002472193', [product]);
      expect(result, isNotNull);
      expect(result!['id'], 4);
      expect(result['_scan_mode'], 'qty');
    });

    test('weight-only variant resolves barcode as weight sale', () {
      final product = {
        'id': 5,
        'name': 'Weight only',
        'unit_type': 'weight',
        'barcode': '5070002472197',
      };
      final result = resolveProductScanFromList('5070002472197', [product]);
      expect(result, isNotNull);
      expect(result!['_scan_mode'], 'weight');
    });

    test('qty variant wins over weight sibling on same product line', () {
      final qtyVariant = {
        'id': 10,
        'name': 'Ducklin Co. Dalian Dried Abalone – 40 heads',
        'unit_type': 'quantity',
        'barcode': '5070002472197',
        'product_line_id': 100,
        'variant_label': '40 heads',
      };
      final weightVariant = {
        'id': 11,
        'name': 'Ducklin Co. Dalian Dried Abalone – per 150g',
        'unit_type': 'weight',
        'barcode': '',
        'weight_barcode_prefix': '72472197',
        'product_line_id': 100,
        'variant_label': '150',
        'price_weight_g': 150,
      };
      final result = resolveProductScanFromList('5070002472197', [weightVariant, qtyVariant]);
      expect(result, isNotNull);
      expect(result!['id'], 10);
      expect(result['_scan_mode'], 'qty');
    });

    test('matches stored barcode with formatting characters', () {
      final product = {
        'id': 6,
        'name': 'Formatted barcode',
        'unit_type': 'quantity',
        'barcode': '5-070-002472197',
      };
      final result = resolveProductScanFromList('5070002472197', [product]);
      expect(result, isNotNull);
      expect(result!['_scan_mode'], 'qty');
    });

    test('matches UPC-A 12-digit scan against EAN-13 stored barcode', () {
      final product = {
        'id': 7,
        'name': 'UPC product',
        'unit_type': 'quantity',
        'barcode': '0123456789012',
      };
      final result = resolveProductScanFromList('123456789012', [product]);
      expect(result, isNotNull);
      expect(result!['_scan_mode'], 'qty');
    });

    test('Dalian abalone qty barcode is not stolen by scallop weight prefix', () {
      final abaloneQty = {
        'id': 4,
        'name': 'Ducklin Co. Dalian Dried Abalone 40 heads – 150g 庄',
        'unit_type': 'quantity',
        'barcode': '5070002375401',
        'sku': '5070002375401',
        'product_line_id': 3,
      };
      final abaloneWeight = {
        'id': 278,
        'name': 'Ducklin Co. Dalian Dried Abalone 40 heads – per 150g',
        'unit_type': 'weight',
        'barcode': '',
        'sku': '5070002375401-WT',
        'weight_barcode': '2375401',
        'weight_barcode_prefix': '2375401',
        'product_line_id': 3,
      };
      final scallopWeight = {
        'id': 35,
        'name': 'Ducklin Co. Qingdao Dried Scallop 400 heads 150g – per 150g',
        'unit_type': 'weight',
        'weight_barcode': '50700023',
        'weight_barcode_prefix': '50700023',
      };
      final result = resolveProductScanFromList(
        '5070002375407',
        [scallopWeight, abaloneWeight, abaloneQty],
      );
      expect(result, isNotNull);
      expect(result!['id'], 4);
      expect(result['_scan_mode'], 'qty');
    });

    test('weight prefix 2375401 beats qty EAN suffix on same product line', () {
      final abaloneQty = {
        'id': 4,
        'unit_type': 'quantity',
        'barcode': '5070002375401',
        'product_line_id': 3,
      };
      final abaloneWeight = {
        'id': 278,
        'unit_type': 'weight',
        'sell_by_weight': 1,
        'weight_barcode': '2375401',
        'weight_barcode_prefix': '2375401',
        'product_line_id': 3,
      };
      final result = resolveProductScanFromList('2375401', [abaloneQty, abaloneWeight]);
      expect(result, isNotNull);
      expect(result!['id'], 278);
      expect(result['_scan_mode'], 'weight');
    });

    test('weight barcode resolves via sell_by_weight when unit_type missing', () {
      final abaloneWeight = {
        'id': 278,
        'sell_by_weight': 1,
        'weight_barcode': '2375401',
        'weight_barcode_prefix': '2375401',
        'product_line_id': 3,
      };
      final result = resolveProductScanFromList('2375401', [abaloneWeight]);
      expect(result, isNotNull);
      expect(result!['_scan_mode'], 'weight');
    });

    test('fuzzy weight barcode 2475401 resolves to weight variant', () {
      final abaloneQty = {
        'id': 4,
        'unit_type': 'quantity',
        'barcode': '5070002375401',
        'product_line_id': 3,
      };
      final abaloneWeight = {
        'id': 278,
        'unit_type': 'weight',
        'weight_barcode': '2375401',
        'weight_barcode_prefix': '2375401',
        'product_line_id': 3,
      };
      final result = resolveProductScanFromList('2475401', [abaloneWeight, abaloneQty]);
      expect(result, isNotNull);
      expect(result!['id'], 278);
      expect(result['_scan_mode'], 'weight');
    });

    test('weight SKU with -WT suffix does not steal qty EAN scan', () {
      final qty = {
        'id': 4,
        'unit_type': 'quantity',
        'barcode': '5070002375401',
        'sku': '5070002375401',
        'product_line_id': 3,
      };
      final weight = {
        'id': 278,
        'unit_type': 'weight',
        'barcode': '',
        'sku': '5070002375401-WT',
        'weight_barcode': '2375401',
        'weight_barcode_prefix': '2375401',
        'product_line_id': 3,
      };
      final result = resolveProductScanFromList('5070002375401', [weight, qty]);
      expect(result, isNotNull);
      expect(result!['id'], 4);
      expect(result['_scan_mode'], 'qty');
    });
  });
}
