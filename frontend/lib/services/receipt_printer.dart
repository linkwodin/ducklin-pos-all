import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
import 'package:pos_system/l10n/app_localizations.dart';
import 'full_receipt_printer.dart';
import 'barcode_receipt_printer.dart';
import 'simple_receipt_printer.dart';
import 'receipt_printer_helpers.dart';
import '../utils/pos_receipt_config.dart';

enum ReceiptType {
  full, // With price, with QR code
  auditNote, // Internal audit note: no price, with QR code
  noPriceWithBarcode, // Without price, with barcode — 下單紙 (龍鳳存根)
  customerCounterfoil, // Same as noPriceWithBarcode — 下單紙 (客戶存根)
  noPriceNoBarcode, // Without price, without barcode (貨品細明 Pickup Receipt)
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

    // Route to appropriate printer (order receipt / full is disabled — do not print)
    final orderForPrint = await ReceiptPrinterHelpers.enrichOrderForReceipt(order);
    switch (receiptType) {
      case ReceiptType.full:
        // Order receipt (訂單收據) is not printed — no-op
        return;
      case ReceiptType.auditNote:
        await FullReceiptPrinter.printReceipt(
          order: orderForPrint,
          l10n: l10n,
          generator: generator,
          printerConfig: printerConfig,
          includePrice: false,
        );
        break;
      case ReceiptType.noPriceWithBarcode: {
        final orderWithTitle = Map<String, dynamic>.from(orderForPrint);
        orderWithTitle['receipt_name'] = '下單紙 (龍鳳存根)\nOrder Clip (Loon Fung copy)';
        await BarcodeReceiptPrinter.printReceipt(
          order: orderWithTitle,
          l10n: l10n,
          generator: generator,
          printerConfig: printerConfig,
        );
        break;
      }
      case ReceiptType.customerCounterfoil: {
        final orderWithTitle = Map<String, dynamic>.from(orderForPrint);
        orderWithTitle['receipt_name'] = '下單紙 (客戶存根)\nOrder Clip (Customer copy)';
        await BarcodeReceiptPrinter.printReceipt(
          order: orderWithTitle,
          l10n: l10n,
          generator: generator,
          printerConfig: printerConfig,
        );
        break;
      }
      case ReceiptType.noPriceNoBarcode:
        await SimpleReceiptPrinter.printReceipt(
          order: orderForPrint,
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
    if (orderConfig != null && orderConfig['receipt_types'] != null) {
      return receiptTypesFromKeys(orderConfig['receipt_types'] as List<dynamic>?);
    }
    if (orderConfig != null &&
        (orderConfig['pos_receipt_types'] != null ||
            orderConfig['pos_auto_print_receipt_types'] != null)) {
      return enabledReceiptTypesFromConfig(orderConfig);
    }
    return receiptTypesFromKeys(null);
  }

  static List<ReceiptType> getAutoPrintTypes(Map<String, dynamic>? config) {
    return autoPrintReceiptTypesFromConfig(config);
  }
}
