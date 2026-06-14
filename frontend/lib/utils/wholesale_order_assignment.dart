double effectiveShipmentItemQty(Map<String, dynamic> si) {
  final qty = (si['quantity'] as num?)?.toDouble();
  if (qty != null && qty > 0) return qty;
  final woItem = si['wholesale_order_item'] as Map<String, dynamic>?;
  return (woItem?['quantity'] as num?)?.toDouble() ?? 0;
}

String formatAssignmentQty(double qty) {
  return qty == qty.roundToDouble() ? '${qty.round()}' : qty.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
}

({int productCount, double totalQty, double totalBoxes}) shipmentAssignedSummary(
  Map<String, dynamic> shipment,
) {
  final items = shipment['items'] as List<dynamic>? ?? [];
  var totalQty = 0.0;
  var totalBoxes = 0.0;
  for (final si in items) {
    if (si is! Map<String, dynamic>) continue;
    totalQty += effectiveShipmentItemQty(si);
    final caseQty = (si['case_qty'] as num?)?.toDouble();
    if (caseQty != null && caseQty > 0) totalBoxes += caseQty;
  }
  return (productCount: items.length, totalQty: totalQty, totalBoxes: totalBoxes);
}
