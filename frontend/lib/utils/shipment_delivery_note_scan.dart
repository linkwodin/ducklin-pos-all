List<String> deliveryNoteScanKeys(Map<String, dynamic> shipment) {
  final order = shipment['wholesale_order'] as Map<String, dynamic>?;
  final orderNumber = order?['order_number']?.toString();
  final keys = <String>[
    if (orderNumber != null && orderNumber.isNotEmpty) orderNumber,
    if (orderNumber != null && orderNumber.isNotEmpty)
      orderNumber.replaceFirst(RegExp(r'^WO-', caseSensitive: false), ''),
    if (order?['po_number'] != null) order!['po_number'].toString(),
    if (order?['ref_no'] != null) order!['ref_no'].toString(),
    shipment['id']?.toString() ?? '',
    shipment['wholesale_order_id']?.toString() ?? '',
    'shipment:${shipment['id']}',
    'shipment-${shipment['id']}',
    if (shipment['tracking_number'] != null) shipment['tracking_number'].toString(),
  ];
  final normalized = keys
      .where((k) => k.trim().isNotEmpty)
      .map((k) => k.trim().toLowerCase())
      .toSet()
      .toList();
  return normalized;
}

bool shipmentMatchesDeliveryNoteScan(Map<String, dynamic> shipment, String raw) {
  final q = raw.trim().toLowerCase();
  if (q.isEmpty) return false;
  final keys = deliveryNoteScanKeys(shipment);
  return keys.any((k) => k == q || k.contains(q) || q.contains(k));
}

bool shipmentMatchesCouriers(Map<String, dynamic> shipment, List<String> couriers) {
  if (couriers.isEmpty) return true;
  final assigned = (shipment['courier']?.toString() ?? '').trim().toLowerCase();
  if (assigned.isEmpty) return true;
  return couriers.any((c) => c.trim().toLowerCase() == assigned);
}
