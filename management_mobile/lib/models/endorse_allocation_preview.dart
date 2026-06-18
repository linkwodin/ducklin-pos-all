class EndorseAllocationAssignmentPreview {
  final int wholesaleOrderItemId;
  final int storeId;
  final double quantity;
  final String? storeName;
  final double? stockAvailable;

  const EndorseAllocationAssignmentPreview({
    required this.wholesaleOrderItemId,
    required this.storeId,
    required this.quantity,
    this.storeName,
    this.stockAvailable,
  });

  factory EndorseAllocationAssignmentPreview.fromJson(Map<String, dynamic> json) =>
      EndorseAllocationAssignmentPreview(
        wholesaleOrderItemId: json['wholesale_order_item_id'] as int,
        storeId: json['store_id'] as int,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        storeName: json['store_name']?.toString(),
        stockAvailable: (json['stock_available'] as num?)?.toDouble(),
      );
}

class EndorseAllocationPreview {
  final String outcome;
  final int? primaryStoreId;
  final String? primaryStoreName;
  final List<int> storeIds;
  final List<EndorseAllocationAssignmentPreview> assignments;

  const EndorseAllocationPreview({
    required this.outcome,
    this.primaryStoreId,
    this.primaryStoreName,
    this.storeIds = const [],
    this.assignments = const [],
  });

  factory EndorseAllocationPreview.fromJson(Map<String, dynamic> json) {
    final storeIdsRaw = json['store_ids'] as List<dynamic>? ?? [];
    final assignmentsRaw = json['assignments'] as List<dynamic>? ?? [];
    return EndorseAllocationPreview(
      outcome: '${json['outcome'] ?? ''}',
      primaryStoreId: json['primary_store_id'] as int?,
      primaryStoreName: json['primary_store_name']?.toString(),
      storeIds: storeIdsRaw.map((e) => e as int).toList(),
      assignments: assignmentsRaw
          .map((e) => EndorseAllocationAssignmentPreview.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
