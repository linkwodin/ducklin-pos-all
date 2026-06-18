class StockProduct {
  final int id;
  final String name;
  final String? nameChinese;

  const StockProduct({
    required this.id,
    required this.name,
    this.nameChinese,
  });

  factory StockProduct.fromJson(Map<String, dynamic> json) => StockProduct(
        id: json['id'] as int,
        name: '${json['name'] ?? ''}',
        nameChinese: json['name_chinese']?.toString(),
      );

  String displayName() {
    if (nameChinese != null && nameChinese!.isNotEmpty) {
      return name.isNotEmpty ? '$name ($nameChinese)' : nameChinese!;
    }
    return name;
  }
}

class StockRow {
  final int productId;
  final int storeId;
  final String? storeName;
  final double quantity;
  final StockProduct? product;

  const StockRow({
    required this.productId,
    required this.storeId,
    this.storeName,
    required this.quantity,
    this.product,
  });

  factory StockRow.fromJson(Map<String, dynamic> json) {
    final store = json['store'] as Map<String, dynamic>?;
    return StockRow(
      productId: json['product_id'] as int,
      storeId: json['store_id'] as int,
      storeName: store?['name']?.toString(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      product: json['product'] != null
          ? StockProduct.fromJson(json['product'] as Map<String, dynamic>)
          : null,
    );
  }
}
