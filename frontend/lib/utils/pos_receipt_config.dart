import '../services/receipt_printer.dart';

const defaultPosReceiptTypeKeys = [
  'audit_note',
  'no_price_with_barcode',
  'customer_counterfoil',
  'no_price_no_barcode',
];

const defaultPosAutoPrintReceiptTypeKeys = [
  'no_price_with_barcode',
  'customer_counterfoil',
  'no_price_no_barcode',
];

ReceiptType? receiptTypeFromKey(String key) {
  final typeStr = key.toLowerCase().trim();
  if (typeStr == 'full') return ReceiptType.full;
  if (typeStr == 'auditnote' || typeStr == 'audit_note') return ReceiptType.auditNote;
  if (typeStr == 'nopricewithbarcode' || typeStr == 'no_price_with_barcode') {
    return ReceiptType.noPriceWithBarcode;
  }
  if (typeStr == 'customercounterfoil' || typeStr == 'customer_counterfoil') {
    return ReceiptType.customerCounterfoil;
  }
  if (typeStr == 'nopricenobarcode' || typeStr == 'no_price_no_barcode') {
    return ReceiptType.noPriceNoBarcode;
  }
  return null;
}

List<ReceiptType> receiptTypesFromKeys(List<dynamic>? keys, {List<String>? defaults}) {
  final source = (keys != null && keys.isNotEmpty)
      ? keys
      : (defaults ?? defaultPosReceiptTypeKeys);
  return source
      .map((k) => receiptTypeFromKey(k.toString()))
      .whereType<ReceiptType>()
      .where((t) => t != ReceiptType.full)
      .toList();
}

bool receiptSettingsConfigured(Map<String, dynamic>? config) {
  final value = config?['pos_receipt_settings_configured'];
  return value == true || value == 1;
}

List<ReceiptType> enabledReceiptTypesFromConfig(Map<String, dynamic>? config) {
  final raw = config?['pos_receipt_types'];
  if (raw is List) {
    return receiptTypesFromKeys(raw);
  }
  return receiptTypesFromKeys(null);
}

List<ReceiptType> autoPrintReceiptTypesFromConfig(Map<String, dynamic>? config) {
  final enabled = enabledReceiptTypesFromConfig(config).toSet();
  final rawAuto = config?['pos_auto_print_receipt_types'];
  if (rawAuto is List) {
    return rawAuto
        .map((k) => receiptTypeFromKey(k.toString()))
        .whereType<ReceiptType>()
        .where((t) => t != ReceiptType.full)
        .where(enabled.contains)
        .toList();
  }
  return receiptTypesFromKeys(
    null,
    defaults: defaultPosAutoPrintReceiptTypeKeys,
  ).where(enabled.contains).toList();
}

Map<String, dynamic> receiptConfigFromStore(Map<String, dynamic> store) {
  final out = <String, dynamic>{};
  if (receiptSettingsConfigured(store)) {
    out['pos_receipt_settings_configured'] = true;
  }
  if (store['pos_receipt_types'] is List) {
    out['pos_receipt_types'] = store['pos_receipt_types'];
  }
  if (store['pos_auto_print_receipt_types'] is List) {
    out['pos_auto_print_receipt_types'] = store['pos_auto_print_receipt_types'];
  }
  return out;
}

Map<String, dynamic> mergeReceiptConfigs(
  Map<String, dynamic>? primary,
  Map<String, dynamic>? secondary,
) {
  final merged = <String, dynamic>{};
  for (final source in [secondary, primary]) {
    if (source == null) continue;
    if (receiptSettingsConfigured(source)) {
      merged['pos_receipt_settings_configured'] = true;
    }
    if (source['pos_receipt_types'] is List) {
      merged['pos_receipt_types'] = source['pos_receipt_types'];
    }
    if (source['pos_auto_print_receipt_types'] is List) {
      merged['pos_auto_print_receipt_types'] = source['pos_auto_print_receipt_types'];
    }
  }
  return merged;
}
