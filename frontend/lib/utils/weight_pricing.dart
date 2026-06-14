import 'product_inventory.dart';

/// Reference weight in grams that a retail unit price applies to (default 1000 g = 1 kg).
double effectivePriceWeightG(Map<String, dynamic> product) {
  if (!productSellByWeight(product)) return 1;
  final priceWeight = (product['price_weight_g'] as num?)?.toDouble() ?? 0;
  return priceWeight > 0 ? priceWeight : 1000;
}

/// Billable factor for a line item: quantity for unit products, actual/reference for weight.
/// [lineUnitType] overrides product flags when set (`quantity` or `weight`).
double orderLineFactor(
  Map<String, dynamic> product,
  double quantity, {
  String? lineUnitType,
}) {
  final asWeight = lineUnitType == 'weight' ||
      (lineUnitType == null &&
          productSellByWeight(product) &&
          !productSellByQty(product));
  if (asWeight) {
    final ref = effectivePriceWeightG(product);
    return quantity / (ref > 0 ? ref : 1000);
  }
  return quantity;
}

/// Price suffix when selling by weight (e.g. "/kg").
String weightSalePriceSuffix(Map<String, dynamic> product) {
  if (!productSellByWeight(product)) return '';
  final refG = effectivePriceWeightG(product);
  if (refG == 1000) return '/kg';
  if (refG >= 1000 && refG % 1000 == 0) {
    return '/${(refG / 1000).toStringAsFixed(0)}kg';
  }
  return '/${refG.toStringAsFixed(0)}g';
}

/// Price suffix for product cards, e.g. "/kg" or "/250g".
String priceWeightSuffix(Map<String, dynamic> product) {
  if (!productSellByWeight(product)) return '';
  if (productSellByQty(product) && productSupportsDualInventory(product)) {
    return '';
  }
  return weightSalePriceSuffix(product);
}
