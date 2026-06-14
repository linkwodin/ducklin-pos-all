import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/utils/product_barcode_packing.dart';
import 'package:pos_system/utils/shipment_packing.dart';

void main() {
  group('resolveProductScanForPacking', () {
    test('does not match a sibling variant barcode on the same product line', () {
      const scanned = '5065018084041';
      const targetBarcode = '5065017084003';

      final shipment = {
        'items': [
          {
            'quantity': 5,
            'wholesale_order_item_id': 1,
            'wholesale_order_item': {
              'product_id': 100,
              'product': {
                'id': 100,
                'barcode': targetBarcode,
                'sell_by_qty': 1,
                'sell_by_weight': 0,
                'product_line_id': 999,
              },
            },
          },
        ],
      };

      final packingLines = buildShipmentPackingLines(shipment);
      final scanCatalog = packingScanCatalog(
        [
          {
            'id': 100,
            'barcode': targetBarcode,
            'product_line_id': 999,
          },
          {
            'id': 200,
            'barcode': scanned,
            'product_line_id': 999,
          },
        ],
        shipment,
      );

      expect(scanCatalog.length, 1);
      expect(resolveProductScanForPacking(scanned, packingLines, scanCatalog), isNull);
    });

    test('does not match via shared weight barcode prefix', () {
      const scanned = '5065018084041';
      const targetBarcode = '5065017084003';
      final shipment = {
        'items': [
          {
            'quantity': 5,
            'wholesale_order_item_id': 1,
            'wholesale_order_item': {
              'product_id': 100,
              'product': {
                'id': 100,
                'barcode': targetBarcode,
                'weight_barcode_prefix': '50650180',
                'sell_by_qty': 1,
                'sell_by_weight': 0,
              },
            },
          },
        ],
      };
      final packingLines = buildShipmentPackingLines(shipment);
      final scanCatalog = packingScanCatalog(
        [
          {
            'id': 100,
            'barcode': targetBarcode,
            'weight_barcode_prefix': '50650180',
          },
        ],
        shipment,
      );
      expect(resolveProductScanForPacking(scanned, packingLines, scanCatalog), isNull);
    });

    test('still matches the shipment product barcode', () {
      const barcode = '5065017084003';
      final shipment = {
        'items': [
          {
            'quantity': 2,
            'wholesale_order_item_id': 1,
            'wholesale_order_item': {
              'product_id': 100,
              'product': {
                'id': 100,
                'barcode': barcode,
                'sell_by_qty': 1,
                'sell_by_weight': 0,
              },
            },
          },
        ],
      };
      final packingLines = buildShipmentPackingLines(shipment);
      final scanCatalog = packingScanCatalog(
        [
          {'id': 100, 'barcode': barcode},
          {'id': 200, 'barcode': '5065018084041'},
        ],
        shipment,
      );

      final result = resolveProductScanForPacking(barcode, packingLines, scanCatalog);
      expect(result, isNotNull);
      expect(result!['id'], 100);
      expect(result['_scan_mode'], 'qty');
    });
  });
}
