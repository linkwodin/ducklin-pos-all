import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'CN'),
    Locale('zh', 'TW')
  ];

  /// The title of the application
  ///
  /// In en, this message translates to:
  /// **'POS System'**
  String get appTitle;

  /// The title shown on the login screen
  ///
  /// In en, this message translates to:
  /// **'德靈公司 POS v1.0'**
  String get loginTitle;

  /// Title for PIN entry screen
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get enterPIN;

  /// Sign in button text
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// Signing in loading text
  ///
  /// In en, this message translates to:
  /// **'Signing in...'**
  String get signingIn;

  /// Username label
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// Password label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// PIN label
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get pin;

  /// Cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Save button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Delete button
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Edit button
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Add button
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Update button
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// Close button
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Error title
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Confirm button
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Search placeholder
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Loading text
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No data message
  ///
  /// In en, this message translates to:
  /// **'No data found'**
  String get noData;

  /// Sync button
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// Sync users button
  ///
  /// In en, this message translates to:
  /// **'Sync Users'**
  String get syncUsers;

  /// Syncing text
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// Login with username/password button
  ///
  /// In en, this message translates to:
  /// **'Login with Username/Password'**
  String get loginWithUsernamePassword;

  /// No users message
  ///
  /// In en, this message translates to:
  /// **'No users available'**
  String get noUsersAvailable;

  /// Message to sync with server
  ///
  /// In en, this message translates to:
  /// **'Please sync with server first'**
  String get pleaseSyncWithServerFirst;

  /// Invalid PIN error
  ///
  /// In en, this message translates to:
  /// **'Invalid PIN'**
  String get invalidPIN;

  /// Login failed error
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginFailed;

  /// PIN validation message
  ///
  /// In en, this message translates to:
  /// **'PIN must be exactly {count} digits'**
  String pinMustBeDigits(int count);

  /// New order navigation item
  ///
  /// In en, this message translates to:
  /// **'New Order'**
  String get newOrder;

  /// Search order navigation item
  ///
  /// In en, this message translates to:
  /// **'Search Order'**
  String get searchOrder;

  /// Inventory navigation item
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventory;

  /// User management navigation item
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get userManagement;

  /// Report navigation item
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// Settings navigation item
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Logout button
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// Logout confirmation
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get areYouSureLogout;

  /// Data sync success message
  ///
  /// In en, this message translates to:
  /// **'Data synced successfully'**
  String get dataSyncedSuccessfully;

  /// Product search placeholder
  ///
  /// In en, this message translates to:
  /// **'Search products by name, barcode, or SKU...'**
  String get searchProducts;

  /// No products found message
  ///
  /// In en, this message translates to:
  /// **'No products found for \"{query}\"'**
  String noProductsFound(String query);

  /// No products in category message
  ///
  /// In en, this message translates to:
  /// **'No products in category \"{category}\"'**
  String noProductsInCategory(String category);

  /// No products available message
  ///
  /// In en, this message translates to:
  /// **'No products available'**
  String get noProductsAvailable;

  /// Clear filters button
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// Scan barcode button
  ///
  /// In en, this message translates to:
  /// **'Scan Barcode'**
  String get scanBarcode;

  /// Added to cart message
  ///
  /// In en, this message translates to:
  /// **'Added to cart'**
  String get addedToCart;

  /// Added weight to cart message
  ///
  /// In en, this message translates to:
  /// **'Added {weight}g to cart'**
  String addedWeightToCart(double weight);

  /// Product added to cart message
  ///
  /// In en, this message translates to:
  /// **'Product \"{name}\" added to cart'**
  String productAddedToCart(String name);

  /// Enter weight dialog title
  ///
  /// In en, this message translates to:
  /// **'Enter Weight'**
  String get enterWeight;

  /// Weight label
  ///
  /// In en, this message translates to:
  /// **'Weight (g)'**
  String get weightG;

  /// Quantity label
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// Inventory management title
  ///
  /// In en, this message translates to:
  /// **'Inventory Management'**
  String get inventoryManagement;

  /// Current stock tab
  ///
  /// In en, this message translates to:
  /// **'Current Stock'**
  String get currentStock;

  /// Incoming stock tab
  ///
  /// In en, this message translates to:
  /// **'Incoming Stock'**
  String get incomingStock;

  /// Store ID label
  ///
  /// In en, this message translates to:
  /// **'Store ID: {id}'**
  String storeID(int id);

  /// No inventory data message
  ///
  /// In en, this message translates to:
  /// **'No inventory data available'**
  String get noInventoryData;

  /// No incoming stock orders message
  ///
  /// In en, this message translates to:
  /// **'No incoming stock orders'**
  String get noIncomingStockOrders;

  /// Update stock dialog title
  ///
  /// In en, this message translates to:
  /// **'Update Stock: {name}'**
  String updateStock(String name);

  /// Reason field label
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get reasonOptional;

  /// Reason placeholder
  ///
  /// In en, this message translates to:
  /// **'e.g., manual adjustment, received stock'**
  String get reasonPlaceholder;

  /// Stock updated success message
  ///
  /// In en, this message translates to:
  /// **'Stock updated successfully'**
  String get stockUpdatedSuccessfully;

  /// Stock update error message
  ///
  /// In en, this message translates to:
  /// **'Failed to update stock: {error}'**
  String failedToUpdateStock(String error);

  /// Confirm receipt dialog title
  ///
  /// In en, this message translates to:
  /// **'Confirm Receipt'**
  String get confirmReceipt;

  /// Confirm receipt message
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to confirm that this stock has arrived? This will update the inventory quantities.'**
  String get confirmReceiptMessage;

  /// Stock receipt confirmed message
  ///
  /// In en, this message translates to:
  /// **'Stock receipt confirmed successfully'**
  String get stockReceiptConfirmed;

  /// Failed to confirm receipt error
  ///
  /// In en, this message translates to:
  /// **'Failed to confirm receipt: {error}'**
  String failedToConfirmReceipt(String error);

  /// Order history title
  ///
  /// In en, this message translates to:
  /// **'Order History'**
  String get orderHistory;

  /// Order search placeholder
  ///
  /// In en, this message translates to:
  /// **'Search by Order #, Total, or Date'**
  String get searchByOrderTotalDate;

  /// No orders found message
  ///
  /// In en, this message translates to:
  /// **'No orders found'**
  String get noOrdersFound;

  /// Order number display
  ///
  /// In en, this message translates to:
  /// **'Order #{number}'**
  String orderNumberHash(String number);

  /// Order number label
  ///
  /// In en, this message translates to:
  /// **'Order #: {number}'**
  String orderNumber(String number);

  /// Date label
  ///
  /// In en, this message translates to:
  /// **'Date: {date}'**
  String date(String date);

  /// View receipt message
  ///
  /// In en, this message translates to:
  /// **'View receipt for Order #{number}'**
  String viewReceipt(String number);

  /// Coming soon message
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get comingSoon;

  /// Inventory management coming soon
  ///
  /// In en, this message translates to:
  /// **'Inventory Management (Coming Soon)'**
  String get inventoryManagementComingSoon;

  /// User management coming soon
  ///
  /// In en, this message translates to:
  /// **'User Management (Coming Soon)'**
  String get userManagementComingSoon;

  /// Reports coming soon
  ///
  /// In en, this message translates to:
  /// **'Reports (Coming Soon)'**
  String get reportsComingSoon;

  /// All filter option
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// Product label
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get product;

  /// Store label
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get store;

  /// Quantity display
  ///
  /// In en, this message translates to:
  /// **'Qty: {quantity}'**
  String qty(String quantity);

  /// Weight display
  ///
  /// In en, this message translates to:
  /// **'{weight}g'**
  String weightDisplay(String weight);

  /// Synced users message
  ///
  /// In en, this message translates to:
  /// **'Synced {count} user(s) successfully'**
  String syncedUsers(int count);

  /// No users found for device message
  ///
  /// In en, this message translates to:
  /// **'No users found for this device on the server.'**
  String get noUsersFoundForDevice;

  /// Sync failed message
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncFailed(String error);

  /// Device code not available message
  ///
  /// In en, this message translates to:
  /// **'Device code not available. Please register device first.'**
  String get deviceCodeNotAvailable;

  /// Refresh button
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Checkout button
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout;

  /// Subtotal label
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// Discount label
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// Total label
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// Process payment button
  ///
  /// In en, this message translates to:
  /// **'Process Payment'**
  String get processPayment;

  /// Order receipt title
  ///
  /// In en, this message translates to:
  /// **'Order Receipt'**
  String get orderReceipt;

  /// Print button
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get print;

  /// Print internal audit note button
  ///
  /// In en, this message translates to:
  /// **'Print Internal Audit Note'**
  String get printInternalAuditNote;

  /// Print invoice button
  ///
  /// In en, this message translates to:
  /// **'Print Invoice'**
  String get printInvoice;

  /// Print customer receipt button
  ///
  /// In en, this message translates to:
  /// **'Print Customer Receipt'**
  String get printCustomerReceipt;

  /// Print all receipts button
  ///
  /// In en, this message translates to:
  /// **'Print All'**
  String get printAll;

  /// Mark paid button
  ///
  /// In en, this message translates to:
  /// **'Mark Paid'**
  String get markPaid;

  /// Order created success message
  ///
  /// In en, this message translates to:
  /// **'Order created successfully'**
  String get orderCreatedSuccessfully;

  /// Store not selected error
  ///
  /// In en, this message translates to:
  /// **'Store not selected'**
  String get storeNotSelected;

  /// User not authenticated error
  ///
  /// In en, this message translates to:
  /// **'User not authenticated'**
  String get userNotAuthenticated;

  /// Status label
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// Reprint button
  ///
  /// In en, this message translates to:
  /// **'Reprint'**
  String get reprint;

  /// Tracking label
  ///
  /// In en, this message translates to:
  /// **'Tracking'**
  String get tracking;

  /// Unknown product label
  ///
  /// In en, this message translates to:
  /// **'Unknown Product'**
  String get unknownProduct;

  /// Language button label
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Printer settings title
  ///
  /// In en, this message translates to:
  /// **'Printer Settings'**
  String get printerSettings;

  /// Connection type label
  ///
  /// In en, this message translates to:
  /// **'Connection Type'**
  String get connectionType;

  /// Network connection type
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// Bluetooth connection type
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get bluetooth;

  /// USB connection type
  ///
  /// In en, this message translates to:
  /// **'USB'**
  String get usb;

  /// Network settings title
  ///
  /// In en, this message translates to:
  /// **'Network Settings'**
  String get networkSettings;

  /// Bluetooth settings title
  ///
  /// In en, this message translates to:
  /// **'Bluetooth Settings'**
  String get bluetoothSettings;

  /// USB settings title
  ///
  /// In en, this message translates to:
  /// **'USB Settings'**
  String get usbSettings;

  /// Printer IP address label
  ///
  /// In en, this message translates to:
  /// **'Printer IP Address'**
  String get printerIPAddress;

  /// Printer port label
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get printerPort;

  /// USB serial port label
  ///
  /// In en, this message translates to:
  /// **'USB Serial Port'**
  String get usbSerialPort;

  /// USB serial port hint
  ///
  /// In en, this message translates to:
  /// **'e.g., /dev/tty.usbserial-* or /dev/cu.usbserial-*'**
  String get usbSerialPortHint;

  /// Scan devices button
  ///
  /// In en, this message translates to:
  /// **'Scan Devices'**
  String get scanDevices;

  /// Scanning text
  ///
  /// In en, this message translates to:
  /// **'Scanning...'**
  String get scanning;

  /// No Bluetooth devices found message
  ///
  /// In en, this message translates to:
  /// **'No Bluetooth devices found'**
  String get noBluetoothDevicesFound;

  /// Test printer button
  ///
  /// In en, this message translates to:
  /// **'Test Printer'**
  String get testPrinter;

  /// Save settings button
  ///
  /// In en, this message translates to:
  /// **'Save Settings'**
  String get saveSettings;

  /// Settings saved success message
  ///
  /// In en, this message translates to:
  /// **'Settings saved successfully'**
  String get settingsSavedSuccessfully;

  /// No USB printers found message
  ///
  /// In en, this message translates to:
  /// **'No USB printers found. Make sure your printer is connected.'**
  String get noUsbPrintersFound;

  /// Order pickup screen title
  ///
  /// In en, this message translates to:
  /// **'Order Pickup'**
  String get orderPickup;

  /// Scan order QR code title
  ///
  /// In en, this message translates to:
  /// **'Scan Order QR Code'**
  String get scanOrderQRCode;

  /// Instructions for scanning QR code
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on the invoice to confirm order pickup'**
  String get scanQRCodeToConfirmPickup;

  /// Label for order number input field
  ///
  /// In en, this message translates to:
  /// **'Enter Order Number'**
  String get enterOrderNumber;

  /// Placeholder for order number input
  ///
  /// In en, this message translates to:
  /// **'Scan QR code or enter order number'**
  String get scanOrEnterOrderNumber;

  /// Instructions for using barcode scanner or manual input
  ///
  /// In en, this message translates to:
  /// **'Use a barcode scanner or type the order number manually'**
  String get useBarcodeScannerOrTypeManually;

  /// Title for order details screen
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get orderDetails;

  /// Section title for order information
  ///
  /// In en, this message translates to:
  /// **'Order Information'**
  String get orderInformation;

  /// Section title for order items
  ///
  /// In en, this message translates to:
  /// **'Order Items'**
  String get orderItems;

  /// Label for order creation date/time
  ///
  /// In en, this message translates to:
  /// **'Created At'**
  String get createdAt;

  /// Label for order payment date/time
  ///
  /// In en, this message translates to:
  /// **'Paid At'**
  String get paidAt;

  /// Label for order completion date/time
  ///
  /// In en, this message translates to:
  /// **'Completed At'**
  String get completedAt;

  /// Label for order pickup date/time
  ///
  /// In en, this message translates to:
  /// **'Picked Up At'**
  String get pickedUpAt;

  /// Section title for print receipts buttons
  ///
  /// In en, this message translates to:
  /// **'Print Receipts'**
  String get printReceipts;

  /// Message when no order items are found
  ///
  /// In en, this message translates to:
  /// **'No items found'**
  String get noItemsFound;

  /// Button to confirm order pickup
  ///
  /// In en, this message translates to:
  /// **'Confirm Pickup'**
  String get confirmPickup;

  /// Button to cancel an order
  ///
  /// In en, this message translates to:
  /// **'Cancel Order'**
  String get cancelOrder;

  /// Confirmation message for cancelling an order
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to cancel this order?'**
  String get cancelOrderConfirmation;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
