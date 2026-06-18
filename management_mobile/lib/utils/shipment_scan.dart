import '../models/shipment.dart';

String _normalize(String raw) => raw.trim().toLowerCase();

List<String> deliveryNoteScanKeys(Shipment shipment) {
  final order = shipment.wholesaleOrder;
  final orderNumber = order?.orderNumber;
  final keys = <String?>[
    orderNumber,
    order?.poNumber,
    order?.refNo,
    orderNumber?.replaceFirst(RegExp(r'^WO-', caseSensitive: false), ''),
    '${shipment.id}',
    '${shipment.wholesaleOrderId}',
    'shipment:${shipment.id}',
    'shipment-${shipment.id}',
    shipment.trackingNumber,
  ];
  return keys
      .whereType<String>()
      .map((k) => k.trim())
      .where((k) => k.isNotEmpty)
      .map(_normalize)
      .toSet()
      .toList();
}

bool shipmentMatchesDeliveryNoteScan(Shipment shipment, String raw) {
  final q = _normalize(raw);
  if (q.isEmpty) return false;
  final keys = deliveryNoteScanKeys(shipment);
  return keys.any((k) => k == q || k.contains(q) || q.contains(k));
}

bool shipmentMatchesCouriers(Shipment shipment, List<String> couriers) {
  if (couriers.isEmpty) return true;
  final assigned = (shipment.courier ?? '').trim().toLowerCase();
  if (assigned.isEmpty) return true;
  return couriers.any((c) => c.trim().toLowerCase() == assigned);
}

const defaultShipmentCouriers = ['In-house', 'DPD', 'Royal Mail'];

List<String> courierOptionsFromSettings(String? raw) {
  final parsed = (raw ?? '')
      .split(RegExp(r'[\n,;]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return parsed.isNotEmpty ? parsed : defaultShipmentCouriers;
}
