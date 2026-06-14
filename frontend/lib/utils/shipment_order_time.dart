int _parseDateMs(String? value) {
  if (value == null || value.trim().isEmpty) return 0;
  final trimmed = value.trim();
  final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed);
  final ms = DateTime.tryParse(dateOnly ? '${trimmed}T12:00:00' : trimmed)?.millisecondsSinceEpoch ?? 0;
  return ms;
}

int shipmentOrderTimeMs(Map<String, dynamic> shipment) {
  final order = shipment['wholesale_order'] as Map<String, dynamic>?;
  final orderDateMs = _parseDateMs(order?['order_date']?.toString());
  if (orderDateMs > 0) return orderDateMs;
  final orderCreatedMs = _parseDateMs(order?['created_at']?.toString());
  if (orderCreatedMs > 0) return orderCreatedMs;
  return _parseDateMs(shipment['created_at']?.toString());
}

String? formatShipmentOrderDate(Map<String, dynamic> shipment) {
  final order = shipment['wholesale_order'] as Map<String, dynamic>?;
  final raw = order?['order_date']?.toString().trim() ??
      order?['created_at']?.toString().trim() ??
      shipment['created_at']?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  final dateOnly = raw.length >= 10 ? raw.substring(0, 10) : raw;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateOnly)) return dateOnly;
  final ms = _parseDateMs(raw);
  if (ms <= 0) return null;
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

int sortShipmentsByOrderTimeDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final diff = shipmentOrderTimeMs(b) - shipmentOrderTimeMs(a);
  if (diff != 0) return diff;
  final orderA = a['wholesale_order'] as Map<String, dynamic>?;
  final orderB = b['wholesale_order'] as Map<String, dynamic>?;
  final orderCreatedDiff =
      _parseDateMs(orderB?['created_at']?.toString()) - _parseDateMs(orderA?['created_at']?.toString());
  if (orderCreatedDiff != 0) return orderCreatedDiff;
  final idA = (a['id'] as num?)?.toInt() ?? 0;
  final idB = (b['id'] as num?)?.toInt() ?? 0;
  return idB - idA;
}

int sortShipmentsByOrderTimeAsc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final diff = shipmentOrderTimeMs(a) - shipmentOrderTimeMs(b);
  if (diff != 0) return diff;
  final orderA = a['wholesale_order'] as Map<String, dynamic>?;
  final orderB = b['wholesale_order'] as Map<String, dynamic>?;
  final orderCreatedDiff =
      _parseDateMs(orderA?['created_at']?.toString()) - _parseDateMs(orderB?['created_at']?.toString());
  if (orderCreatedDiff != 0) return orderCreatedDiff;
  final idA = (a['id'] as num?)?.toInt() ?? 0;
  final idB = (b['id'] as num?)?.toInt() ?? 0;
  return idA - idB;
}

Map<String, dynamic> mergeShipmentListRow(
  Map<String, dynamic> existing,
  Map<String, dynamic> updated,
) {
  final merged = Map<String, dynamic>.from(existing)..addAll(updated);
  final existingOrder = existing['wholesale_order'] as Map<String, dynamic>?;
  final updatedOrder = updated['wholesale_order'] as Map<String, dynamic>?;
  if (updatedOrder != null) {
    merged['wholesale_order'] = {...?existingOrder, ...updatedOrder};
  } else if (existingOrder != null) {
    merged['wholesale_order'] = existingOrder;
  }
  final existingStore = existing['store'] as Map<String, dynamic>?;
  final updatedStore = updated['store'] as Map<String, dynamic>?;
  if (updatedStore != null) {
    merged['store'] = {...?existingStore, ...updatedStore};
  }
  merged['items'] = updated['items'] ?? existing['items'];
  return merged;
}

void sortShipmentsListByOrderTimeDesc(List<Map<String, dynamic>> list) {
  list.sort(sortShipmentsByOrderTimeDesc);
}

void sortShipmentsListByOrderTimeAsc(List<Map<String, dynamic>> list) {
  list.sort(sortShipmentsByOrderTimeAsc);
}
