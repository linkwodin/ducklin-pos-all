import 'shipment.dart';
import 'store.dart';
import 'wholesale_client.dart';

class WholesaleOrderDocument {
  final int id;
  final String type;
  final String fileUrl;
  final String? originalFilename;
  final String? createdAt;

  const WholesaleOrderDocument({
    required this.id,
    required this.type,
    required this.fileUrl,
    this.originalFilename,
    this.createdAt,
  });

  factory WholesaleOrderDocument.fromJson(Map<String, dynamic> json) =>
      WholesaleOrderDocument(
        id: json['id'] as int,
        type: '${json['type'] ?? ''}',
        fileUrl: '${json['file_url'] ?? ''}',
        originalFilename: json['original_filename']?.toString(),
        createdAt: json['created_at']?.toString(),
      );
}

class WholesaleOrderItem {
  final int id;
  final int productId;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final int? assignedStoreId;
  final Store? assignedStore;
  final String? productName;
  final String? productNameChinese;

  const WholesaleOrderItem({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.assignedStoreId,
    this.assignedStore,
    this.productName,
    this.productNameChinese,
  });

  factory WholesaleOrderItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    return WholesaleOrderItem(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0,
      assignedStoreId: json['assigned_store_id'] as int?,
      assignedStore: json['assigned_store'] != null
          ? Store.fromJson(json['assigned_store'] as Map<String, dynamic>)
          : null,
      productName: product?['name']?.toString(),
      productNameChinese: product?['name_chinese']?.toString(),
    );
  }

  String displayName() {
    if (productNameChinese != null && productNameChinese!.isNotEmpty) {
      return productName != null && productName!.isNotEmpty
          ? '$productName ($productNameChinese)'
          : productNameChinese!;
    }
    return productName ?? 'Product #$productId';
  }
}

class WholesaleClientBrief {
  final int id;
  final String name;
  final String? email;

  const WholesaleClientBrief({required this.id, required this.name, this.email});

  factory WholesaleClientBrief.fromJson(Map<String, dynamic> json) => WholesaleClientBrief(
        id: json['id'] as int,
        name: '${json['name'] ?? ''}',
        email: json['email']?.toString(),
      );
}

class WholesaleOrder {
  final int id;
  final String orderNumber;
  final String? poNumber;
  final String? refNo;
  final String? orderChannel;
  final String status;
  final String? createdAt;
  final String? reviewedAt;
  final String? poDate;
  final String? orderDate;
  final String? invoiceSentAt;
  final String? paymentTerms;
  final String? notes;
  final String? rejectionReason;
  final double? amountDue;
  final double? totalNet;
  final double? shippingFee;
  final double? discountAmount;
  final int wholesaleClientId;
  final int? wholesaleClientStoreId;
  final int storeId;
  final String? paymentConfirmedAt;
  final String? paymentProofUrl;
  final bool workflowInvoiceEmailDone;
  final double? workflowPaymentProofTotal;
  final bool isCompleted;
  final WholesaleClientBrief? client;
  final WholesaleClientStore? clientStore;
  final List<WholesaleOrderItem> items;
  final List<WholesaleOrderDocument> documents;
  final List<Shipment> shipments;

  const WholesaleOrder({
    required this.id,
    required this.orderNumber,
    this.poNumber,
    this.refNo,
    this.orderChannel,
    required this.status,
    this.createdAt,
    this.reviewedAt,
    this.poDate,
    this.orderDate,
    this.invoiceSentAt,
    this.paymentTerms,
    this.notes,
    this.rejectionReason,
    this.amountDue,
    this.totalNet,
    this.shippingFee,
    this.discountAmount,
    required this.wholesaleClientId,
    this.wholesaleClientStoreId,
    required this.storeId,
    this.paymentConfirmedAt,
    this.paymentProofUrl,
    this.workflowInvoiceEmailDone = false,
    this.workflowPaymentProofTotal,
    this.isCompleted = false,
    this.client,
    this.clientStore,
    this.items = const [],
    this.documents = const [],
    this.shipments = const [],
  });

  factory WholesaleOrder.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List<dynamic>? ?? [];
    final docsRaw = json['documents'] as List<dynamic>? ?? [];
    final shipmentsRaw = json['shipments'] as List<dynamic>? ?? [];
    return WholesaleOrder(
      id: json['id'] as int,
      orderNumber: '${json['order_number'] ?? ''}',
      poNumber: json['po_number']?.toString(),
      refNo: json['ref_no']?.toString(),
      orderChannel: json['order_channel']?.toString(),
      status: '${json['status'] ?? ''}',
      createdAt: json['created_at']?.toString(),
      reviewedAt: json['reviewed_at']?.toString(),
      poDate: json['po_date']?.toString(),
      orderDate: json['order_date']?.toString(),
      invoiceSentAt: json['invoice_sent_at']?.toString(),
      paymentTerms: json['payment_terms']?.toString(),
      notes: json['notes']?.toString(),
      rejectionReason: json['rejection_reason']?.toString(),
      amountDue: (json['amount_due'] as num?)?.toDouble(),
      totalNet: (json['total_net'] as num?)?.toDouble(),
      shippingFee: (json['shipping_fee'] as num?)?.toDouble(),
      discountAmount: (json['discount_amount'] as num?)?.toDouble(),
      wholesaleClientId: json['wholesale_client_id'] as int,
      wholesaleClientStoreId: json['wholesale_client_store_id'] as int?,
      storeId: json['store_id'] as int,
      paymentConfirmedAt: json['payment_confirmed_at']?.toString(),
      paymentProofUrl: json['payment_proof_url']?.toString(),
      workflowInvoiceEmailDone: json['workflow_invoice_email_done'] == true,
      workflowPaymentProofTotal: (json['workflow_payment_proof_total'] as num?)?.toDouble(),
      isCompleted: json['is_completed'] == true,
      client: json['wholesale_client'] != null
          ? WholesaleClientBrief.fromJson(json['wholesale_client'] as Map<String, dynamic>)
          : null,
      clientStore: json['wholesale_client_store'] != null
          ? WholesaleClientStore.fromJson(json['wholesale_client_store'] as Map<String, dynamic>)
          : null,
      items: itemsRaw
          .map((e) => WholesaleOrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      documents: docsRaw
          .map((e) => WholesaleOrderDocument.fromJson(e as Map<String, dynamic>))
          .toList(),
      shipments: shipmentsRaw.map((e) => Shipment.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  double get itemsTotal => items.fold(0, (sum, it) => sum + it.lineTotal);

  List<int> get shipmentIds => shipments.map((s) => s.id).toList();
}
