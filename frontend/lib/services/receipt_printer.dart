import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
import 'package:pos_system/l10n/app_localizations.dart';
import 'full_receipt_printer.dart';
import 'barcode_receipt_printer.dart';
import 'simple_receipt_printer.dart';
import 'receipt_printer_helpers.dart';

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
    switch (receiptType) {
      case ReceiptType.full:
        // Order receipt (訂單收據) is not printed — no-op
        return;
      case ReceiptType.auditNote:
        await FullReceiptPrinter.printReceipt(
          order: order,
          l10n: l10n,
          generator: generator,
          printerConfig: printerConfig,
          includePrice: false,
        );
        break;
      case ReceiptType.noPriceWithBarcode: {
        final orderWithTitle = Map<String, dynamic>.from(order);
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
        final orderWithTitle = Map<String, dynamic>.from(order);
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
          if (typeStr == 'auditnote' || typeStr == 'audit_note') return ReceiptType.auditNote;
          if (typeStr == 'nopricewithbarcode' || typeStr == 'no_price_with_barcode') return ReceiptType.noPriceWithBarcode;
          if (typeStr == 'customercounterfoil' || typeStr == 'customer_counterfoil') return ReceiptType.customerCounterfoil;
          if (typeStr == 'nopricenobarcode' || typeStr == 'no_price_no_barcode') return ReceiptType.noPriceNoBarcode;
          return null;
        }).whereType<ReceiptType>().toList();
      }
    }
    
    // Default: all types enabled
    return ReceiptType.values;
  }
}
