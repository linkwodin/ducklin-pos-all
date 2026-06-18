import '../models/product.dart';
import '../models/shipment.dart';
import '../models/stock.dart';

class ShipmentPackingLine {
  ShipmentPackingLine({
    required this.productId,
    required this.expectedQty,
    required this.expectedBoxes,
    required this.product,
  });

  final int productId;
  final double expectedQty;
  final double expectedBoxes;
  final Product product;
}

bool shipmentNeedsPacking(String status) =>
    status == 'assigned' || status == 'packing';

bool shipmentShowsCourierPickup(String status) =>
    status == 'packed' || status == 'shipped' || status == 'completed';

bool shipmentHasDeliveryProof(Shipment shipment) =>
    (shipment.signedDeliveryNotePdfUrl ?? '').trim().isNotEmpty;

bool shipmentCanEditCourierDetails(Shipment shipment) => !shipmentHasDeliveryProof(shipment);

bool shipmentCanUploadDeliveryProof(Shipment shipment) {
  if (shipment.status == 'completed') return false;
  if ((shipment.deliveryNotePdfUrl ?? '').trim().isEmpty) return false;
  if (shipmentHasDeliveryProof(shipment)) return false;
  return shipment.status == 'packed' || shipment.status == 'shipped';
}

bool shipmentShowsDeliveryHandoff(Shipment shipment) {
  if (shipment.status == 'completed') return false;
  return shipment.status == 'packed' || shipment.status == 'shipped';
}

enum ShipmentWorkflowStepState { done, active, locked }

bool shipmentPickPackComplete(Shipment shipment) => !shipmentNeedsPacking(shipment.status);

bool shipmentCourierDetailsComplete(Shipment shipment) =>
    shipmentPickPackComplete(shipment) && (shipment.courier ?? '').trim().isNotEmpty;

bool shipmentDeliveryHandoffComplete(Shipment shipment) =>
    shipmentHasDeliveryProof(shipment) || shipment.status == 'completed';

ShipmentWorkflowStepState shipmentPickPackStepState(Shipment shipment) {
  if (shipmentPickPackComplete(shipment)) return ShipmentWorkflowStepState.done;
  return ShipmentWorkflowStepState.active;
}

ShipmentWorkflowStepState shipmentCourierDetailsStepState(Shipment shipment) {
  if (!shipmentPickPackComplete(shipment)) return ShipmentWorkflowStepState.locked;
  if (shipmentCourierDetailsComplete(shipment)) return ShipmentWorkflowStepState.done;
  return ShipmentWorkflowStepState.active;
}

ShipmentWorkflowStepState shipmentDeliveryHandoffStepState(Shipment shipment) {
  if (!shipmentPickPackComplete(shipment) || !shipmentCourierDetailsComplete(shipment)) {
    return ShipmentWorkflowStepState.locked;
  }
  if (shipmentDeliveryHandoffComplete(shipment)) return ShipmentWorkflowStepState.done;
  return ShipmentWorkflowStepState.active;
}

int shipmentExpectedBoxes(ShipmentItem item) {
  if (item.caseQty != null && item.caseQty! > 0) return item.caseQty!;
  final qty = item.effectiveQty();
  final upb = item.wholesaleOrderItem?.product?.wholesaleUnitsPerBox ?? 0;
  if (upb > 0 && qty > 0) return (qty / upb).ceil();
  return qty.round();
}

int shipmentTotalBoxes(Shipment shipment) {
  return shipment.items.fold(0, (sum, item) => sum + shipmentExpectedBoxes(item));
}

List<ShipmentItem> effectiveShipmentItemsForPacking(Shipment shipment) {
  final items = shipment.items;
  if (items.any((si) => si.wholesaleOrderItem?.product != null)) return items;
  return items;
}

List<ShipmentPackingLine> buildShipmentPackingLines(Shipment shipment) {
  final byProduct = <int, ShipmentPackingLine>{};
  for (final si in effectiveShipmentItemsForPacking(shipment)) {
    final product = si.wholesaleOrderItem?.product;
    if (product == null) continue;
    final expectedQty = si.effectiveQty();
    final expectedBoxes = shipmentExpectedBoxes(si).toDouble();
    final existing = byProduct[product.id];
    if (existing != null) {
      byProduct[product.id] = ShipmentPackingLine(
        productId: product.id,
        expectedQty: existing.expectedQty + expectedQty,
        expectedBoxes: existing.expectedBoxes + expectedBoxes,
        product: product,
      );
    } else {
      byProduct[product.id] = ShipmentPackingLine(
        productId: product.id,
        expectedQty: expectedQty,
        expectedBoxes: expectedBoxes,
        product: product,
      );
    }
  }
  return byProduct.values.toList();
}

List<Product> packingScanCatalog(List<Product> catalog, Shipment shipment) {
  final byId = {for (final p in catalog) p.id: p};
  return buildShipmentPackingLines(shipment).map((line) {
    final c = byId[line.productId];
    if (c == null) return line.product;
    return Product(
      id: line.product.id,
      name: line.product.name,
      nameChinese: line.product.nameChinese ?? c.nameChinese,
      barcode: c.barcode ?? line.product.barcode,
      sku: c.sku ?? line.product.sku,
      unitType: line.product.unitType,
      wholesaleUnitsPerBox: line.product.wholesaleUnitsPerBox ?? c.wholesaleUnitsPerBox,
    );
  }).toList();
}

double availableStockForProduct(StockRow? stock) => stock?.quantity ?? 0;

String formatPackingQty(double qty) =>
    qty % 1 == 0 ? qty.round().toString() : qty.toStringAsFixed(2);

Map<int, String> initialCaseQtyFromShipment(Shipment shipment) {
  final out = <int, String>{};
  for (final si in effectiveShipmentItemsForPacking(shipment)) {
    final expected = shipmentExpectedBoxes(si);
    final saved = si.caseQty != null && si.caseQty! > 0 ? si.caseQty! : expected;
    out[si.wholesaleOrderItemId] = '$saved';
  }
  return out;
}

List<Map<String, dynamic>> caseQtyPayload(
  Shipment shipment,
  Map<int, String> caseQtyByOrderItemId,
) {
  return effectiveShipmentItemsForPacking(shipment).map((si) {
    final raw = caseQtyByOrderItemId[si.wholesaleOrderItemId] ?? '0';
    final parsed = double.tryParse(raw) ?? 0;
    return {
      'wholesale_order_item_id': si.wholesaleOrderItemId,
      'case_qty': parsed < 0 ? 0 : parsed.round(),
    };
  }).toList();
}
