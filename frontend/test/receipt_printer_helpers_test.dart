import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/services/receipt_printer_helpers.dart';

void main() {
  group('formatWeightReceiptQuantity', () {
    test('shows exact grams under 1 kg', () {
      expect(ReceiptPrinterHelpers.formatWeightReceiptQuantity(345), '345g');
      expect(ReceiptPrinterHelpers.formatWeightReceiptQuantity(500), '500g');
    });

    test('shows kg at or above 1 kg without barcode rounding', () {
      expect(ReceiptPrinterHelpers.formatWeightReceiptQuantity(1200), '1.2kg');
      expect(ReceiptPrinterHelpers.formatWeightReceiptQuantity(1210), '1.21kg');
    });

    test('preserves decimal grams', () {
      expect(ReceiptPrinterHelpers.formatWeightReceiptQuantity(345.5), '345.5g');
    });
  });

  group('formatReceiptQuantity', () {
    test('uses item unit_type when product is missing', () {
      expect(
        ReceiptPrinterHelpers.formatReceiptQuantity({
          'quantity': 345,
          'unit_type': 'weight',
        }),
        '345g',
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
