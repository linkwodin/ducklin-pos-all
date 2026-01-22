import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
import 'package:pos_system/l10n/app_localizations.dart';
import 'full_receipt_printer.dart';
import 'barcode_receipt_printer.dart';
import 'simple_receipt_printer.dart';
import 'receipt_printer_helpers.dart';

enum ReceiptType {
  full, // With price, with QR code
  noPriceWithBarcode, // Without price, with barcode
  noPriceNoBarcode, // Without price, without barcode
}

/// Main receipt printer router - delegates to specific receipt printers
class ReceiptPrinter {
  /// Print receipt based on type
  /// 
  /// [enabledTypes] - List of enabled receipt types from backend config.
  /// If a receipt type is not in this list, it will throw an exception.
  static Future<void> printReceipt({
    required Map<String, dynamic> order,
    required AppLocalizations l10n,
    required ReceiptType receiptType,
    List<ReceiptType>? enabledTypes,
  }) async {
    // Check if receipt type is enabled (if enabledTypes is provided)
    if (enabledTypes != null && !enabledTypes.contains(receiptType)) {
      throw Exception('Receipt type ${receiptType.name} is not enabled. Please check backend configuration.');
    }

    // Get printer configuration
    final printerConfig = await ReceiptPrinterHelpers.getPrinterConfig();
    ReceiptPrinterHelpers.validatePrinterConfig(printerConfig);

    // Initialize generator
    final profile = await esc_pos_utils.CapabilityProfile.load();
    final generator = esc_pos_utils.Generator(esc_pos_utils.PaperSize.mm80, profile);

    // Route to appropriate printer
    switch (receiptType) {
      case ReceiptType.full:
        await FullReceiptPrinter.printReceipt(
          order: order,
          l10n: l10n,
          generator: generator,
          printerConfig: printerConfig,
        );
        break;
      case ReceiptType.noPriceWithBarcode:
        await BarcodeReceiptPrinter.printReceipt(
          order: order,
          l10n: l10n,
          generator: generator,
          printerConfig: printerConfig,
        );
        break;
      case ReceiptType.noPriceNoBarcode:
        await SimpleReceiptPrinter.printReceipt(
          order: order,
          l10n: l10n,
          generator: generator,
          printerConfig: printerConfig,
        );
        break;
    }
  }

  /// Get enabled receipt types from order or backend config
  /// This can be called to check which receipt types are available
  static List<ReceiptType> getEnabledTypes(Map<String, dynamic>? orderConfig) {
    // If order config has receipt_types, use that
    if (orderConfig != null && orderConfig['receipt_types'] != null) {
      final types = orderConfig['receipt_types'] as List<dynamic>?;
      if (types != null) {
        return types.map((t) {
          final typeStr = t.toString().toLowerCase();
          if (typeStr == 'full') return ReceiptType.full;
          if (typeStr == 'nopricewithbarcode' || typeStr == 'no_price_with_barcode') return ReceiptType.noPriceWithBarcode;
          if (typeStr == 'nopricenobarcode' || typeStr == 'no_price_no_barcode') return ReceiptType.noPriceNoBarcode;
          return null;
        }).whereType<ReceiptType>().toList();
      }
    }
    
    // Default: all types enabled
    return ReceiptType.values;
  }
}
