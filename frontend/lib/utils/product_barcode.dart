import 'product_inventory.dart';
import 'weight_barcode.dart';

String normalizeBarcodeScanInput(String raw) =>
    raw.trim().replaceAll(RegExp(r'[\r\n\t]'), '');

String barcodeDigitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

/// True when [stored] and [scanned] are the same barcode, tolerant of:
/// - non-digit separators in stored values
/// - EAN-13 check-digit differences (first 12 digits)
/// - UPC-A (12) vs EAN-13 (leading 0 + 12)
bool barcodesMatchForLookup(String stored, String scanned) {
  final a = barcodeDigitsOnly(stored);
  final b = barcodeDigitsOnly(scanned);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (a.length == 13 && b.length == 13 && a.substring(0, 12) == b.substring(0, 12)) {
    return true;
  }
  if (a.length == 13 && b.length == 12 && a.startsWith('0') && a.substring(1) == b) {
    return true;
  }
  if (b.length == 13 && a.length == 12 && b.startsWith('0') && b.substring(1) == a) {
    return true;
  }
  return false;
}

String? shortScanDigits(String code) {
  final digits = barcodeDigitsOnly(code);
  if (digits.length >= 6 && digits.length <= 8) return digits;
  return null;
}

bool suffixDigitsMatch(String storedFull, String shortDigits) {
  final full = barcodeDigitsOnly(storedFull);
  if (full.isEmpty || shortDigits.isEmpty) return false;
  return full == shortDigits || full.endsWith(shortDigits);
}

bool oneDigitApart(String a, String b) {
  if (a.length != b.length || a.length < 6) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      diff++;
      if (diff > 1) return false;
    }
  }
  return diff == 1;
}

List<String> _storedBarcodesForWeight(Map<String, dynamic> product) {
  return [
    product['weight_barcode']?.toString().trim(),
    product['weight_barcode_prefix']?.toString().trim(),
  ].whereType<String>().where((v) => v.isNotEmpty).toList();
}

int? _productLineId(Map<String, dynamic> product) {
  final id = product['product_line_id'];
  if (id == null) return null;
  final n = id is int ? id : (id as num).toInt();
  return n > 0 ? n : null;
}

Map<String, dynamic>? _weightVariantOnLine(
  Iterable<Map<String, dynamic>> products,
  int? lineId,
) {
  if (lineId == null) return null;
  for (final product in products) {
    if (_productLineId(product) == lineId && productSellByWeight(product)) {
      return product;
    }
  }
  return null;
}

Map<String, dynamic>? _weightSaleProduct(
  Map<String, dynamic> matched,
  Iterable<Map<String, dynamic>> products,
) {
  if (productSellByWeight(matched)) return matched;
  return _weightVariantOnLine(products, _productLineId(matched));
}

bool _codeMatchesAnyWeightBarcode(String code, Iterable<Map<String, dynamic>> products) {
  for (final product in products) {
    for (final stored in _storedBarcodesForWeight(product)) {
      if (barcodesMatchForLookup(stored, code)) return true;
    }
  }
  return false;
}

Map<String, dynamic>? _qtyFullBarcodeMatch(
  String digits,
  Iterable<Map<String, dynamic>> products,
) {
  for (final product in products) {
    if (!productSellByQty(product)) continue;
    final barcode = barcodeDigitsOnly(product['barcode']?.toString() ?? '');
    // Qty scans use the barcode field only (not SKU — avoids 5070002375401-WT collisions).
    if (barcode.length < 8) continue;
    if (barcodesMatchForLookup(barcode, digits)) {
      return {...product, '_scan_mode': 'qty'};
    }
  }
  return null;
}

Map<String, dynamic>? _weightBarcodeMatch(
  String code,
  Map<String, dynamic> product,
  Iterable<Map<String, dynamic>> products,
) {
  for (final stored in _storedBarcodesForWeight(product)) {
    if (!barcodesMatchForLookup(stored, code)) continue;
    final target = _weightSaleProduct(product, products);
    if (target == null) continue;
    return {...target, '_scan_mode': 'weight'};
  }
  if (!productSellByWeight(product)) return null;
  final barcode = product['barcode']?.toString().trim();
  if (barcode != null &&
      barcode.isNotEmpty &&
      _storedBarcodesForWeight(product).isEmpty &&
      barcodesMatchForLookup(barcode, code)) {
    return {...product, '_scan_mode': 'weight'};
  }
  return null;
}

Map<String, dynamic>? _weightPrefixMatch(
  String normalizedPrefix,
  Map<String, dynamic> product,
  Iterable<Map<String, dynamic>> products,
) {
  final productPrefix = WeightBarcode.effectivePrefixForProduct(product);
  if (productPrefix == null || productPrefix != normalizedPrefix) return null;
  final target = _weightSaleProduct(product, products);
  if (target == null) return null;
  return {...target, '_scan_mode': 'weight'};
}

Map<String, dynamic>? _shortQtySuffixMatch(
  String shortDigits,
  Iterable<Map<String, dynamic>> products,
) {
  if (_codeMatchesAnyWeightBarcode(shortDigits, products)) return null;

  Map<String, dynamic>? hit;
  for (final product in products) {
    if (!productSellByQty(product)) continue;
    final barcode = product['barcode']?.toString();
    if (barcode == null || barcode.isEmpty) continue;
    if (!suffixDigitsMatch(barcode, shortDigits)) continue;
    if (hit != null) return null;
    hit = product;
  }
  if (hit == null) return null;
  return {...hit, '_scan_mode': 'qty'};
}

Map<String, dynamic>? _fuzzyShortWeightMatch(
  String shortDigits,
  Iterable<Map<String, dynamic>> products,
) {
  if (shortDigits.length < 6) return null;
  Map<String, dynamic>? hit;
  for (final product in products) {
    var productMatched = false;
    for (final stored in _storedBarcodesForWeight(product)) {
      final digits = barcodeDigitsOnly(stored);
      if (digits.isEmpty || digits.length != shortDigits.length) continue;
      if (!oneDigitApart(digits, shortDigits)) continue;
      productMatched = true;
      break;
    }
    if (!productMatched) continue;
    final target = _weightSaleProduct(product, products);
    if (target == null) continue;
    if (hit != null) return null;
    hit = target;
  }
  if (hit == null) return null;
  return {...hit, '_scan_mode': 'weight'};
}

Map<String, dynamic>? _fuzzyShortQtyMatch(
  String shortDigits,
  Iterable<Map<String, dynamic>> products,
) {
  if (_codeMatchesAnyWeightBarcode(shortDigits, products)) return null;
  if (shortDigits.length < 7) return null;
  Map<String, dynamic>? hit;
  for (final product in products) {
    if (!productSellByQty(product)) continue;
    final full = barcodeDigitsOnly(product['barcode']?.toString() ?? '');
    if (full.length < 7) continue;
    final suffix = full.substring(full.length - 7);
    if (!oneDigitApart(suffix, shortDigits)) continue;
    if (hit != null) return null;
    hit = product;
  }
  if (hit == null) return null;
  return {...hit, '_scan_mode': 'qty'};
}

/// Resolve a scanned barcode to a product and sale mode (`qty` or `weight`).
Map<String, dynamic>? resolveProductScanFromList(
  String barcode,
  Iterable<Map<String, dynamic>> products,
) {
  final code = normalizeBarcodeScanInput(barcode);
  if (code.isEmpty) return null;

  final list = products.map((p) => Map<String, dynamic>.from(p)).toList();
  final digits = barcodeDigitsOnly(code);
  if (digits.isEmpty) return null;

  // ── Full retail barcode (10+ digits): qty box EAN, then weight legacy barcode ──
  if (digits.length >= 10) {
    final qtyHit = _qtyFullBarcodeMatch(digits, list);
    if (qtyHit != null) return qtyHit;

    for (final product in list) {
      final hit = _weightBarcodeMatch(code, product, list);
      if (hit != null) return hit;
    }

    final parsed = WeightBarcode.parseReceiptBarcode(code);
    if (parsed != null) {
      for (final product in list) {
        final hit = _weightPrefixMatch(parsed.prefix, product, list);
        if (hit != null) {
          return {
            ...hit,
            '_scan_mode': 'weight',
            '_parsed_weight_g': parsed.weightGrams,
          };
        }
      }
    }
    return null;
  }

  // ── Short code (6–9 digits): weight label first, then qty suffix ──
  for (final product in list) {
    if (!productSellByQty(product)) continue;
    final bc = barcodeDigitsOnly(product['barcode']?.toString() ?? '');
    if (bc.isNotEmpty && bc == digits) {
      return {...product, '_scan_mode': 'qty'};
    }
  }

  for (final product in list) {
    final hit = _weightBarcodeMatch(code, product, list);
    if (hit != null) return hit;
  }

  final normalizedPrefix = WeightBarcode.normalizePrefixScan(code);
  if (normalizedPrefix != null) {
    for (final product in list) {
      final hit = _weightPrefixMatch(normalizedPrefix, product, list);
      if (hit != null) return hit;
    }
  }

  final shortDigits = shortScanDigits(code);
  if (shortDigits != null) {
    final suffixHit = _shortQtySuffixMatch(shortDigits, list);
    if (suffixHit != null) return suffixHit;

    final fuzzyWeightHit = _fuzzyShortWeightMatch(shortDigits, list);
    if (fuzzyWeightHit != null) return fuzzyWeightHit;

    final fuzzyQtyHit = _fuzzyShortQtyMatch(shortDigits, list);
    if (fuzzyQtyHit != null) return fuzzyQtyHit;
  }

  return null;
}

double? parsedWeightGramsFromScan(Map<String, dynamic> product) {
  return (product['_parsed_weight_g'] as num?)?.toDouble();
}

Map<String, dynamic> resolveScannedProductForSale(
  Map<String, dynamic> scanned,
  Iterable<Map<String, dynamic>> catalog,
) {
  if (!scanIsWeightMode(scanned)) return scanned;
  if (productSellByWeight(scanned)) return scanned;
  final sibling = _weightVariantOnLine(catalog, _productLineId(scanned));
  if (sibling == null) return scanned;
  return {
    ...sibling,
    '_scan_mode': 'weight',
    if (scanned['_parsed_weight_g'] != null) '_parsed_weight_g': scanned['_parsed_weight_g'],
  };
}

/// Normalize a product row loaded from SQLite for sale-mode detection.
Map<String, dynamic> normalizeProductRow(Map<String, dynamic> row) {
  final product = Map<String, dynamic>.from(row);
  final unitType = (product['unit_type'] ?? '').toString().trim().toLowerCase();
  if (unitType == 'weight' || unitType == 'quantity') return product;
  final sellByWeight = product['sell_by_weight'];
  if (sellByWeight == true || sellByWeight == 1) {
    product['unit_type'] = 'weight';
  } else {
    product['unit_type'] = 'quantity';
  }
  return product;
}
