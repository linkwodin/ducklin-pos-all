import 'product.dart';
import 'store.dart';

class ShipmentOrderBrief {
  final int id;
  final String orderNumber;
  final String? refNo;
  final String? poNumber;
  final String? orderDate;
  final String? clientName;

  const ShipmentOrderBrief({
    required this.id,
    required this.orderNumber,
    this.refNo,
    this.poNumber,
    this.orderDate,
    this.clientName,
  });

  factory ShipmentOrderBrief.fromJson(Map<String, dynamic> json) {
    final client = json['wholesale_client'] as Map<String, dynamic>?;
    return ShipmentOrderBrief(
      id: json['id'] as int,
      orderNumber: '${json['order_number'] ?? ''}',
      refNo: json['ref_no']?.toString(),
      poNumber: json['po_number']?.toString(),
      orderDate: json['order_date']?.toString(),
      clientName: client?['name']?.toString(),
    );
  }
}

class ShipmentOrderItem {
  final int id;
  final int productId;
  final double quantity;
  final int? assignedStoreId;
  final Product? product;

  const ShipmentOrderItem({
    required this.id,
    required this.productId,
    required this.quantity,
    this.assignedStoreId,
    this.product,
  });

  factory ShipmentOrderItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    return ShipmentOrderItem(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      assignedStoreId: json['assigned_store_id'] as int?,
      product: product != null ? Product.fromJson(product) : null,
    );
  }
}

class ShipmentItem {
  final int id;
  final int wholesaleOrderItemId;
  final double? quantity;
  final int? caseQty;
  final ShipmentOrderItem? wholesaleOrderItem;

  const ShipmentItem({
    required this.id,
    required this.wholesaleOrderItemId,
    this.quantity,
    this.caseQty,
    this.wholesaleOrderItem,
  });

  factory ShipmentItem.fromJson(Map<String, dynamic> json) {
    final woItem = json['wholesale_order_item'] as Map<String, dynamic>?;
    return ShipmentItem(
      id: json['id'] as int,
      wholesaleOrderItemId: json['wholesale_order_item_id'] as int,
      quantity: (json['quantity'] as num?)?.toDouble(),
      caseQty: json['case_qty'] as int?,
      wholesaleOrderItem:
          woItem != null ? ShipmentOrderItem.fromJson(woItem) : null,
    );
  }

  double effectiveQty() {
    if (quantity != null && quantity! > 0) return quantity!;
    return wholesaleOrderItem?.quantity ?? 0;
  }
}

class Shipment {
  final int id;
  final int wholesaleOrderId;
  final int storeId;
  final String status;
  final String? courier;
  final String? trackingNumber;
  final String? deliveryDate;
  final String? createdAt;
  final String? updatedAt;
  final String? deliveryNotePdfUrl;
  final String? signedDeliveryNotePdfUrl;
  final Store? store;
  final ShipmentOrderBrief? wholesaleOrder;
  final List<ShipmentItem> items;

  const Shipment({
    required this.id,
    required this.wholesaleOrderId,
    required this.storeId,
    required this.status,
    this.courier,
    this.trackingNumber,
    this.deliveryDate,
    this.createdAt,
    this.updatedAt,
    this.deliveryNotePdfUrl,
    this.signedDeliveryNotePdfUrl,
    this.store,
    this.wholesaleOrder,
    this.items = const [],
  });

  String? get orderNumber => wholesaleOrder?.orderNumber;

  factory Shipment.fromJson(Map<String, dynamic> json) {
    final order = json['wholesale_order'] as Map<String, dynamic>?;
    final itemsRaw = json['items'] as List<dynamic>? ?? [];
    return Shipment(
      id: json['id'] as int,
      wholesaleOrderId: json['wholesale_order_id'] as int,
      storeId: json['store_id'] as int,
      status: '${json['status'] ?? ''}',
      courier: json['courier']?.toString(),
      trackingNumber: json['tracking_number']?.toString(),
      deliveryDate: json['delivery_date']?.toString(),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      deliveryNotePdfUrl: json['delivery_note_pdf_url']?.toString(),
      signedDeliveryNotePdfUrl: json['signed_delivery_note_pdf_url']?.toString(),
      store: json['store'] != null
          ? Store.fromJson(json['store'] as Map<String, dynamic>)
          : null,
      wholesaleOrder: order != null ? ShipmentOrderBrief.fromJson(order) : null,
      items: itemsRaw.map((e) => ShipmentItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
