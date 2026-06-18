/// Product variant helpers — each SKU is either quantity or weight (unit_type).

bool productIsWeight(Map<String, dynamic> product) {
  final unitType = (product['unit_type'] ?? '').toString().toLowerCase();
  if (unitType == 'weight') return true;
  if (unitType == 'quantity') return false;
  final sellByWeight = product['sell_by_weight'];
  return sellByWeight == true || sellByWeight == 1;
}

bool productIsQuantity(Map<String, dynamic> product) {
  return !productIsWeight(product);
}

bool productSellByQty(Map<String, dynamic> product) => productIsQuantity(product);

bool productSellByWeight(Map<String, dynamic> product) => productIsWeight(product);

bool productSupportsDualInventory(Map<String, dynamic> product) => false;

bool productIsLegacyWeightOnly(Map<String, dynamic> product) => productIsWeight(product);

bool productUsesWeightPricing(Map<String, dynamic> product) => productIsWeight(product);

bool stockTracksPrepacked(Map<String, dynamic>? stock, Map<String, dynamic> product) {
  return productIsQuantity(product);
}

bool stockTracksWeight(Map<String, dynamic>? stock, Map<String, dynamic> product) {
  return productIsWeight(product);
}

double systemPrepackedQuantity(Map<String, dynamic>? stock, Map<String, dynamic> product) {
  if (!productIsQuantity(product)) return 0;
  return (stock?['quantity'] as num?)?.toDouble() ?? 0;
}

double systemWeightQuantityG(Map<String, dynamic>? stock, Map<String, dynamic> product) {
  if (!productIsWeight(product)) return 0;
  return (stock?['weight_quantity_g'] as num?)?.toDouble() ??
      (stock?['quantity'] as num?)?.toDouble() ??
      0;
}

String? productScanMode(Map<String, dynamic> product) {
  return product['_scan_mode']?.toString();
}

bool scanIsWeightMode(Map<String, dynamic> product) {
  return productScanMode(product) == 'weight';
}

bool scanIsQtyMode(Map<String, dynamic> product) {
  return productScanMode(product) == 'qty';
}

bool productCanSellInMode(Map<String, dynamic> product, {required bool asWeight}) {
  return asWeight ? productIsWeight(product) : productIsQuantity(product);
}

String saleLineUnitType({required bool asWeight}) {
  return asWeight ? 'weight' : 'quantity';
}

bool cartItemIsWeightLine(Map<String, dynamic> item) {
  return (item['unit_type'] ?? 'quantity').toString() == 'weight';
}

String? productWeightBarcode(Map<String, dynamic> product) {
  if (!productIsWeight(product)) return null;
  final wb = product['weight_barcode']?.toString().trim();
  if (wb != null && wb.isNotEmpty) return wb;
  return product['barcode']?.toString().trim();
}

String? productQtyBarcode(Map<String, dynamic> product) {
  if (!productIsQuantity(product)) return null;
  return product['barcode']?.toString().trim();
}

String productVariantLabel(Map<String, dynamic> product) {
  return (product['variant_label']?.toString() ?? '').trim();
}

bool productHasDistinctSaleBarcodes(Map<String, dynamic> product) => false;

bool productNeedsSaleModePicker(Map<String, dynamic> product) => false;

class PosProductListEntry {
  const PosProductListEntry({
    required this.product,
    this.listSellAsWeight,
  });

  final Map<String, dynamic> product;
  final bool? listSellAsWeight;

  String listKey(int index) {
    final id = product['id'] ?? index;
    return 'product_$id';
  }
}

List<PosProductListEntry> expandProductsForPosList(List<Map<String, dynamic>> products) {
  return products
      .map((product) => PosProductListEntry(product: product))
      .toList();
}
