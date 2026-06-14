import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/utils/weight_pricing.dart';

void main() {
  group('effectivePriceWeightG', () {
    test('defaults to 1000 g for weight products without value', () {
      expect(effectivePriceWeightG({'unit_type': 'weight'}), 1000);
    });

    test('uses configured reference weight', () {
      expect(
        effectivePriceWeightG({'unit_type': 'weight', 'price_weight_g': 250}),
        250,
      );
    });

    test('returns 1 for quantity products', () {
      expect(effectivePriceWeightG({'unit_type': 'quantity'}), 1);
    });
  });

  group('orderLineFactor', () {
    test('quantity product uses quantity directly', () {
      expect(orderLineFactor({'unit_type': 'quantity'}, 3), 3);
    });

    test('weight product at £10/kg with 500 g sold bills 0.5 units', () {
      final product = {'unit_type': 'weight', 'price_weight_g': 1000};
      expect(orderLineFactor(product, 500), 0.5);
    });

    test('weight product priced for 250 g with 500 g sold bills 2 units', () {
      final product = {'unit_type': 'weight', 'price_weight_g': 250};
      expect(orderLineFactor(product, 500), 2);
    });
  });

  group('priceWeightSuffix', () {
    test('shows /kg for 1000 g reference', () {
      expect(priceWeightSuffix({'unit_type': 'weight'}), '/kg');
    });

    test('shows grams when reference is not 1 kg', () {
      expect(
        priceWeightSuffix({'unit_type': 'weight', 'price_weight_g': 250}),
        '/250g',
      );
    });
  });
}
