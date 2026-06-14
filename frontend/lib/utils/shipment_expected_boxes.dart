double computedExpectedBoxes(double quantity, num? wholesaleUnitsPerBox) {
  final upb = (wholesaleUnitsPerBox ?? 0).toDouble();
  if (upb > 0 && quantity > 0) return (quantity / upb).ceilToDouble();
  return quantity.roundToDouble();
}

double shipmentExpectedBoxes(Map<String, dynamic> si) {
  final caseQty = (si['case_qty'] as num?)?.toDouble();
  if (caseQty != null && caseQty > 0) return caseQty;
  final woItem = si['wholesale_order_item'] as Map<String, dynamic>?;
  final qty = (woItem?['quantity'] as num?)?.toDouble() ?? 0;
  final product = woItem?['product'] as Map<String, dynamic>?;
  return computedExpectedBoxes(qty, product?['wholesale_units_per_box'] as num?);
}

double orderItemExpectedBoxes(Map<String, dynamic> item) {
  final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
  final product = item['product'] as Map<String, dynamic>?;
  return computedExpectedBoxes(qty, product?['wholesale_units_per_box'] as num?);
}

double shipmentTotalBoxes(Map<String, dynamic> shipment) {
  final items = shipment['items'] as List<dynamic>? ?? [];
  return items.fold<double>(0, (sum, si) {
    if (si is Map<String, dynamic>) return sum + shipmentExpectedBoxes(si);
    return sum;
  });
}
