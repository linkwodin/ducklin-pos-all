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
    Locale('zh', 'TW'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'POS Management'**
  String get appTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your management account'**
  String get loginSubtitle;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Username required'**
  String get usernameRequired;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password required'**
  String get passwordRequired;

  /// No description provided for @useBiometricNextTime.
  ///
  /// In en, this message translates to:
  /// **'Use {label} next time'**
  String useBiometricNextTime(String label);

  /// No description provided for @biometricUnlockHint.
  ///
  /// In en, this message translates to:
  /// **'Unlock the app without typing your password'**
  String get biometricUnlockHint;

  /// No description provided for @unlockWithBiometric.
  ///
  /// In en, this message translates to:
  /// **'Unlock with {label}'**
  String unlockWithBiometric(String label);

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checking;

  /// No description provided for @usePasswordInstead.
  ///
  /// In en, this message translates to:
  /// **'Use password instead'**
  String get usePasswordInstead;

  /// No description provided for @biometricFailed.
  ///
  /// In en, this message translates to:
  /// **'{label} authentication failed'**
  String biometricFailed(String label);

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get logoutConfirm;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @store.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get store;

  /// No description provided for @client.
  ///
  /// In en, this message translates to:
  /// **'Client'**
  String get client;

  /// No description provided for @created.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get created;

  /// No description provided for @courier.
  ///
  /// In en, this message translates to:
  /// **'Courier'**
  String get courier;

  /// No description provided for @tracking.
  ///
  /// In en, this message translates to:
  /// **'Tracking'**
  String get tracking;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get items;

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @shipments.
  ///
  /// In en, this message translates to:
  /// **'Shipments'**
  String get shipments;

  /// No description provided for @process.
  ///
  /// In en, this message translates to:
  /// **'Process'**
  String get process;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChineseTraditional.
  ///
  /// In en, this message translates to:
  /// **'繁體中文'**
  String get languageChineseTraditional;

  /// No description provided for @languageChineseSimplified.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageChineseSimplified;

  /// No description provided for @menuDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get menuDashboard;

  /// No description provided for @menuReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get menuReports;

  /// No description provided for @menuProductsGroup.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get menuProductsGroup;

  /// No description provided for @menuProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get menuProducts;

  /// No description provided for @menuCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get menuCategories;

  /// No description provided for @menuSectors.
  ///
  /// In en, this message translates to:
  /// **'Sectors'**
  String get menuSectors;

  /// No description provided for @menuInventoryGroup.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get menuInventoryGroup;

  /// No description provided for @menuStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get menuStock;

  /// No description provided for @menuRestock.
  ///
  /// In en, this message translates to:
  /// **'Restock orders'**
  String get menuRestock;

  /// No description provided for @menuPosOrders.
  ///
  /// In en, this message translates to:
  /// **'POS orders'**
  String get menuPosOrders;

  /// No description provided for @menuWholesaleGroup.
  ///
  /// In en, this message translates to:
  /// **'Wholesale'**
  String get menuWholesaleGroup;

  /// No description provided for @menuWholesaleOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get menuWholesaleOrders;

  /// No description provided for @menuShipments.
  ///
  /// In en, this message translates to:
  /// **'Shipments'**
  String get menuShipments;

  /// No description provided for @menuWholesaleClients.
  ///
  /// In en, this message translates to:
  /// **'Clients'**
  String get menuWholesaleClients;

  /// No description provided for @menuSettingsGroup.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get menuSettingsGroup;

  /// No description provided for @menuUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get menuUsers;

  /// No description provided for @menuStores.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get menuStores;

  /// No description provided for @menuDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get menuDevices;

  /// No description provided for @menuCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency rates'**
  String get menuCurrency;

  /// No description provided for @menuCompany.
  ///
  /// In en, this message translates to:
  /// **'Company settings'**
  String get menuCompany;

  /// No description provided for @management.
  ///
  /// In en, this message translates to:
  /// **'Management'**
  String get management;

  /// No description provided for @roleManagement.
  ///
  /// In en, this message translates to:
  /// **'Management'**
  String get roleManagement;

  /// No description provided for @roleHQStaff.
  String get roleHQStaff;

  /// No description provided for @roleSupervisor.
  ///
  /// In en, this message translates to:
  /// **'Supervisor'**
  String get roleSupervisor;

  /// No description provided for @roleCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get roleCashier;

  /// No description provided for @roleStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get roleStaff;

  /// No description provided for @searchOrderPoClient.
  ///
  /// In en, this message translates to:
  /// **'Search order, PO, client…'**
  String get searchOrderPoClient;

  /// No description provided for @tabDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get tabDashboard;

  /// No description provided for @tabList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get tabList;

  /// No description provided for @nothingHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get nothingHere;

  /// No description provided for @shipmentUpdated.
  ///
  /// In en, this message translates to:
  /// **'Shipment updated'**
  String get shipmentUpdated;

  /// No description provided for @shipmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Shipment'**
  String get shipmentTitle;

  /// No description provided for @shipmentNumber.
  ///
  /// In en, this message translates to:
  /// **'Shipment #{id}'**
  String shipmentNumber(int id);

  /// No description provided for @boxesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} boxes'**
  String boxesCount(int count);

  /// No description provided for @monitorPacking.
  ///
  /// In en, this message translates to:
  /// **'Packing'**
  String get monitorPacking;

  /// No description provided for @monitorPackedAwaitingCourier.
  ///
  /// In en, this message translates to:
  /// **'Packed — awaiting courier'**
  String get monitorPackedAwaitingCourier;

  /// No description provided for @monitorShipped.
  ///
  /// In en, this message translates to:
  /// **'Shipped'**
  String get monitorShipped;

  /// No description provided for @monitorCompletedRecent.
  ///
  /// In en, this message translates to:
  /// **'Completed (recent)'**
  String get monitorCompletedRecent;

  /// No description provided for @batchPack.
  ///
  /// In en, this message translates to:
  /// **'Batch pack'**
  String get batchPack;

  /// No description provided for @courierPickup.
  ///
  /// In en, this message translates to:
  /// **'Courier pickup'**
  String get courierPickup;

  /// No description provided for @workflowPickPack.
  ///
  /// In en, this message translates to:
  /// **'Pick & pack'**
  String get workflowPickPack;

  /// No description provided for @workflowPickPackSub.
  ///
  /// In en, this message translates to:
  /// **'Scan items and confirm box counts'**
  String get workflowPickPackSub;

  /// No description provided for @workflowCourier.
  ///
  /// In en, this message translates to:
  /// **'Courier details'**
  String get workflowCourier;

  /// No description provided for @workflowCourierSub.
  ///
  /// In en, this message translates to:
  /// **'Courier, tracking number, and delivery date'**
  String get workflowCourierSub;

  /// No description provided for @workflowHandoff.
  ///
  /// In en, this message translates to:
  /// **'Delivery handoff'**
  String get workflowHandoff;

  /// No description provided for @workflowHandoffUploaded.
  ///
  /// In en, this message translates to:
  /// **'Signed delivery note uploaded'**
  String get workflowHandoffUploaded;

  /// No description provided for @workflowHandoffUploadShipped.
  ///
  /// In en, this message translates to:
  /// **'Upload signed delivery note'**
  String get workflowHandoffUploadShipped;

  /// No description provided for @workflowHandoffUploadAndShip.
  ///
  /// In en, this message translates to:
  /// **'Upload signed delivery note and mark shipped'**
  String get workflowHandoffUploadAndShip;

  /// No description provided for @saveDetails.
  ///
  /// In en, this message translates to:
  /// **'Save details'**
  String get saveDetails;

  /// No description provided for @batchPacking.
  ///
  /// In en, this message translates to:
  /// **'Batch packing'**
  String get batchPacking;

  /// No description provided for @packingQueueComplete.
  ///
  /// In en, this message translates to:
  /// **'Packing queue complete'**
  String get packingQueueComplete;

  /// No description provided for @noShipmentsInQueue.
  ///
  /// In en, this message translates to:
  /// **'No shipments left in queue'**
  String get noShipmentsInQueue;

  /// No description provided for @skipThisShipment.
  ///
  /// In en, this message translates to:
  /// **'Skip this shipment'**
  String get skipThisShipment;

  /// No description provided for @startPacking.
  ///
  /// In en, this message translates to:
  /// **'Start packing'**
  String get startPacking;

  /// No description provided for @shipmentStatusAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get shipmentStatusAssigned;

  /// No description provided for @shipmentStatusPacking.
  ///
  /// In en, this message translates to:
  /// **'Packing'**
  String get shipmentStatusPacking;

  /// No description provided for @shipmentStatusPacked.
  ///
  /// In en, this message translates to:
  /// **'Packed'**
  String get shipmentStatusPacked;

  /// No description provided for @shipmentStatusShipped.
  ///
  /// In en, this message translates to:
  /// **'Shipped'**
  String get shipmentStatusShipped;

  /// No description provided for @shipmentStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get shipmentStatusCompleted;

  /// No description provided for @filterPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get filterPendingApproval;

  /// No description provided for @filterAssignShipment.
  ///
  /// In en, this message translates to:
  /// **'Assign shipment'**
  String get filterAssignShipment;

  /// No description provided for @filterAwaitingPayment.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get filterAwaitingPayment;

  /// No description provided for @filterCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get filterCompleted;

  /// No description provided for @filterRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get filterRejected;

  /// No description provided for @filterDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get filterDeleted;

  /// No description provided for @wholesaleStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get wholesaleStatusRejected;

  /// No description provided for @wholesaleStatusDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get wholesaleStatusDeleted;

  /// No description provided for @wholesaleStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get wholesaleStatusCompleted;

  /// No description provided for @wholesaleStatusPendingOrderConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Pending order confirmation'**
  String get wholesaleStatusPendingOrderConfirmation;

  /// No description provided for @wholesaleStatusPendingPacking.
  ///
  /// In en, this message translates to:
  /// **'Pending packing'**
  String get wholesaleStatusPendingPacking;

  /// No description provided for @wholesaleStatusInTransit.
  ///
  /// In en, this message translates to:
  /// **'In transit'**
  String get wholesaleStatusInTransit;

  /// No description provided for @wholesaleStatusPendingInvoice.
  ///
  /// In en, this message translates to:
  /// **'Pending invoice email'**
  String get wholesaleStatusPendingInvoice;

  /// No description provided for @wholesaleStatusPendingPayment.
  ///
  /// In en, this message translates to:
  /// **'Pending payment confirmation'**
  String get wholesaleStatusPendingPayment;

  /// No description provided for @wholesaleStatusPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get wholesaleStatusPendingApproval;

  /// No description provided for @wholesaleStatusAssignShipment.
  ///
  /// In en, this message translates to:
  /// **'Assign shipment'**
  String get wholesaleStatusAssignShipment;

  /// No description provided for @wholesaleStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get wholesaleStatusApproved;

  /// No description provided for @posFilterPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get posFilterPending;

  /// No description provided for @posFilterPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get posFilterPaid;

  /// No description provided for @posFilterPickedUp.
  ///
  /// In en, this message translates to:
  /// **'Picked up'**
  String get posFilterPickedUp;

  /// No description provided for @posFilterCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get posFilterCancelled;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get chooseFromGallery;

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get chooseFile;

  /// No description provided for @rejectOrder.
  ///
  /// In en, this message translates to:
  /// **'Reject order'**
  String get rejectOrder;

  /// No description provided for @rejectReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get rejectReason;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @noDocumentsYet.
  ///
  /// In en, this message translates to:
  /// **'No documents yet'**
  String get noDocumentsYet;

  /// No description provided for @uploadPoAttachment.
  ///
  /// In en, this message translates to:
  /// **'Upload PO attachment'**
  String get uploadPoAttachment;

  /// No description provided for @assigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get assigned;

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @emailSkipped.
  ///
  /// In en, this message translates to:
  /// **'Email skipped'**
  String get emailSkipped;

  /// No description provided for @emailSent.
  ///
  /// In en, this message translates to:
  /// **'Email sent'**
  String get emailSent;

  /// No description provided for @resubmit.
  ///
  /// In en, this message translates to:
  /// **'Resubmit'**
  String get resubmit;

  /// No description provided for @selectStore.
  ///
  /// In en, this message translates to:
  /// **'Select store'**
  String get selectStore;

  /// No description provided for @assignByDefaults.
  ///
  /// In en, this message translates to:
  /// **'Assign by defaults'**
  String get assignByDefaults;

  /// No description provided for @changeAssignment.
  ///
  /// In en, this message translates to:
  /// **'Change assignment'**
  String get changeAssignment;

  /// No description provided for @regenerateOrderConfirmationPdf.
  ///
  /// In en, this message translates to:
  /// **'Regenerate order confirmation PDF'**
  String get regenerateOrderConfirmationPdf;

  /// No description provided for @linesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String linesCount(int count);

  /// No description provided for @generateInvoice.
  ///
  /// In en, this message translates to:
  /// **'Generate invoice'**
  String get generateInvoice;

  /// No description provided for @orderTotal.
  ///
  /// In en, this message translates to:
  /// **'Order total: {amount}'**
  String orderTotal(String amount);

  /// No description provided for @proofTotal.
  ///
  /// In en, this message translates to:
  /// **'Proof total: {amount}'**
  String proofTotal(String amount);

  /// No description provided for @uploadPaymentProof.
  ///
  /// In en, this message translates to:
  /// **'Upload payment proof'**
  String get uploadPaymentProof;

  /// No description provided for @confirmPaymentReceived.
  ///
  /// In en, this message translates to:
  /// **'Confirm payment received'**
  String get confirmPaymentReceived;

  /// No description provided for @paymentConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmed'**
  String get paymentConfirmed;

  /// No description provided for @moveReassign.
  ///
  /// In en, this message translates to:
  /// **'Move / reassign'**
  String get moveReassign;

  /// No description provided for @moveFrom.
  ///
  /// In en, this message translates to:
  /// **'From {store}'**
  String moveFrom(String store);

  /// No description provided for @skipEmail.
  ///
  /// In en, this message translates to:
  /// **'Skip email'**
  String get skipEmail;

  /// No description provided for @loadReport.
  ///
  /// In en, this message translates to:
  /// **'Load report'**
  String get loadReport;

  /// No description provided for @posRevenue.
  ///
  /// In en, this message translates to:
  /// **'POS revenue'**
  String get posRevenue;

  /// No description provided for @posOrdersCount.
  ///
  /// In en, this message translates to:
  /// **'POS orders: {count}'**
  String posOrdersCount(int count);

  /// No description provided for @allStores.
  ///
  /// In en, this message translates to:
  /// **'All stores'**
  String get allStores;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get saveSettings;

  /// No description provided for @createWholesaleOrder.
  ///
  /// In en, this message translates to:
  /// **'Create wholesale order'**
  String get createWholesaleOrder;

  /// No description provided for @addAtLeastOneProduct.
  ///
  /// In en, this message translates to:
  /// **'Add at least one product'**
  String get addAtLeastOneProduct;

  /// No description provided for @companyAddress.
  ///
  /// In en, this message translates to:
  /// **'Company address'**
  String get companyAddress;

  /// No description provided for @sourceClientPo.
  ///
  /// In en, this message translates to:
  /// **'Client PO'**
  String get sourceClientPo;

  /// No description provided for @sourceWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get sourceWhatsapp;

  /// No description provided for @sourceEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get sourceEmail;

  /// No description provided for @sourceNa.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get sourceNa;

  /// No description provided for @lineItems.
  ///
  /// In en, this message translates to:
  /// **'Line items'**
  String get lineItems;

  /// No description provided for @unitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit price: {amount}'**
  String unitPrice(String amount);

  /// No description provided for @poAttachments.
  ///
  /// In en, this message translates to:
  /// **'PO attachments ({count})'**
  String poAttachments(int count);

  /// No description provided for @createOrder.
  ///
  /// In en, this message translates to:
  /// **'Create order'**
  String get createOrder;

  /// No description provided for @deliveryLocations.
  ///
  /// In en, this message translates to:
  /// **'Delivery locations'**
  String get deliveryLocations;

  /// No description provided for @auditLog.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get auditLog;

  /// No description provided for @registerDevice.
  ///
  /// In en, this message translates to:
  /// **'Register device'**
  String get registerDevice;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @newCategory.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get newCategory;

  /// No description provided for @newSector.
  ///
  /// In en, this message translates to:
  /// **'New sector'**
  String get newSector;

  /// No description provided for @newStore.
  ///
  /// In en, this message translates to:
  /// **'New store'**
  String get newStore;

  /// No description provided for @warehouse.
  ///
  /// In en, this message translates to:
  /// **'Warehouse'**
  String get warehouse;

  /// No description provided for @receive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receive;

  /// No description provided for @markPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark paid'**
  String get markPaid;

  /// No description provided for @markComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark complete'**
  String get markComplete;

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel order?'**
  String get cancelOrder;

  /// No description provided for @cancelOrderAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get cancelOrderAction;

  /// No description provided for @courierDetails.
  ///
  /// In en, this message translates to:
  /// **'Courier details'**
  String get courierDetails;

  /// No description provided for @courierDetailsHint.
  ///
  /// In en, this message translates to:
  /// **'Enter courier and tracking details. Suggestions appear as you type.'**
  String get courierDetailsHint;

  /// No description provided for @courierHint.
  ///
  /// In en, this message translates to:
  /// **'Type or pick from suggestions'**
  String get courierHint;

  /// No description provided for @trackingNumber.
  ///
  /// In en, this message translates to:
  /// **'Tracking number'**
  String get trackingNumber;

  /// No description provided for @deliveryProofLocked.
  ///
  /// In en, this message translates to:
  /// **'Delivery proof uploaded — courier details are locked.'**
  String get deliveryProofLocked;

  /// No description provided for @shipmentProgress.
  ///
  /// In en, this message translates to:
  /// **'Shipment {current} of {total}'**
  String shipmentProgress(int current, int total);

  /// No description provided for @markShipped.
  ///
  /// In en, this message translates to:
  /// **'Mark shipped'**
  String get markShipped;

  /// No description provided for @deliveryHandoffHint.
  ///
  /// In en, this message translates to:
  /// **'When the courier collects the shipment, upload the signed delivery note and mark it shipped.'**
  String get deliveryHandoffHint;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @product.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get product;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @sector.
  ///
  /// In en, this message translates to:
  /// **'Sector'**
  String get sector;

  /// No description provided for @qtyTimes.
  ///
  /// In en, this message translates to:
  /// **'Qty {qty} × {price}'**
  String qtyTimes(String qty, String price);

  /// No description provided for @packShipment.
  ///
  /// In en, this message translates to:
  /// **'Pack shipment'**
  String get packShipment;

  /// No description provided for @packOrder.
  ///
  /// In en, this message translates to:
  /// **'Pack {order}'**
  String packOrder(String order);

  /// No description provided for @manualBarcode.
  ///
  /// In en, this message translates to:
  /// **'Manual barcode'**
  String get manualBarcode;

  /// No description provided for @nextConfirmBoxes.
  ///
  /// In en, this message translates to:
  /// **'Next — confirm boxes'**
  String get nextConfirmBoxes;

  /// No description provided for @confirmBoxes.
  ///
  /// In en, this message translates to:
  /// **'Confirm boxes'**
  String get confirmBoxes;

  /// No description provided for @finishPacking.
  ///
  /// In en, this message translates to:
  /// **'Finish packing'**
  String get finishPacking;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @boxes.
  ///
  /// In en, this message translates to:
  /// **'Boxes'**
  String get boxes;

  /// No description provided for @expectedBoxes.
  ///
  /// In en, this message translates to:
  /// **'Qty {qty} · Expected boxes {count}'**
  String expectedBoxes(String qty, int count);

  /// No description provided for @deliveryLocation.
  ///
  /// In en, this message translates to:
  /// **'Delivery location'**
  String get deliveryLocation;

  /// No description provided for @orderChannel.
  ///
  /// In en, this message translates to:
  /// **'Order channel'**
  String get orderChannel;

  /// No description provided for @poNumber.
  ///
  /// In en, this message translates to:
  /// **'PO number'**
  String get poNumber;

  /// No description provided for @poDate.
  ///
  /// In en, this message translates to:
  /// **'PO date (YYYY-MM-DD)'**
  String get poDate;

  /// No description provided for @paymentTerms.
  ///
  /// In en, this message translates to:
  /// **'Payment terms'**
  String get paymentTerms;

  /// No description provided for @shippingFee.
  ///
  /// In en, this message translates to:
  /// **'Shipping fee'**
  String get shippingFee;

  /// No description provided for @paymentProofDetails.
  ///
  /// In en, this message translates to:
  /// **'Payment proof details'**
  String get paymentProofDetails;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @transferDate.
  ///
  /// In en, this message translates to:
  /// **'Transfer date'**
  String get transferDate;

  /// No description provided for @transferredToAccount.
  ///
  /// In en, this message translates to:
  /// **'Transferred to account'**
  String get transferredToAccount;

  /// No description provided for @saveAndUploadProof.
  ///
  /// In en, this message translates to:
  /// **'Save & upload proof'**
  String get saveAndUploadProof;

  /// No description provided for @orderConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Order confirmation'**
  String get orderConfirmation;

  /// No description provided for @rejectedSection.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejectedSection;

  /// No description provided for @deliveryCompleteEmail.
  ///
  /// In en, this message translates to:
  /// **'Delivery complete email'**
  String get deliveryCompleteEmail;

  /// No description provided for @invoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get invoice;

  /// No description provided for @assignLinesHint.
  ///
  /// In en, this message translates to:
  /// **'Assign all lines to stores, then confirm allocation to approve this order.'**
  String get assignLinesHint;

  /// No description provided for @assignLinesHintStaged.
  ///
  /// In en, this message translates to:
  /// **'Assign lines to stores. Green store chips can fully fulfill pending quantities; orange can fulfill some.'**
  String get assignLinesHintStaged;

  /// No description provided for @stageForStore.
  ///
  /// In en, this message translates to:
  /// **'Stage for store'**
  String get stageForStore;

  /// No description provided for @assignPendingQty.
  ///
  /// In en, this message translates to:
  /// **'Assign pending qty'**
  String get assignPendingQty;

  /// No description provided for @sendDeliveryCompleteEmail.
  ///
  /// In en, this message translates to:
  /// **'Send delivery complete email'**
  String get sendDeliveryCompleteEmail;

  /// No description provided for @resendDeliveryCompleteEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend delivery complete email'**
  String get resendDeliveryCompleteEmail;

  /// No description provided for @sendInvoiceEmail.
  ///
  /// In en, this message translates to:
  /// **'Send invoice email'**
  String get sendInvoiceEmail;

  /// No description provided for @resendInvoiceEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend invoice email'**
  String get resendInvoiceEmail;

  /// No description provided for @skipReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'A reason is required to skip this email'**
  String get skipReasonRequired;

  /// No description provided for @shipmentsAfterAssignment.
  ///
  /// In en, this message translates to:
  /// **'Shipments will appear here after store assignment.'**
  String get shipmentsAfterAssignment;

  /// No description provided for @todayPosRevenue.
  ///
  /// In en, this message translates to:
  /// **'Today POS revenue'**
  String get todayPosRevenue;

  /// No description provided for @lowStockItems.
  ///
  /// In en, this message translates to:
  /// **'Low stock items'**
  String get lowStockItems;

  /// No description provided for @pendingRestocks.
  ///
  /// In en, this message translates to:
  /// **'Pending restocks'**
  String get pendingRestocks;

  /// No description provided for @pendingWholesaleOrders.
  ///
  /// In en, this message translates to:
  /// **'Pending wholesale orders'**
  String get pendingWholesaleOrders;

  /// No description provided for @companyName.
  ///
  /// In en, this message translates to:
  /// **'Company name'**
  String get companyName;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @postcode.
  ///
  /// In en, this message translates to:
  /// **'Postcode'**
  String get postcode;

  /// No description provided for @telephone.
  ///
  /// In en, this message translates to:
  /// **'Telephone'**
  String get telephone;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @paymentInfo.
  ///
  /// In en, this message translates to:
  /// **'Payment info'**
  String get paymentInfo;

  /// No description provided for @shipmentCouriersField.
  ///
  /// In en, this message translates to:
  /// **'Shipment couriers'**
  String get shipmentCouriersField;

  /// No description provided for @deviceCode.
  ///
  /// In en, this message translates to:
  /// **'Device code'**
  String get deviceCode;

  /// No description provided for @deviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceName;

  /// No description provided for @currencyCode.
  ///
  /// In en, this message translates to:
  /// **'Currency code'**
  String get currencyCode;

  /// No description provided for @rateToGbp.
  ///
  /// In en, this message translates to:
  /// **'Rate to GBP'**
  String get rateToGbp;

  /// No description provided for @addCurrencyRate.
  ///
  /// In en, this message translates to:
  /// **'Add currency rate'**
  String get addCurrencyRate;

  /// No description provided for @rateLabel.
  ///
  /// In en, this message translates to:
  /// **'Rate: {rate}'**
  String rateLabel(String rate);

  /// No description provided for @adjustStock.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock'**
  String get adjustStock;

  /// No description provided for @adjustStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust {name}'**
  String adjustStockTitle(String name);

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// No description provided for @searchProducts.
  ///
  /// In en, this message translates to:
  /// **'Search products'**
  String get searchProducts;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get lastName;

  /// No description provided for @newPasswordOptional.
  ///
  /// In en, this message translates to:
  /// **'New password (optional)'**
  String get newPasswordOptional;

  /// No description provided for @rolePosUser.
  ///
  /// In en, this message translates to:
  /// **'POS user'**
  String get rolePosUser;

  /// No description provided for @locationsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} locations'**
  String locationsCount(int count);

  /// No description provided for @storeNumber.
  ///
  /// In en, this message translates to:
  /// **'Store #{id}'**
  String storeNumber(int id);

  /// No description provided for @restockNumber.
  ///
  /// In en, this message translates to:
  /// **'Restock #{id}'**
  String restockNumber(int id);

  /// No description provided for @selectCourier.
  ///
  /// In en, this message translates to:
  /// **'Select a courier'**
  String get selectCourier;

  /// No description provided for @selectAtLeastOneShipment.
  ///
  /// In en, this message translates to:
  /// **'Select at least one shipment'**
  String get selectAtLeastOneShipment;

  /// No description provided for @noCouriersConfigured.
  ///
  /// In en, this message translates to:
  /// **'No couriers configured in company settings.'**
  String get noCouriersConfigured;

  /// No description provided for @selectOrders.
  ///
  /// In en, this message translates to:
  /// **'Select orders'**
  String get selectOrders;

  /// No description provided for @scanDeliveryNote.
  ///
  /// In en, this message translates to:
  /// **'Scan delivery note'**
  String get scanDeliveryNote;

  /// No description provided for @confirmStep.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmStep;

  /// No description provided for @noMatchingShipment.
  ///
  /// In en, this message translates to:
  /// **'No matching shipment for: {code}'**
  String noMatchingShipment(String code);

  /// No description provided for @markedShippedVia.
  ///
  /// In en, this message translates to:
  /// **'Marked {count} shipment(s) shipped via {courier}'**
  String markedShippedVia(int count, String courier);

  /// No description provided for @courierLabel.
  ///
  /// In en, this message translates to:
  /// **'Courier: {name}'**
  String courierLabel(String name);

  /// No description provided for @shipmentsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Shipments: {count}'**
  String shipmentsCountLabel(int count);

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @apiServer.
  ///
  /// In en, this message translates to:
  /// **'API server'**
  String get apiServer;

  /// No description provided for @environment.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get environment;

  /// No description provided for @biometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get biometricUnlock;

  /// No description provided for @biometricUnlockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Require Face ID / fingerprint on app open'**
  String get biometricUnlockSubtitle;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Start date (YYYY-MM-DD)'**
  String get startDate;

  /// No description provided for @endDate.
  ///
  /// In en, this message translates to:
  /// **'End date (YYYY-MM-DD)'**
  String get endDate;

  /// No description provided for @toStore.
  ///
  /// In en, this message translates to:
  /// **'To store'**
  String get toStore;

  /// No description provided for @stepCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get stepCreated;

  /// No description provided for @stepOrderConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Order confirmation'**
  String get stepOrderConfirmation;

  /// No description provided for @stepStartShipment.
  ///
  /// In en, this message translates to:
  /// **'Start shipment'**
  String get stepStartShipment;

  /// No description provided for @stepFinishShipment.
  ///
  /// In en, this message translates to:
  /// **'Finish shipment'**
  String get stepFinishShipment;

  /// No description provided for @stepInvoiceEmail.
  ///
  /// In en, this message translates to:
  /// **'Invoice email'**
  String get stepInvoiceEmail;

  /// No description provided for @stepPaymentConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmation'**
  String get stepPaymentConfirmation;

  /// No description provided for @stepComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get stepComplete;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @ref.
  ///
  /// In en, this message translates to:
  /// **'Ref'**
  String get ref;

  /// No description provided for @channel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get channel;

  /// No description provided for @rejection.
  ///
  /// In en, this message translates to:
  /// **'Rejection'**
  String get rejection;

  /// No description provided for @unassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get unassigned;

  /// No description provided for @qtyAssigned.
  ///
  /// In en, this message translates to:
  /// **'Qty {qty} · Assigned {assigned}'**
  String qtyAssigned(String qty, String assigned);

  /// No description provided for @staged.
  ///
  /// In en, this message translates to:
  /// **'staged'**
  String get staged;

  /// No description provided for @newUser.
  ///
  /// In en, this message translates to:
  /// **'New user'**
  String get newUser;

  /// No description provided for @editUser.
  ///
  /// In en, this message translates to:
  /// **'Edit user'**
  String get editUser;

  /// No description provided for @staff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staff;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @posOrder.
  ///
  /// In en, this message translates to:
  /// **'POS order'**
  String get posOrder;

  /// No description provided for @confirmAllocationApprove.
  ///
  /// In en, this message translates to:
  /// **'Confirm allocation & approve'**
  String get confirmAllocationApprove;

  /// No description provided for @confirmAllocation.
  ///
  /// In en, this message translates to:
  /// **'Confirm allocation'**
  String get confirmAllocation;

  /// No description provided for @allLinesAssigned.
  ///
  /// In en, this message translates to:
  /// **'All lines are assigned to stores.'**
  String get allLinesAssigned;

  /// No description provided for @changeAssignmentWhilePacking.
  ///
  /// In en, this message translates to:
  /// **'You can change assignments while shipments are still in assign/pack stage.'**
  String get changeAssignmentWhilePacking;

  /// No description provided for @orderConfirmationEmail.
  ///
  /// In en, this message translates to:
  /// **'Order confirmation email'**
  String get orderConfirmationEmail;

  /// No description provided for @sendOrderConfirmationEmail.
  ///
  /// In en, this message translates to:
  /// **'Send order confirmation email'**
  String get sendOrderConfirmationEmail;

  /// No description provided for @resendOrderConfirmationEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend order confirmation email'**
  String get resendOrderConfirmationEmail;

  /// No description provided for @paymentConfirmationSection.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmation'**
  String get paymentConfirmationSection;

  /// No description provided for @actionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Action needed'**
  String get actionNeeded;

  /// No description provided for @forceComplete.
  ///
  /// In en, this message translates to:
  /// **'Force complete'**
  String get forceComplete;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @confirmPickup.
  ///
  /// In en, this message translates to:
  /// **'Confirm pickup'**
  String get confirmPickup;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Order #, PO, ref…'**
  String get scanHint;

  /// No description provided for @selectedOrder.
  ///
  /// In en, this message translates to:
  /// **'Selected {order}'**
  String selectedOrder(String order);

  /// No description provided for @totalBoxes.
  ///
  /// In en, this message translates to:
  /// **'Total boxes: {count}'**
  String totalBoxes(int count);

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @createUser.
  ///
  /// In en, this message translates to:
  /// **'Create user'**
  String get createUser;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @toField.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get toField;

  /// No description provided for @ccField.
  ///
  /// In en, this message translates to:
  /// **'Cc'**
  String get ccField;

  /// No description provided for @bccField.
  ///
  /// In en, this message translates to:
  /// **'Bcc'**
  String get bccField;

  /// No description provided for @subjectField.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get subjectField;

  /// No description provided for @messageField.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageField;

  /// No description provided for @attachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments;

  /// No description provided for @focusMode.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get focusMode;

  /// No description provided for @focusModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Focus mode — screen stays on while scanning'**
  String get focusModeTooltip;

  /// No description provided for @scanStep.
  ///
  /// In en, this message translates to:
  /// **'1/2 Scan'**
  String get scanStep;

  /// No description provided for @boxesStep.
  ///
  /// In en, this message translates to:
  /// **'2/2 Boxes'**
  String get boxesStep;

  /// No description provided for @needQtyBoxes.
  ///
  /// In en, this message translates to:
  /// **'Need {qty} · Boxes {boxes}'**
  String needQtyBoxes(String qty, String boxes);

  /// No description provided for @turnPhoneNext.
  ///
  /// In en, this message translates to:
  /// **'Turn or move phone to the next product'**
  String get turnPhoneNext;

  /// No description provided for @phoneTurnedNext.
  ///
  /// In en, this message translates to:
  /// **'Phone turned toward next item'**
  String get phoneTurnedNext;

  /// No description provided for @pauseComplete.
  ///
  /// In en, this message translates to:
  /// **'Pause complete'**
  String get pauseComplete;

  /// No description provided for @pauseForSeconds.
  ///
  /// In en, this message translates to:
  /// **'Pause for {seconds}s while you move'**
  String pauseForSeconds(int seconds);

  /// No description provided for @reasonPrefix.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String reasonPrefix(String reason);

  /// No description provided for @skippedAt.
  ///
  /// In en, this message translates to:
  /// **'Skipped at {date}'**
  String skippedAt(String date);

  /// No description provided for @skippedBy.
  ///
  /// In en, this message translates to:
  /// **'Skipped by {name}'**
  String skippedBy(String name);

  /// No description provided for @previouslySentAt.
  ///
  /// In en, this message translates to:
  /// **'Previously sent at {date}'**
  String previouslySentAt(String date);

  /// No description provided for @noPaymentProof.
  ///
  /// In en, this message translates to:
  /// **'No payment proof'**
  String get noPaymentProof;

  /// No description provided for @forceConfirmPayment.
  ///
  /// In en, this message translates to:
  /// **'Force confirm payment'**
  String get forceConfirmPayment;

  /// No description provided for @noPaymentProofWarning.
  ///
  /// In en, this message translates to:
  /// **'No payment proof has been uploaded. Are you sure you want to confirm without proof?'**
  String get noPaymentProofWarning;

  /// No description provided for @forceConfirmWarning.
  ///
  /// In en, this message translates to:
  /// **'This will mark payment as received without matching the uploaded proof total. Only use if you are certain payment is complete.'**
  String get forceConfirmWarning;

  /// No description provided for @confirmPaymentQuestion.
  ///
  /// In en, this message translates to:
  /// **'Confirm that payment has been received for this order?'**
  String get confirmPaymentQuestion;

  /// No description provided for @proofShortfallHint.
  ///
  /// In en, this message translates to:
  /// **'Proof total is below order total. No further uploads are allowed once payment is confirmed.'**
  String get proofShortfallHint;

  /// No description provided for @snackSelectStore.
  ///
  /// In en, this message translates to:
  /// **'Select a store'**
  String get snackSelectStore;

  /// No description provided for @snackShipmentPacked.
  ///
  /// In en, this message translates to:
  /// **'That store shipment is already packed or shipped'**
  String get snackShipmentPacked;

  /// No description provided for @snackLineStaged.
  ///
  /// In en, this message translates to:
  /// **'Line staged for assignment'**
  String get snackLineStaged;

  /// No description provided for @snackDefaultStaged.
  ///
  /// In en, this message translates to:
  /// **'Default allocation staged — confirm when ready'**
  String get snackDefaultStaged;

  /// No description provided for @snackAssignAllLines.
  ///
  /// In en, this message translates to:
  /// **'Assign all lines before confirming'**
  String get snackAssignAllLines;

  /// No description provided for @snackOrderApproved.
  ///
  /// In en, this message translates to:
  /// **'Order approved and assigned'**
  String get snackOrderApproved;

  /// No description provided for @snackAllocationConfirmedContinue.
  ///
  /// In en, this message translates to:
  /// **'Allocation confirmed — send order confirmation email or skip to continue'**
  String get snackAllocationConfirmedContinue;

  /// No description provided for @snackAssignmentRemoved.
  ///
  /// In en, this message translates to:
  /// **'Assignment removed'**
  String get snackAssignmentRemoved;

  /// No description provided for @snackAssignmentMoved.
  ///
  /// In en, this message translates to:
  /// **'Assignment moved'**
  String get snackAssignmentMoved;

  /// No description provided for @snackPaymentProofUploaded.
  ///
  /// In en, this message translates to:
  /// **'Payment proof uploaded'**
  String get snackPaymentProofUploaded;

  /// No description provided for @snackPaymentProofAutoConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Payment proof uploaded. Payment was automatically confirmed.'**
  String get snackPaymentProofAutoConfirmed;

  /// No description provided for @lineAssigned.
  ///
  /// In en, this message translates to:
  /// **'Line assigned'**
  String get lineAssigned;

  /// No description provided for @assignedByDefaults.
  ///
  /// In en, this message translates to:
  /// **'Assigned by defaults'**
  String get assignedByDefaults;

  /// No description provided for @orderResubmitted.
  ///
  /// In en, this message translates to:
  /// **'Order resubmitted'**
  String get orderResubmitted;

  /// No description provided for @orderConfirmationRegenerated.
  ///
  /// In en, this message translates to:
  /// **'Order confirmation regenerated'**
  String get orderConfirmationRegenerated;

  /// No description provided for @invoiceGenerated.
  ///
  /// In en, this message translates to:
  /// **'Invoice generated'**
  String get invoiceGenerated;

  /// No description provided for @qtyLabel.
  ///
  /// In en, this message translates to:
  /// **'Qty {qty}'**
  String qtyLabel(String qty);

  /// No description provided for @filesSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) selected'**
  String filesSelected(int count);

  /// No description provided for @enterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get enterValidAmount;

  /// No description provided for @selectTransferDate.
  ///
  /// In en, this message translates to:
  /// **'Select a transfer date'**
  String get selectTransferDate;

  /// No description provided for @selectDestinationAccount.
  ///
  /// In en, this message translates to:
  /// **'Select the destination account'**
  String get selectDestinationAccount;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @newClient.
  ///
  /// In en, this message translates to:
  /// **'New client'**
  String get newClient;

  /// No description provided for @editClient.
  ///
  /// In en, this message translates to:
  /// **'Edit client'**
  String get editClient;

  /// No description provided for @findNextItemToScan.
  ///
  /// In en, this message translates to:
  /// **'Find the next item to scan'**
  String get findNextItemToScan;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @po.
  ///
  /// In en, this message translates to:
  /// **'PO'**
  String get po;

  /// No description provided for @resend.
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get resend;

  /// No description provided for @resendEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend email'**
  String get resendEmail;

  /// No description provided for @sendOrderConfirmationEmailDescription.
  ///
  /// In en, this message translates to:
  /// **'Send the order confirmation email with attachments to the client.'**
  String get sendOrderConfirmationEmailDescription;

  /// No description provided for @sendDeliveryCompleteEmailDescription.
  ///
  /// In en, this message translates to:
  /// **'Send the delivery complete email with signed delivery notes.'**
  String get sendDeliveryCompleteEmailDescription;

  /// No description provided for @sendInvoiceEmailDescription.
  ///
  /// In en, this message translates to:
  /// **'Send the invoice email with invoice and optional delivery documents.'**
  String get sendInvoiceEmailDescription;

  /// No description provided for @emailRecipientsRequired.
  ///
  /// In en, this message translates to:
  /// **'At least one recipient email is required'**
  String get emailRecipientsRequired;

  /// No description provided for @invalidEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid email: {email}'**
  String invalidEmailAddress(String email);

  /// No description provided for @selectAtLeastOneAttachment.
  ///
  /// In en, this message translates to:
  /// **'Select at least one attachment'**
  String get selectAtLeastOneAttachment;

  /// No description provided for @sendSkippedEmailNow.
  ///
  /// In en, this message translates to:
  /// **'You can send this email now even though it was skipped before.'**
  String get sendSkippedEmailNow;

  /// No description provided for @attachmentsList.
  ///
  /// In en, this message translates to:
  /// **'Attachments: {list}'**
  String attachmentsList(String list);

  /// No description provided for @filesList.
  ///
  /// In en, this message translates to:
  /// **'Files: {list}'**
  String filesList(String list);

  /// No description provided for @invoiceDeliveryDocsOptional.
  ///
  /// In en, this message translates to:
  /// **'Delivery note and delivery proof are optional for invoice emails.'**
  String get invoiceDeliveryDocsOptional;

  /// No description provided for @emailRecipientsHint.
  ///
  /// In en, this message translates to:
  /// **'email@example.com, another@example.com'**
  String get emailRecipientsHint;

  /// No description provided for @paymentProofNumber.
  ///
  /// In en, this message translates to:
  /// **'Payment proof #{id}'**
  String paymentProofNumber(int id);

  /// No description provided for @productNotFound.
  ///
  /// In en, this message translates to:
  /// **'Product not found'**
  String get productNotFound;

  /// No description provided for @productNotFoundDetail.
  ///
  /// In en, this message translates to:
  /// **'Barcode \"{code}\" does not match any item on this shipment.'**
  String productNotFoundDetail(String code);

  /// No description provided for @quantityAlreadyComplete.
  ///
  /// In en, this message translates to:
  /// **'Quantity already complete'**
  String get quantityAlreadyComplete;

  /// No description provided for @quantityAlreadyCompleteDetail.
  ///
  /// In en, this message translates to:
  /// **'{product} is fully scanned ({scanned}/{expected}). Scan a different item.'**
  String quantityAlreadyCompleteDetail(
    String product,
    String scanned,
    String expected,
  );

  /// No description provided for @scanProgress.
  ///
  /// In en, this message translates to:
  /// **'{product}: {scanned} / {expected}'**
  String scanProgress(String product, String scanned, String expected);

  /// No description provided for @biometricEnableReason.
  ///
  /// In en, this message translates to:
  /// **'Enable biometric unlock for POS Management'**
  String get biometricEnableReason;

  /// No description provided for @biometricUnlockReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock POS Management'**
  String get biometricUnlockReason;

  /// No description provided for @restockStatusInitiated.
  ///
  /// In en, this message translates to:
  /// **'Initiated'**
  String get restockStatusInitiated;

  /// No description provided for @restockStatusInTransit.
  ///
  /// In en, this message translates to:
  /// **'In transit'**
  String get restockStatusInTransit;

  /// No description provided for @restockStatusReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get restockStatusReceived;

  /// No description provided for @markedShippedSnack.
  ///
  /// In en, this message translates to:
  /// **'Marked shipped'**
  String get markedShippedSnack;

  /// No description provided for @shipmentMarkedAwaitProof.
  ///
  /// In en, this message translates to:
  /// **'Shipment is marked shipped. Upload the signed delivery note when you receive it.'**
  String get shipmentMarkedAwaitProof;
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
    'that was used.',
  );
}
