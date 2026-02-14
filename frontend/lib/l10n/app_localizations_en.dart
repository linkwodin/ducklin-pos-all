// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'POS System';

  @override
  String get loginTitle => '德靈公司 POS v1.0';

  @override
  String get enterPIN => 'Enter PIN';

  @override
  String get signIn => 'Sign In';

  @override
  String get signingIn => 'Signing in...';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get email => 'Email';

  @override
  String get pin => 'PIN';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get update => 'Update';

  @override
  String get close => 'Close';

  @override
  String get error => 'Error';

  @override
  String get confirm => 'Confirm';

  @override
  String get search => 'Search';

  @override
  String get loading => 'Loading...';

  @override
  String get noData => 'No data found';

  @override
  String get sync => 'Sync';

  @override
  String get syncUsers => 'Sync Users';

  @override
  String get syncing => 'Syncing...';

  @override
  String get syncScreenTitle => 'Sync';

  @override
  String get syncPendingOrders => 'Pending orders';

  @override
  String get syncPendingStocktakes => 'Pending stocktakes';

  @override
  String get syncNoPendingItems => 'No pending items. All data is synced.';

  @override
  String get fullSyncTitle => 'Full Sync';

  @override
  String get fullSyncUsers => 'Sync users';

  @override
  String get fullSyncProducts => 'Sync products';

  @override
  String get fullSyncProductImages => 'Sync product images';

  @override
  String get fullSyncOrders => 'Sync orders';

  @override
  String get fullSyncInventory => 'Sync inventory';

  @override
  String get loginWithUsernamePassword => 'Login with Username/Password';

  @override
  String get noUsersAvailable => 'No users available';

  @override
  String get pleaseSyncWithServerFirst => 'Please sync with server first';

  @override
  String get invalidPIN => 'Invalid PIN';

  @override
  String get loginFailed => 'Login failed';

  @override
  String pinMustBeDigits(int count) {
    return 'PIN must be exactly $count digits';
  }

  @override
  String get newOrder => 'New Order';

  @override
  String get searchOrder => 'Search Order';

  @override
  String get inventory => 'Inventory';

  @override
  String get userManagement => 'User Management';

  @override
  String get report => 'Report';

  @override
  String get settings => 'Settings';

  @override
  String get logout => 'Logout';

  @override
  String get areYouSureLogout => 'Are you sure you want to logout?';

  @override
  String get dataSyncedSuccessfully => 'Data synced successfully';

  @override
  String get searchProducts => 'Search products by name, barcode, or SKU...';

  @override
  String noProductsFound(String query) {
    return 'No products found for \"$query\"';
  }

  @override
  String noProductsInCategory(String category) {
    return 'No products in category \"$category\"';
  }

  @override
  String get noProductsAvailable => 'No products available';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get scanBarcode => 'Scan Barcode';

  @override
  String get addedToCart => 'Added to cart';

  @override
  String addedWeightToCart(double weight) {
    return 'Added ${weight}g to cart';
  }

  @override
  String productAddedToCart(String name) {
    return 'Product \"$name\" added to cart';
  }

  @override
  String get enterWeight => 'Enter Weight';

  @override
  String get weightG => 'Weight (g)';

  @override
  String get quantity => 'Quantity';

  @override
  String get inventoryManagement => 'Inventory Management';

  @override
  String get currentStock => 'Current Stock';

  @override
  String get incomingStock => 'Incoming Stock';

  @override
  String storeID(int id) {
    return 'Store ID: $id';
  }

  @override
  String get noInventoryData => 'No inventory data available';

  @override
  String get noIncomingStockOrders => 'No incoming stock orders';

  @override
  String updateStock(String name) {
    return 'Update Stock: $name';
  }

  @override
  String get reasonOptional => 'Reason (optional)';

  @override
  String get reasonPlaceholder => 'e.g., manual adjustment, received stock';

  @override
  String get stockUpdatedSuccessfully => 'Stock updated successfully';

  @override
  String failedToUpdateStock(String error) {
    return 'Failed to update stock: $error';
  }

  @override
  String get confirmReceipt => 'Confirm Receipt';

  @override
  String get confirmReceiptMessage =>
      'Are you sure you want to confirm that this stock has arrived? This will update the inventory quantities.';

  @override
  String get stockReceiptConfirmed => 'Stock receipt confirmed successfully';

  @override
  String failedToConfirmReceipt(String error) {
    return 'Failed to confirm receipt: $error';
  }

  @override
  String get orderHistory => 'Order History';

  @override
  String get searchByOrderTotalDate => 'Search by Order #, Total, or Date';

  @override
  String get noOrdersFound => 'No orders found';

  @override
  String orderNumberHash(String number) {
    return 'Order #$number';
  }

  @override
  String orderNumber(String number) {
    return 'Order #: $number';
  }

  @override
  String date(String date) {
    return 'Date: $date';
  }

  @override
  String viewReceipt(String number) {
    return 'View receipt for Order #$number';
  }

  @override
  String get comingSoon => 'Coming Soon';

  @override
  String get inventoryManagementComingSoon =>
      'Inventory Management (Coming Soon)';

  @override
  String get userManagementComingSoon => 'User Management (Coming Soon)';

  @override
  String get reportsComingSoon => 'Reports (Coming Soon)';

  @override
  String get reportToday => 'Today\'s Sales';

  @override
  String get reportTotalSales => 'Total Sales';

  @override
  String get reportSoldProducts => 'Sold Products';

  @override
  String get reportLoading => 'Loading report...';

  @override
  String get reportError => 'Failed to load report';

  @override
  String get reportNoSalesToday => 'No sales today';

  @override
  String get reportQuantity => 'Qty';

  @override
  String get reportRevenue => 'Revenue';

  @override
  String get reportTodayCommission => 'Today Commission';

  @override
  String get stocktakeDiscrepancyTitle => 'Stock difference';

  @override
  String get stocktakeDiscrepancyMessage =>
      'The following items differ from system record. Please provide a reason for the adjustment.';

  @override
  String get stocktakeReasonHint => 'Reason';

  @override
  String get stocktakeRemarkHint => 'Remarks';

  @override
  String get stocktakeSavedOffline =>
      'Stocktake saved locally. Will sync when online.';

  @override
  String get stocktakeDayStartTitle => 'Day start stocktake';

  @override
  String get stocktakeDayStartMessage =>
      'Please do day start stocktake on first login.';

  @override
  String get stocktakeDayEndTitle => 'Day end stocktake';

  @override
  String get stocktakeDayEndMessage =>
      'Please do day end stocktake before logout.';

  @override
  String get stocktakeDoIt => 'Do stocktake';

  @override
  String get stocktakeSkip => 'Skip';

  @override
  String get stocktakeSkipReasonHint => 'Reason for skipping (required)';

  @override
  String get stocktakeSkippedNotificationShort => 'Stocktake skipped';

  @override
  String get stocktakePendingMessage =>
      'Day start stocktake required today. Tap to open.';

  @override
  String get all => 'All';

  @override
  String get product => 'Product';

  @override
  String get store => 'Store';

  @override
  String qty(String quantity) {
    return 'Qty: $quantity';
  }

  @override
  String weightDisplay(String weight) {
    return '${weight}g';
  }

  @override
  String syncedUsers(int count) {
    return 'Synced $count user(s) successfully';
  }

  @override
  String get noUsersFoundForDevice =>
      'No users found for this device on the server.';

  @override
  String syncFailed(String error) {
    return 'Sync failed: $error';
  }

  @override
  String get deviceCodeNotAvailable =>
      'Device code not available. Please register device first.';

  @override
  String get refresh => 'Refresh';

  @override
  String get checkout => 'Checkout';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get discount => 'Discount';

  @override
  String get total => 'Total';

  @override
  String get processPayment => 'Process Payment';

  @override
  String get orderReceipt => '貨品細明 Pickup Receipt';

  @override
  String get print => 'Print';

  @override
  String get printInternalAuditNote => 'Print Audit Note';

  @override
  String get printInvoice => 'Order Clip (Loon Fung copy)';

  @override
  String get printCustomerCounterfoil => 'Order Clip (Ducklin copy)';

  @override
  String get printCustomerReceipt => '貨品細明 Pickup Receipt';

  @override
  String get printAll => 'Print All';

  @override
  String get markPaid => 'Mark Paid';

  @override
  String get orderCreatedSuccessfully => 'Order created successfully';

  @override
  String get storeNotSelected => 'Store not selected';

  @override
  String get userNotAuthenticated => 'User not authenticated';

  @override
  String get status => 'Status';

  @override
  String get reprint => 'Reprint';

  @override
  String get tracking => 'Tracking';

  @override
  String get unknownProduct => 'Unknown Product';

  @override
  String get language => 'Language';

  @override
  String get printerSettings => 'Printer Settings';

  @override
  String get connectionType => 'Connection Type';

  @override
  String get network => 'Network';

  @override
  String get bluetooth => 'Bluetooth';

  @override
  String get usb => 'USB';

  @override
  String get networkSettings => 'Network Settings';

  @override
  String get bluetoothSettings => 'Bluetooth Settings';

  @override
  String get usbSettings => 'USB Settings';

  @override
  String get printerIPAddress => 'Printer IP Address';

  @override
  String get printerPort => 'Port';

  @override
  String get usbSerialPort => 'USB Serial Port';

  @override
  String get usbSerialPortHint =>
      'e.g., /dev/tty.usbserial-* or /dev/cu.usbserial-*';

  @override
  String get scanDevices => 'Scan Devices';

  @override
  String get scanning => 'Scanning...';

  @override
  String get noBluetoothDevicesFound => 'No Bluetooth devices found';

  @override
  String get testPrinter => 'Test Printer';

  @override
  String get saveSettings => 'Save Settings';

  @override
  String get settingsSavedSuccessfully => 'Settings saved successfully';

  @override
  String get noUsbPrintersFound =>
      'No USB printers found. Make sure your printer is connected.';

  @override
  String get orderPickup => 'Order Pickup';

  @override
  String get scanOrderQRCode => 'Scan Order QR Code';

  @override
  String get scanQRCodeToConfirmPickup =>
      'Scan a QR code to confirm the pickup';

  @override
  String get enterItManually => 'Enter it manually';

  @override
  String get enterOrderNumber => 'Enter Order Number';

  @override
  String get scanOrEnterOrderNumber => 'Scan QR code or enter order number';

  @override
  String get useBarcodeScannerOrTypeManually =>
      'Use a barcode scanner or type the order number manually';

  @override
  String get orderDetails => 'Order Details';

  @override
  String get orderInformation => 'Order Information';

  @override
  String get orderItems => 'Order Items';

  @override
  String get createdAt => 'Created At';

  @override
  String get paidAt => 'Paid At';

  @override
  String get completedAt => 'Completed At';

  @override
  String get pickedUpAt => 'Picked Up At';

  @override
  String get printReceipts => 'Print Receipts';

  @override
  String get noItemsFound => 'No items found';

  @override
  String get confirmPickup => 'Confirm Pickup';

  @override
  String get ok => 'OK';

  @override
  String get orderNumberLabel => 'Order number';

  @override
  String get tapToEnterOrderNumber => 'Tap to enter order number';

  @override
  String get editOrderNumber => 'Edit order number';

  @override
  String get pickupInvoice => 'Invoice';

  @override
  String get pickupReceipt => 'Receipt';

  @override
  String get invoiceCheckCodeLabel => 'Invoice check code';

  @override
  String get receiptCheckCodeLabel => 'Receipt check code';

  @override
  String get tapToSetInvoiceCheckCode => 'Tap to set invoice check code';

  @override
  String get tapToSetReceiptCheckCode => 'Tap to set receipt check code';

  @override
  String orderPickedUp(String number) {
    return 'Order #$number picked up';
  }

  @override
  String get alreadyPickedUp => 'Already picked up';

  @override
  String scanOtherQRFromOrder(String type) {
    return 'Scan the $type QR from this order';
  }

  @override
  String get orderNumbersDontMatch =>
      'Order numbers don\'t match. Scan both QRs from the same order.';

  @override
  String get invalidQRFormatInvoice =>
      'Invoice QR code should contain |. Please enter check code manually or scan again.';

  @override
  String get invalidQRFormatReceipt =>
      'Receipt QR code should contain |. Please enter check code manually or scan again.';

  @override
  String get useKeyboardInput => 'Use Keyboard Input';

  @override
  String get useCameraScanner => 'Use Camera Scanner';

  @override
  String get cancelOrder => 'Cancel Order';

  @override
  String get cancelOrderConfirmation =>
      'Are you sure you want to cancel this order?';

  @override
  String get profile => 'Profile';

  @override
  String get userInfo => 'User Information';

  @override
  String get firstName => 'First Name';

  @override
  String get lastName => 'Last Name';

  @override
  String get role => 'Role';

  @override
  String get profileIcon => 'Profile Icon';

  @override
  String get changeIcon => 'Change Icon';

  @override
  String get changePIN => 'Change PIN';

  @override
  String get pinInfo => 'Enter your current PIN and a new PIN to change it.';

  @override
  String get currentPIN => 'Current PIN';

  @override
  String get currentPINRequired => 'Current PIN is required';

  @override
  String get newPIN => 'New PIN';

  @override
  String get newPINRequired => 'New PIN is required';

  @override
  String get confirmPIN => 'Confirm New PIN';

  @override
  String get pinMismatch => 'PINs do not match';

  @override
  String get pinMinLength => 'PIN must be at least 4 characters';

  @override
  String get pinUpdated => 'PIN updated successfully';

  @override
  String get iconUpdated => 'Icon updated successfully';

  @override
  String get generateFromColors => 'Generate from Colors';

  @override
  String get uploadImage => 'Upload Image';

  @override
  String get backgroundColor => 'Background Color';

  @override
  String get textColor => 'Text Color';

  @override
  String get selectImage => 'Select Image';

  @override
  String get updatePIN => 'Update PIN';

  @override
  String get configureDevice => 'Configure Device';

  @override
  String get deviceId => 'Device ID';

  @override
  String get copyDeviceId => 'Copy';

  @override
  String get deviceIdCopied => 'Device ID copied to clipboard';

  @override
  String get addDeviceToStore => 'Add device to store';

  @override
  String get selectStore => 'Select store';

  @override
  String get saveDeviceStore => 'Save';

  @override
  String get deviceConfiguredSuccessfully => 'Device configured successfully';

  @override
  String get onlyManagementCanConfigure =>
      'Only management users can configure the device.';
}
