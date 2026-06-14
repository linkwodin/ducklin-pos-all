import 'product_inventory.dart';
import 'weight_barcode.dart';

/// True when [stored] and [scanned] are the same barcode, or the same EAN-13
/// except for a wrong check digit (first 12 digits match).
bool barcodesMatchForLookup(String stored, String scanned) {
  final a = stored.trim();
  final b = scanned.trim();
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (a.length == 13 && b.length == 13 && RegExp(r'^\d{13}$').hasMatch(a) && RegExp(r'^\d{13}$').hasMatch(b)) {
    return a.substring(0, 12) == b.substring(0, 12);
  }
  return false;
}

/// Resolve a scanned barcode to a product and sale mode (`qty` or `weight`).
/// Returns null if the barcode does not match any product.
Map<String, dynamic>? resolveProductScanFromList(
  String barcode,
  Iterable<Map<String, dynamic>> products,
) {
  final code = barcode.trim();
  if (code.isEmpty) return null;

  for (final product in products) {
    final map = Map<String, dynamic>.from(product);
    final qty = map['barcode']?.toString().trim();
    if (qty != null && qty.isNotEmpty && barcodesMatchForLookup(qty, code)) {
      if (productSellByQty(map)) {
        return {...map, '_scan_mode': 'qty'};
      }
      return {...map, '_scan_mode': 'qty', '_sale_mode_blocked': true};
    }
    final weight = map['weight_barcode']?.toString().trim();
    if (weight != null && weight.isNotEmpty && barcodesMatchForLookup(weight, code)) {
      if (productSellByWeight(map)) {
        return {...map, '_scan_mode': 'weight'};
      }
      return {...map, '_scan_mode': 'weight', '_sale_mode_blocked': true};
    }
    // Legacy weight-only: barcode is the weight barcode
    final unitType = (map['unit_type'] ?? 'quantity').toString().toLowerCase();
    final sellByQty = map['sell_by_qty'];
    final legacyWeightOnly = unitType == 'weight' &&
        sellByQty != true &&
        sellByQty != 1 &&
        (map['sell_by_weight'] == null ||
            map['sell_by_weight'] == false ||
            map['sell_by_weight'] == 0);
    if (legacyWeightOnly && qty != null && barcodesMatchForLookup(qty, code) && productSellByWeight(map)) {
      return {...map, '_scan_mode': 'weight'};
    }
  }

  // Scale / receipt barcode: 8-digit prefix + 4-digit weight (0.01 kg) + check digit.
  final parsed = WeightBarcode.parseReceiptBarcode(code);
  if (parsed != null) {
    for (final product in products) {
      final map = Map<String, dynamic>.from(product);
      if (!productSellByWeight(map)) continue;
      final productPrefix = WeightBarcode.effectivePrefixForProduct(map);
      if (productPrefix != null && productPrefix == parsed.prefix) {
        return {
          ...map,
          '_scan_mode': 'weight',
          '_parsed_weight_g': parsed.weightGrams,
        };
      }
    }
  }

  // Prefix-only scan (1–8 digits): identify weight product without embedded weight.
  final normalizedPrefix = WeightBarcode.normalizePrefixScan(code);
  if (normalizedPrefix != null) {
    for (final product in products) {
      final map = Map<String, dynamic>.from(product);
      if (!productSellByWeight(map)) continue;
      final productPrefix = WeightBarcode.effectivePrefixForProduct(map);
      if (productPrefix != null && productPrefix == normalizedPrefix) {
        return {...map, '_scan_mode': 'weight'};
      }
    }
  }

  return null;
}

/// Weight in grams parsed from a prefix barcode scan, if any.
double? parsedWeightGramsFromScan(Map<String, dynamic> product) {
  return (product['_parsed_weight_g'] as num?)?.toDouble();
}
