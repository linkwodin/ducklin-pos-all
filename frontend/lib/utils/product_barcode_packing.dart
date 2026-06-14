import 'product_barcode.dart';
import 'shipment_packing.dart';

String normalizeBarcodeScanInput(String raw) => raw.trim().replaceAll(RegExp(r'[\r\n\t]'), '');

List<String> _storedBarcodesForPacking(Map<String, dynamic> product) {
  return [
    product['barcode']?.toString().trim(),
    product['sku']?.toString().trim(),
  ].whereType<String>().where((v) => v.isNotEmpty).toList();
}

String? _pickNonEmpty(String? a, String? b) {
  final ta = a?.trim();
  if (ta != null && ta.isNotEmpty) return ta;
  final tb = b?.trim();
  if (tb != null && tb.isNotEmpty) return tb;
  return null;
}

Map<String, dynamic> _mergeLineProduct(
  ShipmentPackingLine line,
  Map<String, dynamic>? catalog,
) {
  if (catalog == null) return line.product;
  final lineProduct = line.product;
  return {
    ...catalog,
    ...lineProduct,
    if (_pickNonEmpty(catalog['barcode']?.toString(), lineProduct['barcode']?.toString()) != null)
      'barcode': _pickNonEmpty(catalog['barcode']?.toString(), lineProduct['barcode']?.toString()),
    if (_pickNonEmpty(catalog['sku']?.toString(), lineProduct['sku']?.toString()) != null)
      'sku': _pickNonEmpty(catalog['sku']?.toString(), lineProduct['sku']?.toString()),
    if (_pickNonEmpty(catalog['weight_barcode']?.toString(), lineProduct['weight_barcode']?.toString()) != null)
      'weight_barcode':
          _pickNonEmpty(catalog['weight_barcode']?.toString(), lineProduct['weight_barcode']?.toString()),
    if (_pickNonEmpty(catalog['weight_barcode_prefix']?.toString(), lineProduct['weight_barcode_prefix']?.toString()) !=
        null)
      'weight_barcode_prefix': _pickNonEmpty(
        catalog['weight_barcode_prefix']?.toString(),
        lineProduct['weight_barcode_prefix']?.toString(),
      ),
    'product_line_id': lineProduct['product_line_id'] ?? catalog['product_line_id'],
    'unit_type': lineProduct['unit_type'] ?? catalog['unit_type'],
    'sell_by_qty': lineProduct['sell_by_qty'] ?? catalog['sell_by_qty'],
    'sell_by_weight': lineProduct['sell_by_weight'] ?? catalog['sell_by_weight'],
  };
}

Map<String, dynamic>? _mapCatalogBarcodeToPackingLine(
  String code,
  List<ShipmentPackingLine> packingLines,
  List<Map<String, dynamic>> lineProducts,
  List<Map<String, dynamic>> catalog,
) {
  final catalogHits = catalog.where((product) {
    return _storedBarcodesForPacking(product).any((stored) => barcodesMatchForLookup(stored, code));
  }).toList();
  if (catalogHits.isEmpty) return null;

  for (final hit in catalogHits) {
    final hitId = (hit['id'] as num?)?.toInt();
    final directIdx = packingLines.indexWhere((line) => line.productId == hitId);
    if (directIdx >= 0) {
      return {...lineProducts[directIdx], '_scan_mode': 'qty'};
    }
  }
  return null;
}

/// Resolve a scan only to products on this shipment (exact barcode match only).
Map<String, dynamic>? resolveProductScanForPacking(
  String barcode,
  List<ShipmentPackingLine> packingLines,
  List<Map<String, dynamic>> catalog,
) {
  if (packingLines.isEmpty) return null;
  final code = normalizeBarcodeScanInput(barcode);
  if (code.isEmpty) return null;

  final catalogById = <int, Map<String, dynamic>>{};
  for (final p in catalog) {
    final id = (p['id'] as num?)?.toInt();
    if (id != null) catalogById[id] = p;
  }
  final lineProducts = packingLines
      .map((line) => _mergeLineProduct(line, catalogById[line.productId]))
      .toList();

  for (var i = 0; i < packingLines.length; i++) {
    final product = lineProducts[i];
    for (final stored in _storedBarcodesForPacking(product)) {
      if (barcodesMatchForLookup(stored, code)) {
        return {...product, '_scan_mode': 'qty'};
      }
    }
  }

  return _mapCatalogBarcodeToPackingLine(code, packingLines, lineProducts, catalog);
}

bool shouldAutoSubmitBarcodeLength(String trimmed) {
  const completeLengths = {8, 12, 13, 14};
  return completeLengths.contains(trimmed.length) && RegExp(r'^\d+$').hasMatch(trimmed);
}
