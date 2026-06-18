class Product {
  final int id;
  final String name;
  final String? nameChinese;
  final String? barcode;
  final String? sku;
  final String? category;
  final String unitType;
  final bool isActive;
  final int? wholesaleUnitsPerBox;
  final ProductCost? currentCost;
  final List<ProductSectorDiscount> discounts;

  const Product({
    required this.id,
    required this.name,
    this.nameChinese,
    this.barcode,
    this.sku,
    this.category,
    this.unitType = 'quantity',
    this.isActive = true,
    this.wholesaleUnitsPerBox,
    this.currentCost,
    this.discounts = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final discountsRaw = json['discounts'] as List<dynamic>? ?? [];
    return Product(
      id: json['id'] as int,
      name: '${json['name'] ?? ''}',
      nameChinese: json['name_chinese']?.toString(),
      barcode: json['barcode']?.toString(),
      sku: json['sku']?.toString(),
      category: json['category']?.toString(),
      unitType: '${json['unit_type'] ?? 'quantity'}',
      isActive: json['is_active'] != false,
      wholesaleUnitsPerBox: json['wholesale_units_per_box'] as int?,
      currentCost: json['current_cost'] != null
          ? ProductCost.fromJson(json['current_cost'] as Map<String, dynamic>)
          : null,
      discounts: discountsRaw
          .map((e) => ProductSectorDiscount.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  String displayName() {
    if (nameChinese != null && nameChinese!.isNotEmpty) {
      return name.isNotEmpty ? '$name ($nameChinese)' : nameChinese!;
    }
    return name;
  }

  double unitPriceForSector(int? sectorId) {
    final c = currentCost;
    if (c == null) return 0;
    final directRetail = c.directRetailOnlineStorePriceGbp ?? 0;
    final wholesale = c.wholesaleCostGbp;
    var price = directRetail > 0 ? directRetail : wholesale;
    if (sectorId != null) {
      for (final disc in discounts) {
        if (disc.sectorId == sectorId) {
          if (disc.sectorPriceGbp > 0) return disc.sectorPriceGbp;
          if (disc.discountPercent > 0 && price > 0) {
            return (price * (1 - disc.discountPercent / 100) * 100).round() / 100;
          }
        }
      }
    }
    return price;
  }
}

class ProductCost {
  final double wholesaleCostGbp;
  final double? directRetailOnlineStorePriceGbp;

  const ProductCost({
    required this.wholesaleCostGbp,
    this.directRetailOnlineStorePriceGbp,
  });

  factory ProductCost.fromJson(Map<String, dynamic> json) => ProductCost(
        wholesaleCostGbp: (json['wholesale_cost_gbp'] as num?)?.toDouble() ?? 0,
        directRetailOnlineStorePriceGbp:
            (json['direct_retail_online_store_price_gbp'] as num?)?.toDouble(),
      );
}

class ProductSectorDiscount {
  final int sectorId;
  final double discountPercent;
  final double sectorPriceGbp;

  const ProductSectorDiscount({
    required this.sectorId,
    required this.discountPercent,
    required this.sectorPriceGbp,
  });

  factory ProductSectorDiscount.fromJson(Map<String, dynamic> json) =>
      ProductSectorDiscount(
        sectorId: json['sector_id'] as int,
        discountPercent: (json['discount_percent'] as num?)?.toDouble() ?? 0,
        sectorPriceGbp: (json['sector_price_gbp'] as num?)?.toDouble() ?? 0,
      );
}
