import 'product_display.dart';
import 'shipment_expected_boxes.dart';
import 'wholesale_order_assignment.dart';

class MonitorLine {
  MonitorLine({
    required this.key,
    required this.name,
    required this.qty,
    required this.boxes,
    this.imageUrl,
  });

  final String key;
  final String name;
  final double qty;
  final double? boxes;
  final String? imageUrl;
}

MonitorLine _lineFromShipmentItem(
  Map<String, dynamic> si,
  String lang,
  String Function(int id) itemFallback,
) {
  final woItem = si['wholesale_order_item'] as Map<String, dynamic>?;
  final product = woItem?['product'] as Map<String, dynamic>?;
  final itemId = (si['wholesale_order_item_id'] as num?)?.toInt() ?? 0;
  final name = product != null ? productDisplayName(product, lang) : itemFallback(itemId);
  final boxes = shipmentExpectedBoxes(si);
  return MonitorLine(
    key: 'si-${si['id']}',
    name: name,
    qty: effectiveShipmentItemQty(si),
    boxes: boxes > 0 ? boxes : null,
    imageUrl: product?['image_url']?.toString(),
  );
}

MonitorLine _lineFromOrderItem(Map<String, dynamic> oi, String lang) {
  final product = oi['product'] as Map<String, dynamic>?;
  final id = (oi['id'] as num?)?.toInt() ?? 0;
  final name = product != null ? productDisplayName(product, lang) : 'Item #$id';
  final boxes = orderItemExpectedBoxes(oi);
  return MonitorLine(
    key: 'oi-$id',
    name: name,
    qty: (oi['quantity'] as num?)?.toDouble() ?? 0,
    boxes: boxes > 0 ? boxes : null,
    imageUrl: product?['image_url']?.toString(),
  );
}

List<MonitorLine> monitorLinesForShipment(
  Map<String, dynamic> shipment,
  String lang,
  String Function(int id) itemFallback,
) {
  final items = shipment['items'] as List<dynamic>? ?? [];
  if (items.isNotEmpty) {
    return items
        .whereType<Map<String, dynamic>>()
        .map((si) => _lineFromShipmentItem(si, lang, itemFallback))
        .toList();
  }

  final order = shipment['wholesale_order'] as Map<String, dynamic>?;
  final orderItems = order?['items'] as List<dynamic>? ?? [];
  if (orderItems.isEmpty) return [];

  final storeId = (shipment['store_id'] as num?)?.toInt();
  final forStore = orderItems.whereType<Map<String, dynamic>>().where((oi) {
    final assignedStore = (oi['assigned_store_id'] as num?)?.toInt();
    return assignedStore == null || assignedStore == storeId;
  }).toList();
  final source = forStore.isNotEmpty
      ? forStore
      : orderItems.whereType<Map<String, dynamic>>().toList();
  return source.map((oi) => _lineFromOrderItem(oi, lang)).toList();
}

String formatQtyLabel(double qty) {
  return qty == qty.roundToDouble() ? '${qty.round()}' : qty.toStringAsFixed(2);
}
