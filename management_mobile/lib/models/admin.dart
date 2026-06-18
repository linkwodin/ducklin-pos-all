import 'store.dart';
import 'user.dart';

class RestockOrderItem {
  final int id;
  final int productId;
  final double quantity;
  final String? productName;

  const RestockOrderItem({
    required this.id,
    required this.productId,
    required this.quantity,
    this.productName,
  });

  factory RestockOrderItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    return RestockOrderItem(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      productName: product?['name']?.toString(),
    );
  }
}

class RestockOrder {
  final int id;
  final int storeId;
  final String status;
  final String? trackingNumber;
  final String? initiatedAt;
  final String? notes;
  final Store? store;
  final AppUser? initiator;
  final List<RestockOrderItem> items;

  const RestockOrder({
    required this.id,
    required this.storeId,
    required this.status,
    this.trackingNumber,
    this.initiatedAt,
    this.notes,
    this.store,
    this.initiator,
    this.items = const [],
  });

  factory RestockOrder.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List<dynamic>? ?? [];
    return RestockOrder(
      id: json['id'] as int,
      storeId: json['store_id'] as int,
      status: '${json['status'] ?? ''}',
      trackingNumber: json['tracking_number']?.toString(),
      initiatedAt: json['initiated_at']?.toString(),
      notes: json['notes']?.toString(),
      store: json['store'] != null
          ? Store.fromJson(json['store'] as Map<String, dynamic>)
          : null,
      initiator: json['initiator'] != null
          ? AppUser.fromJson(json['initiator'] as Map<String, dynamic>)
          : null,
      items: itemsRaw
          .map((e) => RestockOrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PosDevice {
  final int id;
  final String deviceCode;
  final int storeId;
  final String? deviceName;
  final bool isActive;
  final Store? store;

  const PosDevice({
    required this.id,
    required this.deviceCode,
    required this.storeId,
    this.deviceName,
    this.isActive = true,
    this.store,
  });

  factory PosDevice.fromJson(Map<String, dynamic> json) => PosDevice(
        id: json['id'] as int,
        deviceCode: '${json['device_code'] ?? ''}',
        storeId: json['store_id'] as int,
        deviceName: json['device_name']?.toString(),
        isActive: json['is_active'] != false,
        store: json['store'] != null
            ? Store.fromJson(json['store'] as Map<String, dynamic>)
            : null,
      );
}

class CurrencyRate {
  final int id;
  final String currencyCode;
  final double rateToGbp;
  final bool isPinned;

  const CurrencyRate({
    required this.id,
    required this.currencyCode,
    required this.rateToGbp,
    this.isPinned = false,
  });

  factory CurrencyRate.fromJson(Map<String, dynamic> json) => CurrencyRate(
        id: json['id'] as int,
        currencyCode: '${json['currency_code'] ?? ''}',
        rateToGbp: (json['rate_to_gbp'] as num?)?.toDouble() ?? 0,
        isPinned: json['is_pinned'] == true,
      );
}

class CompanySettings {
  final String companyName;
  final String addressLine1;
  final String city;
  final String postcode;
  final String telephone;
  final String email;
  final String paymentInfo;
  final String? shipmentCouriers;
  final String? paymentTransferToInfo;
  final String wholesaleOrderEmailSubjectTemplate;
  final String wholesaleOrderEmailDefaultCc;

  const CompanySettings({
    required this.companyName,
    this.addressLine1 = '',
    this.city = '',
    this.postcode = '',
    this.telephone = '',
    this.email = '',
    this.paymentInfo = '',
    this.shipmentCouriers,
    this.paymentTransferToInfo,
    this.wholesaleOrderEmailSubjectTemplate = '',
    this.wholesaleOrderEmailDefaultCc = '',
  });

  factory CompanySettings.fromJson(Map<String, dynamic> json) => CompanySettings(
        companyName: '${json['company_name'] ?? ''}',
        addressLine1: '${json['address_line1'] ?? ''}',
        city: '${json['city'] ?? ''}',
        postcode: '${json['postcode'] ?? ''}',
        telephone: '${json['telephone'] ?? ''}',
        email: '${json['email'] ?? ''}',
        paymentInfo: '${json['payment_info'] ?? ''}',
        shipmentCouriers: json['shipment_couriers']?.toString(),
        paymentTransferToInfo: json['payment_transfer_to_info']?.toString(),
        wholesaleOrderEmailSubjectTemplate: '${json['wholesale_order_email_subject_template'] ?? ''}',
        wholesaleOrderEmailDefaultCc: '${json['wholesale_order_email_default_cc'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'company_name': companyName,
        'address_line1': addressLine1,
        'city': city,
        'postcode': postcode,
        'telephone': telephone,
        'email': email,
        'payment_info': paymentInfo,
        if (shipmentCouriers != null) 'shipment_couriers': shipmentCouriers,
        'wholesale_order_email_subject_template': wholesaleOrderEmailSubjectTemplate,
        'wholesale_order_email_default_cc': wholesaleOrderEmailDefaultCc,
      };
}

class AuditLogEntry {
  final int id;
  final String action;
  final String? createdAt;
  final String? changes;

  const AuditLogEntry({
    required this.id,
    required this.action,
    this.createdAt,
    this.changes,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        id: json['id'] as int,
        action: '${json['action'] ?? ''}',
        createdAt: json['created_at']?.toString(),
        changes: json['changes']?.toString(),
      );
}
