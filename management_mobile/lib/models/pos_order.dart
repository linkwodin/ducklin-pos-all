import 'product.dart';
import 'store.dart';
import 'user.dart';

class PosOrderItem {
  final int id;
  final int productId;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final Product? product;

  const PosOrderItem({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.product,
  });

  factory PosOrderItem.fromJson(Map<String, dynamic> json) => PosOrderItem(
        id: json['id'] as int,
        productId: json['product_id'] as int,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
        lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0,
        product: json['product'] != null
            ? Product.fromJson(json['product'] as Map<String, dynamic>)
            : null,
      );
}

class PosOrder {
  final int id;
  final String orderNumber;
  final int storeId;
  final String status;
  final double subtotal;
  final double discountAmount;
  final double totalAmount;
  final String? createdAt;
  final String? paidAt;
  final String? completedAt;
  final Store? store;
  final AppUser? user;
  final List<PosOrderItem> items;

  const PosOrder({
    required this.id,
    required this.orderNumber,
    required this.storeId,
    required this.status,
    required this.subtotal,
    required this.discountAmount,
    required this.totalAmount,
    this.createdAt,
    this.paidAt,
    this.completedAt,
    this.store,
    this.user,
    this.items = const [],
  });

  factory PosOrder.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List<dynamic>? ?? [];
    return PosOrder(
      id: json['id'] as int,
      orderNumber: '${json['order_number'] ?? ''}',
      storeId: json['store_id'] as int,
      status: '${json['status'] ?? ''}',
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at']?.toString(),
      paidAt: json['paid_at']?.toString(),
      completedAt: json['completed_at']?.toString(),
      store: json['store'] != null
          ? Store.fromJson(json['store'] as Map<String, dynamic>)
          : null,
      user: json['user'] != null
          ? AppUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      items: itemsRaw
          .map((e) => PosOrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
