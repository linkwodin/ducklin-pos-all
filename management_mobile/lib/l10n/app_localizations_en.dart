// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'POS Management';

  @override
  String get loginSubtitle => 'Sign in with your management account';

  @override
  String get signIn => 'Sign in';

  @override
  String get username => 'Username';

  @override
  String get usernameRequired => 'Username required';

  @override
  String get password => 'Password';

  @override
  String get passwordRequired => 'Password required';

  @override
  String useBiometricNextTime(String label) {
    return 'Use $label next time';
  }

  @override
  String get biometricUnlockHint =>
      'Unlock the app without typing your password';

  @override
  String unlockWithBiometric(String label) {
    return 'Unlock with $label';
  }

  @override
  String get unlock => 'Unlock';

  @override
  String get checking => 'Checking…';

  @override
  String get usePasswordInstead => 'Use password instead';

  @override
  String biometricFailed(String label) {
    return '$label authentication failed';
  }

  @override
  String get logout => 'Log out';

  @override
  String get logoutConfirm => 'Log out?';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get retry => 'Retry';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get create => 'Create';

  @override
  String get none => 'None';

  @override
  String get all => 'All';

  @override
  String get status => 'Status';

  @override
  String get store => 'Store';

  @override
  String get client => 'Client';

  @override
  String get created => 'Created';

  @override
  String get courier => 'Courier';

  @override
  String get tracking => 'Tracking';

  @override
  String get items => 'Items';

  @override
  String get documents => 'Documents';

  @override
  String get overview => 'Overview';

  @override
  String get shipments => 'Shipments';

  @override
  String get process => 'Process';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChineseTraditional => '繁體中文';

  @override
  String get languageChineseSimplified => '简体中文';

  @override
  String get menuDashboard => 'Dashboard';

  @override
  String get menuReports => 'Reports';

  @override
  String get menuProductsGroup => 'Products';

  @override
  String get menuProducts => 'Products';

  @override
  String get menuCategories => 'Categories';

  @override
  String get menuSectors => 'Sectors';

  @override
  String get menuInventoryGroup => 'Inventory';

  @override
  String get menuStock => 'Stock';

  @override
  String get menuRestock => 'Restock orders';

  @override
  String get menuPosOrders => 'POS orders';

  @override
  String get menuWholesaleGroup => 'Wholesale';

  @override
  String get menuWholesaleOrders => 'Orders';

  @override
  String get menuShipments => 'Shipments';

  @override
  String get menuWholesaleClients => 'Clients';

  @override
  String get menuSettingsGroup => 'Settings';

  @override
  String get menuUsers => 'Users';

  @override
  String get menuStores => 'Stores';

  @override
  String get menuDevices => 'Devices';

  @override
  String get menuCurrency => 'Currency rates';

  @override
  String get menuCompany => 'Company settings';

  @override
  String get management => 'Management';

  @override
  String get roleManagement => 'Management';

  @override
  String get roleSupervisor => 'Supervisor';

  @override
  String get roleCashier => 'Cashier';

  @override
  String get roleStaff => 'Staff';

  @override
  String get searchOrderPoClient => 'Search order, PO, client…';

  @override
  String get tabDashboard => 'Dashboard';

  @override
  String get tabList => 'List';

  @override
  String get nothingHere => 'Nothing here';

  @override
  String get shipmentUpdated => 'Shipment updated';

  @override
  String get shipmentTitle => 'Shipment';

  @override
  String shipmentNumber(int id) {
    return 'Shipment #$id';
  }

  @override
  String boxesCount(int count) {
    return '$count boxes';
  }

  @override
  String get monitorPacking => 'Packing';

  @override
  String get monitorPackedAwaitingCourier => 'Packed — awaiting courier';

  @override
  String get monitorShipped => 'Shipped';

  @override
  String get monitorCompletedRecent => 'Completed (recent)';

  @override
  String get batchPack => 'Batch pack';

  @override
  String get courierPickup => 'Courier pickup';

  @override
  String get workflowPickPack => 'Pick & pack';

  @override
  String get workflowPickPackSub => 'Scan items and confirm box counts';

  @override
  String get workflowCourier => 'Courier details';

  @override
  String get workflowCourierSub =>
      'Courier, tracking number, and delivery date';

  @override
  String get workflowHandoff => 'Delivery handoff';

  @override
  String get workflowHandoffUploaded => 'Signed delivery note uploaded';

  @override
  String get workflowHandoffUploadShipped => 'Upload signed delivery note';

  @override
  String get workflowHandoffUploadAndShip =>
      'Upload signed delivery note and mark shipped';

  @override
  String get saveDetails => 'Save details';

  @override
  String get batchPacking => 'Batch packing';

  @override
  String get packingQueueComplete => 'Packing queue complete';

  @override
  String get noShipmentsInQueue => 'No shipments left in queue';

  @override
  String get skipThisShipment => 'Skip this shipment';

  @override
  String get startPacking => 'Start packing';

  @override
  String get shipmentStatusAssigned => 'Assigned';

  @override
  String get shipmentStatusPacking => 'Packing';

  @override
  String get shipmentStatusPacked => 'Packed';

  @override
  String get shipmentStatusShipped => 'Shipped';

  @override
  String get shipmentStatusCompleted => 'Completed';

  @override
  String get filterPendingApproval => 'Pending approval';

  @override
  String get filterAssignShipment => 'Assign shipment';

  @override
  String get filterAwaitingPayment => 'Awaiting payment';

  @override
  String get filterCompleted => 'Completed';

  @override
  String get filterRejected => 'Rejected';

  @override
  String get filterDeleted => 'Deleted';

  @override
  String get wholesaleStatusRejected => 'Rejected';

  @override
  String get wholesaleStatusDeleted => 'Deleted';

  @override
  String get wholesaleStatusCompleted => 'Completed';

  @override
  String get wholesaleStatusPendingOrderConfirmation =>
      'Pending order confirmation';

  @override
  String get wholesaleStatusPendingPacking => 'Pending packing';

  @override
  String get wholesaleStatusInTransit => 'In transit';

  @override
  String get wholesaleStatusPendingPayment => 'Pending payment confirmation';

  @override
  String get wholesaleStatusPendingApproval => 'Pending approval';

  @override
  String get wholesaleStatusAssignShipment => 'Assign shipment';

  @override
  String get wholesaleStatusApproved => 'Approved';

  @override
  String get posFilterPending => 'Pending';

  @override
  String get posFilterPaid => 'Paid';

  @override
  String get posFilterPickedUp => 'Picked up';

  @override
  String get posFilterCancelled => 'Cancelled';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get chooseFromGallery => 'Choose from gallery';

  @override
  String get chooseFile => 'Choose file';

  @override
  String get rejectOrder => 'Reject order';

  @override
  String get rejectReason => 'Reason';

  @override
  String get reject => 'Reject';

  @override
  String get noDocumentsYet => 'No documents yet';

  @override
  String get uploadPoAttachment => 'Upload PO attachment';

  @override
  String get assigned => 'Assigned';

  @override
  String get move => 'Move';

  @override
  String get remove => 'Remove';

  @override
  String get skip => 'Skip';

  @override
  String get emailSkipped => 'Email skipped';

  @override
  String get emailSent => 'Email sent';

  @override
  String get resubmit => 'Resubmit';

  @override
  String get selectStore => 'Select store';

  @override
  String get assignByDefaults => 'Assign by defaults';

  @override
  String get changeAssignment => 'Change assignment';

  @override
  String get regenerateOrderConfirmationPdf =>
      'Regenerate order confirmation PDF';

  @override
  String linesCount(int count) {
    return '$count lines';
  }

  @override
  String get generateInvoice => 'Generate invoice';

  @override
  String orderTotal(String amount) {
    return 'Order total: $amount';
  }

  @override
  String proofTotal(String amount) {
    return 'Proof total: $amount';
  }

  @override
  String get uploadPaymentProof => 'Upload payment proof';

  @override
  String get confirmPaymentReceived => 'Confirm payment received';

  @override
  String get paymentConfirmed => 'Payment confirmed';

  @override
  String get moveReassign => 'Move / reassign';

  @override
  String moveFrom(String store) {
    return 'From $store';
  }

  @override
  String get skipEmail => 'Skip email';

  @override
  String get loadReport => 'Load report';

  @override
  String get posRevenue => 'POS revenue';

  @override
  String posOrdersCount(int count) {
    return 'POS orders: $count';
  }

  @override
  String get allStores => 'All stores';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get saveSettings => 'Save settings';

  @override
  String get createWholesaleOrder => 'Create wholesale order';

  @override
  String get addAtLeastOneProduct => 'Add at least one product';

  @override
  String get companyAddress => 'Company address';

  @override
  String get sourceClientPo => 'Client PO';

  @override
  String get sourceWhatsapp => 'WhatsApp';

  @override
  String get sourceEmail => 'Email';

  @override
  String get sourceNa => 'N/A';

  @override
  String get lineItems => 'Line items';

  @override
  String unitPrice(String amount) {
    return 'Unit price: $amount';
  }

  @override
  String poAttachments(int count) {
    return 'PO attachments ($count)';
  }

  @override
  String get createOrder => 'Create order';

  @override
  String get deliveryLocations => 'Delivery locations';

  @override
  String get auditLog => 'Audit log';

  @override
  String get registerDevice => 'Register device';

  @override
  String get register => 'Register';

  @override
  String get newCategory => 'New category';

  @override
  String get newSector => 'New sector';

  @override
  String get newStore => 'New store';

  @override
  String get warehouse => 'Warehouse';

  @override
  String get receive => 'Receive';

  @override
  String get markPaid => 'Mark paid';

  @override
  String get markComplete => 'Mark complete';

  @override
  String get cancelOrder => 'Cancel order?';

  @override
  String get cancelOrderAction => 'Cancel order';

  @override
  String get courierDetails => 'Courier details';

  @override
  String get courierDetailsHint =>
      'Enter courier and tracking details. Suggestions appear as you type.';

  @override
  String get courierHint => 'Type or pick from suggestions';

  @override
  String get trackingNumber => 'Tracking number';

  @override
  String get deliveryProofLocked =>
      'Delivery proof uploaded — courier details are locked.';

  @override
  String shipmentProgress(int current, int total) {
    return 'Shipment $current of $total';
  }

  @override
  String get markShipped => 'Mark shipped';

  @override
  String get deliveryHandoffHint =>
      'When the courier collects the shipment, upload the signed delivery note and mark it shipped.';

  @override
  String get name => 'Name';

  @override
  String get back => 'Back';

  @override
  String get no => 'No';

  @override
  String get product => 'Product';

  @override
  String get quantity => 'Quantity';

  @override
  String get notes => 'Notes';

  @override
  String get phone => 'Phone';

  @override
  String get contact => 'Contact';

  @override
  String get sector => 'Sector';

  @override
  String qtyTimes(String qty, String price) {
    return 'Qty $qty × $price';
  }

  @override
  String get packShipment => 'Pack shipment';

  @override
  String packOrder(String order) {
    return 'Pack $order';
  }

  @override
  String get manualBarcode => 'Manual barcode';

  @override
  String get nextConfirmBoxes => 'Next — confirm boxes';

  @override
  String get confirmBoxes => 'Confirm boxes';

  @override
  String get finishPacking => 'Finish packing';

  @override
  String get products => 'Products';

  @override
  String get boxes => 'Boxes';

  @override
  String expectedBoxes(String qty, int count) {
    return 'Qty $qty · Expected boxes $count';
  }

  @override
  String get deliveryLocation => 'Delivery location';

  @override
  String get orderChannel => 'Order channel';

  @override
  String get poNumber => 'PO number';

  @override
  String get poDate => 'PO date (YYYY-MM-DD)';

  @override
  String get paymentTerms => 'Payment terms';

  @override
  String get shippingFee => 'Shipping fee';

  @override
  String get paymentProofDetails => 'Payment proof details';

  @override
  String get amount => 'Amount';

  @override
  String get transferDate => 'Transfer date';

  @override
  String get transferredToAccount => 'Transferred to account';

  @override
  String get saveAndUploadProof => 'Save & upload proof';

  @override
  String get orderConfirmation => 'Order confirmation';

  @override
  String get rejectedSection => 'Rejected';

  @override
  String get deliveryCompleteEmail => 'Delivery complete email';

  @override
  String get invoice => 'Invoice';

  @override
  String get assignLinesHint =>
      'Assign all lines to stores, then confirm allocation to approve this order.';

  @override
  String get assignLinesHintStaged =>
      'Assign lines to stores. Green store chips can fully fulfill pending quantities; orange can fulfill some.';

  @override
  String get stageForStore => 'Stage for store';

  @override
  String get assignPendingQty => 'Assign pending qty';

  @override
  String get sendDeliveryCompleteEmail => 'Send delivery complete email';

  @override
  String get resendDeliveryCompleteEmail => 'Resend delivery complete email';

  @override
  String get sendInvoiceEmail => 'Send invoice email';

  @override
  String get resendInvoiceEmail => 'Resend invoice email';

  @override
  String get skipReasonRequired => 'A reason is required to skip this email';

  @override
  String get shipmentsAfterAssignment =>
      'Shipments will appear here after store assignment.';

  @override
  String get todayPosRevenue => 'Today POS revenue';

  @override
  String get lowStockItems => 'Low stock items';

  @override
  String get pendingRestocks => 'Pending restocks';

  @override
  String get pendingWholesaleOrders => 'Pending wholesale orders';

  @override
  String get companyName => 'Company name';

  @override
  String get address => 'Address';

  @override
  String get city => 'City';

  @override
  String get postcode => 'Postcode';

  @override
  String get telephone => 'Telephone';

  @override
  String get email => 'Email';

  @override
  String get paymentInfo => 'Payment info';

  @override
  String get shipmentCouriersField => 'Shipment couriers';

  @override
  String get deviceCode => 'Device code';

  @override
  String get deviceName => 'Device name';

  @override
  String get currencyCode => 'Currency code';

  @override
  String get rateToGbp => 'Rate to GBP';

  @override
  String get addCurrencyRate => 'Add currency rate';

  @override
  String rateLabel(String rate) {
    return 'Rate: $rate';
  }

  @override
  String get adjustStock => 'Adjust stock';

  @override
  String adjustStockTitle(String name) {
    return 'Adjust $name';
  }

  @override
  String get reason => 'Reason';

  @override
  String get searchProducts => 'Search products';

  @override
  String get firstName => 'First name';

  @override
  String get lastName => 'Last name';

  @override
  String get newPasswordOptional => 'New password (optional)';

  @override
  String get rolePosUser => 'POS user';

  @override
  String locationsCount(int count) {
    return '$count locations';
  }

  @override
  String storeNumber(int id) {
    return 'Store #$id';
  }

  @override
  String restockNumber(int id) {
    return 'Restock #$id';
  }

  @override
  String get selectCourier => 'Select a courier';

  @override
  String get selectAtLeastOneShipment => 'Select at least one shipment';

  @override
  String get noCouriersConfigured =>
      'No couriers configured in company settings.';

  @override
  String get selectOrders => 'Select orders';

  @override
  String get scanDeliveryNote => 'Scan delivery note';

  @override
  String get confirmStep => 'Confirm';

  @override
  String noMatchingShipment(String code) {
    return 'No matching shipment for: $code';
  }

  @override
  String markedShippedVia(int count, String courier) {
    return 'Marked $count shipment(s) shipped via $courier';
  }

  @override
  String courierLabel(String name) {
    return 'Courier: $name';
  }

  @override
  String shipmentsCountLabel(int count) {
    return 'Shipments: $count';
  }

  @override
  String get more => 'More';

  @override
  String get apiServer => 'API server';

  @override
  String get environment => 'Environment';

  @override
  String get biometricUnlock => 'Biometric unlock';

  @override
  String get biometricUnlockSubtitle =>
      'Require Face ID / fingerprint on app open';

  @override
  String get startDate => 'Start date (YYYY-MM-DD)';

  @override
  String get endDate => 'End date (YYYY-MM-DD)';

  @override
  String get toStore => 'To store';

  @override
  String get stepCreated => 'Created';

  @override
  String get stepOrderConfirmation => 'Order confirmation';

  @override
  String get stepStartShipment => 'Start shipment';

  @override
  String get stepFinishShipment => 'Finish shipment';

  @override
  String get stepInvoiceEmail => 'Invoice email';

  @override
  String get stepPaymentConfirmation => 'Payment confirmation';

  @override
  String get stepComplete => 'Complete';

  @override
  String get total => 'Total';

  @override
  String get ref => 'Ref';

  @override
  String get channel => 'Channel';

  @override
  String get rejection => 'Rejection';

  @override
  String get unassigned => 'Unassigned';

  @override
  String qtyAssigned(String qty, String assigned) {
    return 'Qty $qty · Assigned $assigned';
  }

  @override
  String get staged => 'staged';

  @override
  String get newUser => 'New user';

  @override
  String get editUser => 'Edit user';

  @override
  String get staff => 'Staff';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get discount => 'Discount';

  @override
  String get posOrder => 'POS order';

  @override
  String get confirmAllocationApprove => 'Confirm allocation & approve';

  @override
  String get confirmAllocation => 'Confirm allocation';

  @override
  String get allLinesAssigned => 'All lines are assigned to stores.';

  @override
  String get changeAssignmentWhilePacking =>
      'You can change assignments while shipments are still in assign/pack stage.';

  @override
  String get orderConfirmationEmail => 'Order confirmation email';

  @override
  String get sendOrderConfirmationEmail => 'Send order confirmation email';

  @override
  String get resendOrderConfirmationEmail => 'Resend order confirmation email';

  @override
  String get paymentConfirmationSection => 'Payment confirmation';

  @override
  String get actionNeeded => 'Action needed';

  @override
  String get forceComplete => 'Force complete';

  @override
  String get next => 'Next';

  @override
  String get confirmPickup => 'Confirm pickup';

  @override
  String get scanHint => 'Order #, PO, ref…';

  @override
  String selectedOrder(String order) {
    return 'Selected $order';
  }

  @override
  String totalBoxes(int count) {
    return 'Total boxes: $count';
  }

  @override
  String get saveChanges => 'Save changes';

  @override
  String get createUser => 'Create user';

  @override
  String get required => 'Required';

  @override
  String get send => 'Send';

  @override
  String get toField => 'To';

  @override
  String get ccField => 'Cc';

  @override
  String get bccField => 'Bcc';

  @override
  String get subjectField => 'Subject';

  @override
  String get messageField => 'Message';

  @override
  String get attachments => 'Attachments';

  @override
  String get focusMode => 'Focus';

  @override
  String get focusModeTooltip => 'Focus mode — screen stays on while scanning';

  @override
  String get scanStep => '1/2 Scan';

  @override
  String get boxesStep => '2/2 Boxes';

  @override
  String needQtyBoxes(String qty, String boxes) {
    return 'Need $qty · Boxes $boxes';
  }

  @override
  String get turnPhoneNext => 'Turn or move phone to the next product';

  @override
  String get phoneTurnedNext => 'Phone turned toward next item';

  @override
  String get pauseComplete => 'Pause complete';

  @override
  String pauseForSeconds(int seconds) {
    return 'Pause for ${seconds}s while you move';
  }

  @override
  String reasonPrefix(String reason) {
    return 'Reason: $reason';
  }

  @override
  String skippedAt(String date) {
    return 'Skipped at $date';
  }

  @override
  String skippedBy(String name) {
    return 'Skipped by $name';
  }

  @override
  String previouslySentAt(String date) {
    return 'Previously sent at $date';
  }

  @override
  String get noPaymentProof => 'No payment proof';

  @override
  String get forceConfirmPayment => 'Force confirm payment';

  @override
  String get noPaymentProofWarning =>
      'No payment proof has been uploaded. Are you sure you want to confirm without proof?';

  @override
  String get forceConfirmWarning =>
      'This will mark payment as received without matching the uploaded proof total. Only use if you are certain payment is complete.';

  @override
  String get confirmPaymentQuestion =>
      'Confirm that payment has been received for this order?';

  @override
  String get proofShortfallHint =>
      'Proof total is below order total. No further uploads are allowed once payment is confirmed.';

  @override
  String get snackSelectStore => 'Select a store';

  @override
  String get snackShipmentPacked =>
      'That store shipment is already packed or shipped';

  @override
  String get snackLineStaged => 'Line staged for assignment';

  @override
  String get snackDefaultStaged =>
      'Default allocation staged — confirm when ready';

  @override
  String get snackAssignAllLines => 'Assign all lines before confirming';

  @override
  String get snackOrderApproved => 'Order approved and assigned';

  @override
  String get snackAllocationConfirmedContinue =>
      'Allocation confirmed — send order confirmation email or skip to continue';

  @override
  String get snackAssignmentRemoved => 'Assignment removed';

  @override
  String get snackAssignmentMoved => 'Assignment moved';

  @override
  String get snackPaymentProofUploaded => 'Payment proof uploaded';

  @override
  String get snackPaymentProofAutoConfirmed =>
      'Payment proof uploaded. Payment was automatically confirmed.';

  @override
  String get lineAssigned => 'Line assigned';

  @override
  String get assignedByDefaults => 'Assigned by defaults';

  @override
  String get orderResubmitted => 'Order resubmitted';

  @override
  String get orderConfirmationRegenerated => 'Order confirmation regenerated';

  @override
  String get invoiceGenerated => 'Invoice generated';

  @override
  String qtyLabel(String qty) {
    return 'Qty $qty';
  }

  @override
  String filesSelected(int count) {
    return '$count file(s) selected';
  }

  @override
  String get enterValidAmount => 'Enter a valid amount';

  @override
  String get selectTransferDate => 'Select a transfer date';

  @override
  String get selectDestinationAccount => 'Select the destination account';

  @override
  String get role => 'Role';

  @override
  String get newClient => 'New client';

  @override
  String get editClient => 'Edit client';

  @override
  String get findNextItemToScan => 'Find the next item to scan';

  @override
  String get active => 'Active';

  @override
  String get inactive => 'Inactive';

  @override
  String get po => 'PO';

  @override
  String get resend => 'Resend';

  @override
  String get resendEmail => 'Resend email';

  @override
  String get sendOrderConfirmationEmailDescription =>
      'Send the order confirmation email with attachments to the client.';

  @override
  String get sendDeliveryCompleteEmailDescription =>
      'Send the delivery complete email with signed delivery notes.';

  @override
  String get sendInvoiceEmailDescription =>
      'Send the invoice email with invoice and optional delivery documents.';

  @override
  String get emailRecipientsRequired =>
      'At least one recipient email is required';

  @override
  String invalidEmailAddress(String email) {
    return 'Invalid email: $email';
  }

  @override
  String get selectAtLeastOneAttachment => 'Select at least one attachment';

  @override
  String get sendSkippedEmailNow =>
      'You can send this email now even though it was skipped before.';

  @override
  String attachmentsList(String list) {
    return 'Attachments: $list';
  }

  @override
  String filesList(String list) {
    return 'Files: $list';
  }

  @override
  String get invoiceDeliveryDocsOptional =>
      'Delivery note and delivery proof are optional for invoice emails.';

  @override
  String get emailRecipientsHint => 'email@example.com, another@example.com';

  @override
  String paymentProofNumber(int id) {
    return 'Payment proof #$id';
  }

  @override
  String get productNotFound => 'Product not found';

  @override
  String productNotFoundDetail(String code) {
    return 'Barcode \"$code\" does not match any item on this shipment.';
  }

  @override
  String get quantityAlreadyComplete => 'Quantity already complete';

  @override
  String quantityAlreadyCompleteDetail(
    String product,
    String scanned,
    String expected,
  ) {
    return '$product is fully scanned ($scanned/$expected). Scan a different item.';
  }

  @override
  String scanProgress(String product, String scanned, String expected) {
    return '$product: $scanned / $expected';
  }

  @override
  String get biometricEnableReason =>
      'Enable biometric unlock for POS Management';

  @override
  String get biometricUnlockReason => 'Unlock POS Management';

  @override
  String get restockStatusInitiated => 'Initiated';

  @override
  String get restockStatusInTransit => 'In transit';

  @override
  String get restockStatusReceived => 'Received';

  @override
  String get markedShippedSnack => 'Marked shipped';

  @override
  String get shipmentMarkedAwaitProof =>
      'Shipment is marked shipped. Upload the signed delivery note when you receive it.';
}
