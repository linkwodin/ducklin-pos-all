import 'product_inventory.dart';
import 'shipment_expected_boxes.dart';
import 'wholesale_order_assignment.dart';

class ShipmentPackingLine {
  ShipmentPackingLine({
    required this.productId,
    required this.expectedQty,
    required this.expectedBoxes,
    required this.product,
  });

  final int productId;
  double expectedQty;
  double expectedBoxes;
  final Map<String, dynamic> product;
}

void _aggregatePackingLine(
  Map<int, ShipmentPackingLine> byProduct,
  int productId,
  Map<String, dynamic> product,
  double expectedQty,
  double expectedBoxes,
) {
  final existing = byProduct[productId];
  if (existing != null) {
    existing.expectedQty += expectedQty;
    existing.expectedBoxes += expectedBoxes;
  } else {
    byProduct[productId] = ShipmentPackingLine(
      productId: productId,
      expectedQty: expectedQty,
      expectedBoxes: expectedBoxes,
      product: product,
    );
  }
}

List<ShipmentPackingLine> _buildLinesFromShipmentItems(List<Map<String, dynamic>> items) {
  final byProduct = <int, ShipmentPackingLine>{};
  for (final si in items) {
    final woItem = si['wholesale_order_item'] as Map<String, dynamic>?;
    final productId = (woItem?['product_id'] as num?)?.toInt();
    final product = woItem?['product'] as Map<String, dynamic>?;
    if (productId == null || product == null) continue;
    final expectedQty = effectiveShipmentItemQty(si);
    final caseQty = (si['case_qty'] as num?)?.toDouble() ?? 0;
    final boxes = caseQty > 0 ? caseQty : 0.0;
    _aggregatePackingLine(byProduct, productId, product, expectedQty, boxes);
  }
  return byProduct.values.toList();
}

List<Map<String, dynamic>> effectiveShipmentItemsForPacking(Map<String, dynamic> shipment) {
  final items = (shipment['items'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
  final hasLines = items.any((si) {
    final woItem = si['wholesale_order_item'] as Map<String, dynamic>?;
    return woItem?['product_id'] != null && woItem?['product'] != null;
  });
  if (hasLines) return items;

  final order = shipment['wholesale_order'] as Map<String, dynamic>?;
  final orderItems = order?['items'] as List<dynamic>? ?? [];
  final storeId = (shipment['store_id'] as num?)?.toInt();
  final forStore = orderItems.whereType<Map<String, dynamic>>().where((oi) {
    return oi['product'] != null &&
        ((oi['assigned_store_id'] as num?)?.toInt() == null ||
            (oi['assigned_store_id'] as num?)?.toInt() == storeId);
  }).toList();
  final source = forStore.isNotEmpty
      ? forStore
      : orderItems.whereType<Map<String, dynamic>>().where((oi) => oi['product'] != null).toList();

  return source.map((oi) {
    final oiId = (oi['id'] as num?)?.toInt() ?? 0;
    return {
      'id': -oiId,
      'shipment_id': shipment['id'],
      'wholesale_order_item_id': oiId,
      'quantity': oi['quantity'],
      'wholesale_order_item': oi,
    };
  }).toList();
}

List<ShipmentPackingLine> buildShipmentPackingLines(Map<String, dynamic> shipment) {
  final fromItems = _buildLinesFromShipmentItems(effectiveShipmentItemsForPacking(shipment));
  if (fromItems.isNotEmpty) return fromItems;

  final byProduct = <int, ShipmentPackingLine>{};
  final order = shipment['wholesale_order'] as Map<String, dynamic>?;
  final orderItems = order?['items'] as List<dynamic>? ?? [];
  final storeId = (shipment['store_id'] as num?)?.toInt();
  for (final oi in orderItems.whereType<Map<String, dynamic>>()) {
    final productId = (oi['product_id'] as num?)?.toInt();
    final product = oi['product'] as Map<String, dynamic>?;
    if (productId == null || product == null) continue;
    final assignedStore = (oi['assigned_store_id'] as num?)?.toInt();
    if (assignedStore != null && assignedStore != storeId) continue;
    final boxes = orderItemExpectedBoxes(oi);
    _aggregatePackingLine(
      byProduct,
      productId,
      product,
      (oi['quantity'] as num?)?.toDouble() ?? 0,
      boxes > 0 ? boxes : 0,
    );
  }
  return byProduct.values.toList();
}

Map<int, Map<String, dynamic>> stockByProductId(List<dynamic> rows) {
  final map = <int, Map<String, dynamic>>{};
  for (final row in rows) {
    if (row is Map<String, dynamic>) {
      final id = (row['product_id'] as num?)?.toInt();
      if (id != null) map[id] = row;
    }
  }
  return map;
}

double availableStockForProduct(Map<String, dynamic>? stock, Map<String, dynamic> product) {
  if (stock == null) return 0;
  if (productIsWeight(product)) {
    return (stock['weight_quantity_g'] as num?)?.toDouble() ??
        (stock['quantity'] as num?)?.toDouble() ??
        0;
  }
  return (stock['quantity'] as num?)?.toDouble() ?? 0;
}

bool hasNoStock(double available) => available <= 0.0001;

String formatPackingQty(double qty) {
  return qty == qty.roundToDouble() ? '${qty.round()}' : qty.toStringAsFixed(2);
}

String packingLineSubtitle(ShipmentPackingLine line) {
  final parts = <String>[];
  if (line.expectedBoxes > 0) {
    parts.add('Expected boxes: ${formatPackingQty(line.expectedBoxes)}');
  }
  parts.add('Qty: ${formatPackingQty(line.expectedQty)}');
  return parts.join(' · ');
}

Map<String, dynamic> initialCaseQtyFromShipment(Map<String, dynamic> shipment) {
  final out = <String, dynamic>{};
  for (final si in effectiveShipmentItemsForPacking(shipment)) {
    final itemId = (si['wholesale_order_item_id'] as num?)?.toInt();
    if (itemId == null) continue;
    final expected = shipmentExpectedBoxes(si);
    final saved = (si['case_qty'] as num?)?.toDouble();
    out['$itemId'] = saved != null && saved > 0 ? saved.round().toString() : expected.round().toString();
  }
  return out;
}

List<Map<String, dynamic>> packingScanCatalog(
  List<Map<String, dynamic>> products,
  Map<String, dynamic> shipment,
) {
  final byId = <int, Map<String, dynamic>>{};
  for (final p in products) {
    final id = (p['id'] as num?)?.toInt();
    if (id != null) byId[id] = Map<String, dynamic>.from(p);
  }
  return buildShipmentPackingLines(shipment).map((line) {
    final catalog = byId[line.productId];
    final lineProduct = line.product;
    String? pick(String? a, String? b) {
      final ta = a?.trim();
      if (ta != null && ta.isNotEmpty) return ta;
      final tb = b?.trim();
      if (tb != null && tb.isNotEmpty) return tb;
      return null;
    }

    return catalog != null
        ? {
            ...catalog,
            ...lineProduct,
            if (pick(catalog['barcode']?.toString(), lineProduct['barcode']?.toString()) != null)
              'barcode': pick(catalog['barcode']?.toString(), lineProduct['barcode']?.toString()),
            if (pick(catalog['sku']?.toString(), lineProduct['sku']?.toString()) != null)
              'sku': pick(catalog['sku']?.toString(), lineProduct['sku']?.toString()),
            if (pick(catalog['weight_barcode']?.toString(), lineProduct['weight_barcode']?.toString()) != null)
              'weight_barcode':
                  pick(catalog['weight_barcode']?.toString(), lineProduct['weight_barcode']?.toString()),
            if (pick(catalog['weight_barcode_prefix']?.toString(), lineProduct['weight_barcode_prefix']?.toString()) !=
                null)
              'weight_barcode_prefix': pick(
                catalog['weight_barcode_prefix']?.toString(),
                lineProduct['weight_barcode_prefix']?.toString(),
              ),
            'sell_by_qty': lineProduct['sell_by_qty'] ?? catalog['sell_by_qty'],
            'sell_by_weight': lineProduct['sell_by_weight'] ?? catalog['sell_by_weight'],
            'unit_type': lineProduct['unit_type'] ?? catalog['unit_type'],
          }
        : lineProduct;
  }).toList();
}

double packingScanDelta(Map<String, dynamic> product, Map<String, dynamic> scanned) => 1;
