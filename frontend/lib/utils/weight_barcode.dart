/// Weight-product receipt barcode: [6-digit prefix][6-digit weight in 0.001 kg][check digit 0].
/// Example: prefix 123456, 1.2 kg -> 1234560012000
class WeightBarcode {
  static const int prefixDigits = 6;
  static const int weightDigits = 6;

  /// Normalize a prefix-only scan (1–6 digits) to 6 digits for comparison.
  static String? normalizePrefixScan(String scanned) {
    final digits = scanned.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty || digits.length > prefixDigits) return null;
    return digits.padLeft(prefixDigits, '0');
  }

  static String _sixDigitPrefix(String digits, {bool preferLeading = false}) {
    if (digits.length <= prefixDigits) return digits.padLeft(prefixDigits, '0');
    return preferLeading
        ? digits.substring(0, prefixDigits)
        : digits.substring(digits.length - prefixDigits);
  }

  /// Parsed weight from a scale/receipt barcode scan.
  static ({String prefix, double weightGrams})? parseReceiptBarcode(String scanned) {
    final digits = scanned.replaceAll(RegExp(r'\D'), '');
    // Format: 6-digit prefix + 6-digit weight (0.001 kg) + check digit 0.
    final expectedLen = prefixDigits + weightDigits + 1;
    if (digits.length != expectedLen || digits[expectedLen - 1] != '0') return null;

    final prefix = digits.substring(0, prefixDigits);
    final weightPart = digits.substring(prefixDigits, prefixDigits + weightDigits);
    final weightThousandthsKg = int.tryParse(weightPart);
    if (weightThousandthsKg == null || weightThousandthsKg <= 0) return null;

    // 6 digits = thousandths of kg (0.001 kg). E.g. 001200 -> 1.2 kg -> 1200 g.
    final weightGrams = weightThousandthsKg.toDouble();
    return (prefix: prefix, weightGrams: weightGrams);
  }

  /// Resolve prefix: explicit [prefix], else last 6 digits of [productBarcode] (digits only).
  static String? resolvePrefix({
    String? prefix,
    String? productBarcode,
    bool preferLeading = false,
  }) {
    final p = prefix?.trim() ?? '';
    if (p.isNotEmpty) {
      if (!RegExp(r'^\d{1,8}$').hasMatch(p)) return null;
      return _sixDigitPrefix(p, preferLeading: preferLeading);
    }
    final digits = (productBarcode ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return _sixDigitPrefix(digits, preferLeading: preferLeading);
  }

  /// 6-digit prefix used to match scale barcodes for a product.
  static String? effectivePrefixForProduct(Map<String, dynamic> product) {
    final explicit = product['weight_barcode_prefix']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) {
      return resolvePrefix(prefix: explicit, productBarcode: null, preferLeading: true);
    }
    final weightBarcode = product['weight_barcode']?.toString().trim();
    if (weightBarcode != null && weightBarcode.isNotEmpty) {
      return resolvePrefix(prefix: '', productBarcode: weightBarcode, preferLeading: true);
    }
    final qtyBarcode = product['barcode']?.toString();
    return resolvePrefix(prefix: '', productBarcode: qtyBarcode, preferLeading: false);
  }

  /// [weightGrams] is the sold quantity in grams (POS cart stores grams for weight products).
  static String? formatReceiptBarcode({
    String? prefix,
    String? productBarcode,
    required double weightGrams,
    bool? preferLeadingPrefix,
  }) {
    final hasExplicitPrefix = (prefix?.trim() ?? '').isNotEmpty;
    final preferLeading = preferLeadingPrefix ?? hasExplicitPrefix;
    final resolved = resolvePrefix(
      prefix: prefix,
      productBarcode: productBarcode,
      preferLeading: preferLeading,
    );
    if (resolved == null || resolved.isEmpty) {
      return null;
    }
    // Encode to thousandths of kg (0.001 kg units), e.g. 1.2 kg -> 1200 -> 001200
    final weightPart = weightGrams.round().clamp(0, 999999).toString().padLeft(weightDigits, '0');
    const checkDigit = '0'; // TBC: real check digit algorithm
    return '$resolved$weightPart$checkDigit';
  }
}
