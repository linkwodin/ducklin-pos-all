import '../models/product.dart';
import 'shipment_packing.dart';

String normalizeBarcodeScanInput(String raw) =>
    raw.trim().replaceAll(RegExp(r'[\r\n\t]'), '');

String barcodeDigitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

bool barcodesMatchForLookup(String stored, String scanned) {
  final a = barcodeDigitsOnly(stored);
  final b = barcodeDigitsOnly(scanned);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (a.length == 13 && b.length == 13 && a.substring(0, 12) == b.substring(0, 12)) {
    return true;
  }
  if (a.length == 12 && b.length == 13 && a == b.substring(0, 12)) return true;
  if (b.length == 12 && a.length == 13 && b == a.substring(0, 12)) return true;
  return false;
}

List<String> storedBarcodesForPacking(Product product) {
  return [product.barcode, product.sku]
      .whereType<String>()
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();
}

Product? resolveProductScanForPacking(
  String barcode,
  List<ShipmentPackingLine> packingLines,
  List<Product> catalog,
) {
  final code = normalizeBarcodeScanInput(barcode);
  if (code.isEmpty || packingLines.isEmpty) return null;

  final catalogById = {for (final p in catalog) p.id: p};
  final lineProducts = packingLines.map((line) {
    final c = catalogById[line.productId];
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

  for (var i = 0; i < packingLines.length; i++) {
    final product = lineProducts[i];
    for (final stored in storedBarcodesForPacking(product)) {
      if (barcodesMatchForLookup(stored, code)) return product;
    }
  }

  for (final hit in catalog) {
    final matches = storedBarcodesForPacking(hit)
        .any((stored) => barcodesMatchForLookup(stored, code));
    if (!matches) continue;
    if (packingLines.any((line) => line.productId == hit.id)) return hit;
  }
  return null;
}
