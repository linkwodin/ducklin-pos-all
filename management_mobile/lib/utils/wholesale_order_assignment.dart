import '../models/shipment.dart';
import '../models/stock.dart';
import '../models/wholesale_order.dart';

class StagedStoreAssignment {
  const StagedStoreAssignment({
    required this.wholesaleOrderItemId,
    required this.storeId,
    required this.quantity,
  });

  final int wholesaleOrderItemId;
  final int storeId;
  final double quantity;

  Map<String, dynamic> toJson() => {
        'wholesale_order_item_id': wholesaleOrderItemId,
        'store_id': storeId,
        'quantity': quantity,
      };
}

enum StoreStockHighlight { none, partial, full }

class AssignStoreStockHint {
  const AssignStoreStockHint({required this.text, required this.sufficient});
  final String text;
  final bool sufficient;
}

double effectiveShipmentItemQty(ShipmentItem si) {
  if (si.quantity != null && si.quantity! > 0) return si.quantity!;
  return si.wholesaleOrderItem?.quantity ?? 0;
}

double assignedQtyForOrderItem(WholesaleOrder order, int itemId) {
  var sum = 0.0;
  for (final sh in order.shipments) {
    for (final si in sh.items) {
      if (si.wholesaleOrderItemId == itemId) {
        sum += effectiveShipmentItemQty(si);
      }
    }
  }
  return sum;
}

double pendingQtyForOrderItem(WholesaleOrder order, WholesaleOrderItem item) {
  return (item.quantity - assignedQtyForOrderItem(order, item.id)).clamp(0, double.infinity);
}

bool orderLineFullyAssigned(WholesaleOrder order, WholesaleOrderItem item) {
  return pendingQtyForOrderItem(order, item) <= 0.0001;
}

bool allOrderLinesFullyAssigned(WholesaleOrder order) {
  return order.items.isNotEmpty && order.items.every((it) => orderLineFullyAssigned(order, it));
}

bool shipmentStatusAllowsAssignmentChange(String status) {
  final normalized = status.toLowerCase();
  return normalized == 'assigned' || normalized == 'packing';
}

Shipment? storeShipmentForOrder(WholesaleOrder order, int storeId) {
  for (final s in order.shipments) {
    if (s.storeId == storeId) return s;
  }
  return null;
}

bool storeAllowsAssignmentTarget(WholesaleOrder order, int storeId) {
  final shipment = storeShipmentForOrder(order, storeId);
  if (shipment == null) return true;
  return shipmentStatusAllowsAssignmentChange(shipment.status);
}

bool orderLinesHaveAssignedStore(WholesaleOrder order) {
  return order.items.isNotEmpty && order.items.every((it) => it.assignedStoreId != null);
}

bool isAssignmentComplete(WholesaleOrder order, {Iterable<String>? completedAssignmentActions}) {
  if (allOrderLinesFullyAssigned(order)) return true;
  if (completedAssignmentActions?.contains('wholesale_order_complete_assignment') == true) {
    return true;
  }
  if (order.shipments.isEmpty) return false;
  final shipmentLinesLoaded = order.shipments.any((s) => s.items.isNotEmpty);
  if (!shipmentLinesLoaded) return orderLinesHaveAssignedStore(order);
  // List payloads may omit nested shipment line qty while detail loads full rows.
  // Once stores are assigned and shipments have started or finished, treat allocation as done.
  if (orderLinesHaveAssignedStore(order)) {
    if (order.shipments.any((s) => !shipmentStatusAllowsAssignmentChange(s.status))) {
      return true;
    }
  }
  return false;
}

bool orderAllowsAssignmentChange(WholesaleOrder order) {
  for (final item in order.items) {
    if (pendingQtyForOrderItem(order, item) > 0.0001) return true;
  }
  for (final sh in order.shipments) {
    if (!shipmentStatusAllowsAssignmentChange(sh.status)) continue;
    if (sh.items.isNotEmpty) return true;
  }
  return false;
}

bool wholesaleOrderCanAssign(WholesaleOrder order) {
  return order.status == 'pending_approval' ||
      order.status == 'approved' ||
      order.status == 'assign_shipment';
}

double stagedQtyForOrderItem(List<StagedStoreAssignment> staged, int itemId) {
  return staged
      .where((a) => a.wholesaleOrderItemId == itemId)
      .fold(0.0, (sum, a) => sum + a.quantity);
}

double pendingQtyForOrderItemWithStaging(
  WholesaleOrder order,
  WholesaleOrderItem item,
  List<StagedStoreAssignment> staged,
) {
  return (item.quantity - assignedQtyForOrderItem(order, item.id) - stagedQtyForOrderItem(staged, item.id))
      .clamp(0, double.infinity);
}

bool allOrderLinesFullyStaged(WholesaleOrder order, List<StagedStoreAssignment> staged) {
  return order.items.isNotEmpty &&
      order.items.every((it) => pendingQtyForOrderItemWithStaging(order, it, staged) <= 0.0001);
}

List<StagedStoreAssignment> removeStagedAssignmentQty(
  List<StagedStoreAssignment> staged,
  int itemId,
  int storeId,
  double quantity,
) {
  var remaining = quantity;
  final result = <StagedStoreAssignment>[];
  for (final a in staged) {
    if (a.wholesaleOrderItemId == itemId && a.storeId == storeId && remaining > 0.0001) {
      if (a.quantity <= remaining + 0.0001) {
        remaining -= a.quantity;
        continue;
      }
      result.add(StagedStoreAssignment(
        wholesaleOrderItemId: a.wholesaleOrderItemId,
        storeId: a.storeId,
        quantity: a.quantity - remaining,
      ));
      remaining = 0;
    } else {
      result.add(a);
    }
  }
  return result;
}

class OrderItemStoreAssignment {
  const OrderItemStoreAssignment({
    required this.storeId,
    required this.storeName,
    required this.quantity,
    required this.canUnassign,
    required this.staged,
  });

  final int storeId;
  final String storeName;
  final double quantity;
  final bool canUnassign;
  final bool staged;
}

List<OrderItemStoreAssignment> orderItemStoreAssignments(
  WholesaleOrder order,
  int itemId,
  List<StagedStoreAssignment> staged,
  Map<int, String> storeNameById,
) {
  final entries = <OrderItemStoreAssignment>[];
  for (final sh in order.shipments) {
    final canUnassign = shipmentStatusAllowsAssignmentChange(sh.status);
    for (final si in sh.items) {
      if (si.wholesaleOrderItemId != itemId) continue;
      entries.add(OrderItemStoreAssignment(
        storeId: sh.storeId,
        storeName: (sh.store?.name ?? '').trim().isNotEmpty ? sh.store!.name : 'Store #${sh.storeId}',
        quantity: effectiveShipmentItemQty(si),
        canUnassign: canUnassign,
        staged: false,
      ));
    }
  }
  for (final a in staged) {
    if (a.wholesaleOrderItemId != itemId) continue;
    entries.add(OrderItemStoreAssignment(
      storeId: a.storeId,
      storeName: storeNameById[a.storeId] ?? 'Store #${a.storeId}',
      quantity: a.quantity,
      canUnassign: true,
      staged: true,
    ));
  }
  return entries;
}

bool canChangeWholesaleAssignment(
  WholesaleOrder order,
  bool allocationConfirmed,
) {
  return wholesaleOrderCanAssign(order) &&
      allOrderLinesFullyAssigned(order) &&
      allocationConfirmed &&
      orderAllowsAssignmentChange(order);
}

List<StagedStoreAssignment> addStagedAssignment(
  List<StagedStoreAssignment> staged,
  StagedStoreAssignment assignment,
) {
  final next = <StagedStoreAssignment>[];
  var merged = false;
  for (final a in staged) {
    if (a.wholesaleOrderItemId == assignment.wholesaleOrderItemId && a.storeId == assignment.storeId) {
      next.add(StagedStoreAssignment(
        wholesaleOrderItemId: a.wholesaleOrderItemId,
        storeId: a.storeId,
        quantity: a.quantity + assignment.quantity,
      ));
      merged = true;
    } else {
      next.add(a);
    }
  }
  if (!merged) next.add(assignment);
  return next;
}

String stagedAssignmentSummary(
  List<StagedStoreAssignment> staged,
  int itemId,
  Map<int, String> storeNameById,
) {
  final parts = staged
      .where((a) => a.wholesaleOrderItemId == itemId)
      .map((a) {
        final name = storeNameById[a.storeId] ?? 'Store #${a.storeId}';
        return '$name (${formatAssignmentQty(a.quantity)})';
      })
      .toList();
  return parts.isEmpty ? '—' : parts.join(', ');
}

String formatAssignmentQty(double qty) {
  if (qty == qty.roundToDouble()) return qty.toInt().toString();
  return qty.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
}

double stockLevelValue(StockRow? stock) {
  if (stock == null) return 0;
  return stock.quantity;
}

bool storeCanFulfillItemQty(
  int storeId,
  WholesaleOrderItem item,
  double needQty,
  Map<String, StockRow> stockByStoreProduct,
) {
  if (needQty <= 0.0001) return true;
  final stock = stockByStoreProduct['$storeId-${item.productId}'];
  if (stock == null) return false;
  return stockLevelValue(stock) + 0.0001 >= needQty;
}

StoreStockHighlight storeStockHighlightLevel(
  int storeId,
  WholesaleOrder order,
  double Function(WholesaleOrderItem item) pendingQtyForItem,
  Map<String, StockRow> stockByStoreProduct,
) {
  var anyPending = false;
  var allFulfill = true;
  var anyFulfill = false;
  for (final it in order.items) {
    final pending = pendingQtyForItem(it);
    if (pending <= 0.0001) continue;
    anyPending = true;
    final ok = storeCanFulfillItemQty(storeId, it, pending, stockByStoreProduct);
    if (ok) anyFulfill = true;
    if (!ok) allFulfill = false;
  }
  if (!anyPending) return StoreStockHighlight.none;
  if (allFulfill) return StoreStockHighlight.full;
  if (anyFulfill) return StoreStockHighlight.partial;
  return StoreStockHighlight.none;
}

AssignStoreStockHint formatAssignStoreStockHint(double? available, double needQty) {
  if (available == null || available.isNaN) {
    return const AssignStoreStockHint(text: '—', sufficient: false);
  }
  final sufficient = available + 0.0001 >= needQty;
  if (needQty <= 0.0001) {
    return AssignStoreStockHint(text: formatAssignmentQty(available), sufficient: true);
  }
  return AssignStoreStockHint(
    text: '${formatAssignmentQty(available)} / ${formatAssignmentQty(needQty)}',
    sufficient: sufficient,
  );
}
