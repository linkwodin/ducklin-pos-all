/// Weight-product receipt barcode: [8-digit prefix][4-digit weight in 0.01 kg][check digit 0].
/// Example: prefix 12345678, 1.2 kg -> 1234567801200
class WeightBarcode {
  /// Normalize a prefix-only scan (1–8 digits) to 8 digits for comparison.
  static String? normalizePrefixScan(String scanned) {
    final digits = scanned.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty || digits.length > 8) return null;
    return digits.padLeft(8, '0');
  }

  /// Parsed weight from a scale/receipt barcode scan.
  static ({String prefix, double weightGrams})? parseReceiptBarcode(String scanned) {
    final digits = scanned.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 13) return null;

    final prefix = digits.substring(0, 8);
    final weightPart = digits.substring(8, 12);
    final weightHundredthsKg = int.tryParse(weightPart);
    if (weightHundredthsKg == null || weightHundredthsKg <= 0) return null;

    // 4 digits = hundredths of kg (0.01 kg). E.g. 0120 -> 1.2 kg -> 1200 g.
    final weightGrams = weightHundredthsKg * 10.0;
    return (prefix: prefix, weightGrams: weightGrams);
  }

  /// Resolve prefix: explicit [prefix], else last 8 digits of [productBarcode] (digits only).
  static String? resolvePrefix({String? prefix, String? productBarcode}) {
    final p = prefix?.trim() ?? '';
    if (p.isNotEmpty) {
      if (!RegExp(r'^\d{1,8}$').hasMatch(p)) return null;
      return p;
    }
    final digits = (productBarcode ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.length <= 8) return digits;
    return digits.substring(digits.length - 8);
  }

  /// 8-digit prefix used to match scale barcodes for a product.
  static String? effectivePrefixForProduct(Map<String, dynamic> product) {
    final explicit = product['weight_barcode_prefix']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) {
      final resolved = resolvePrefix(prefix: explicit, productBarcode: null);
      return resolved?.padLeft(8, '0');
    }
    final weightBarcode = product['weight_barcode']?.toString().trim();
    if (weightBarcode != null && weightBarcode.isNotEmpty) {
      final resolved = resolvePrefix(prefix: '', productBarcode: weightBarcode);
      return resolved?.padLeft(8, '0');
    }
    final qtyBarcode = product['barcode']?.toString();
    final resolved = resolvePrefix(prefix: '', productBarcode: qtyBarcode);
    return resolved?.padLeft(8, '0');
  }

  /// [weightGrams] is the sold quantity in grams (POS cart stores grams for weight products).
  static String? formatReceiptBarcode({
    String? prefix,
    String? productBarcode,
    required double weightGrams,
  }) {
    final resolved = resolvePrefix(prefix: prefix, productBarcode: productBarcode);
    if (resolved == null || resolved.isEmpty) {
      return null;
    }
    final paddedPrefix = resolved.padLeft(8, '0');
    final weightKg = weightGrams / 1000.0;
    // Encode to hundredths of kg (0.01 kg units), e.g. 1.2 kg -> 120 -> 0120
    final weightPart = (weightKg * 100).round().clamp(0, 9999).toString().padLeft(4, '0');
    const checkDigit = '0'; // TBC: real check digit algorithm
    return '$paddedPrefix$weightPart$checkDigit';
  }
}
