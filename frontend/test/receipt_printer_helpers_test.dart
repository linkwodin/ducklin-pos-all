import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/services/receipt_printer_helpers.dart';

void main() {
  group('formatWeightReceiptQuantity', () {
    test('always shows kg with three decimal places', () {
      expect(ReceiptPrinterHelpers.formatWeightReceiptQuantity(500), '0.500kg');
      expect(ReceiptPrinterHelpers.formatWeightReceiptQuantity(1200), '1.200kg');
      expect(ReceiptPrinterHelpers.formatWeightReceiptQuantity(2333), '2.333kg');
    });

    test('rounds grams to match barcode thousandths', () {
      expect(ReceiptPrinterHelpers.formatWeightReceiptQuantity(2333.4), '2.333kg');
      expect(ReceiptPrinterHelpers.formatWeightReceiptQuantity(2333.6), '2.334kg');
    });
  });

  group('formatReceiptQuantity', () {
    test('uses item unit_type when product is missing', () {
      expect(
        ReceiptPrinterHelpers.formatReceiptQuantity({
          'quantity': 2333,
          'unit_type': 'weight',
        }),
        '2.333kg',
      );
    });

    test('quantity products use integer qty', () {
      expect(
        ReceiptPrinterHelpers.formatReceiptQuantity({
          'quantity': 3,
          'unit_type': 'quantity',
        }),
        '3 ',
      );
    });
  });
}
