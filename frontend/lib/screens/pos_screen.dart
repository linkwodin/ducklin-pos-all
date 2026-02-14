import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/product_provider.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/sync_status_provider.dart';
import '../providers/notification_bar_provider.dart';
import '../providers/stocktake_flow_provider.dart';
import '../providers/stocktake_status_provider.dart';
import '../services/database_service.dart';
import '../services/image_cache_service.dart';
import '../services/offline_sync_service.dart';
import '../services/api_service.dart';
import '../services/stocktake_prompt_service.dart';
import '../widgets/logo.dart';
import 'stocktake_skip_reason_screen.dart';
import 'product_selection_screen.dart';
import 'cart_screen.dart';
import 'checkout_screen.dart';
import 'order_history_screen.dart';
import 'inventory_screen.dart';
import 'stocktake_flow_screen.dart';
import 'user_management_screen.dart';
import 'report_screen.dart';
import 'login_screen.dart';
import 'order_pickup_screen.dart';
import 'user_profile_screen.dart';
import 'settings_screen.dart';
import 'full_sync_progress_screen.dart';
import 'product_selection_screen.dart' show productSelectionScreenKey;

class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  int _selectedIndex = 0;
  String? _userRole;
  double groupAlignment = -1.0;

  // Global keys to access state of screens that need refreshing
  final GlobalKey<OrderHistoryScreenState> _orderHistoryKey = GlobalKey<OrderHistoryScreenState>();
  
  // Global barcode scanner listener
  final TextEditingController _globalBarcodeController = TextEditingController();
  final FocusNode _globalBarcodeFocus = FocusNode();
  String _lastProcessedBarcode = '';
  String? _pendingBarcode; // Barcode to process after navigation
  Map<String, String>? _pendingPickupQR; // Invoice/receipt QR data to open on pickup tab
  
  bool get _showUserManagement =>
      _userRole == 'admin' || _userRole == 'management' || _userRole == 'supervisor';

  // Page index: for pos_user we have 5 nav items (Report at index 4). For admin we have 6 (UserMgmt at 4, Report at 5).
  // _pages order: [Order, Pickup, History, Inventory, Report, UserManagement]
  int get _pageIndex {
    if (_selectedIndex < 4) return _selectedIndex;
    if (_showUserManagement) return _selectedIndex == 4 ? 5 : 4; // 4->UserMgmt(5), 5->Report(4)
    return 4; // pos_user: nav index 4 = Report = _pages[4]
  }

  // List of pages for navigation: Order, Pickup, History, Inventory, Report, UserManagement
  List<Widget> get _pages => [
    OrderScreen(
      onInvoiceReceiptQRScanned: (data) {
        setState(() {
          _pendingPickupQR = data;
          _selectedIndex = 1;
        });
      },
      onQuantityDialogOpen: () {
        _globalBarcodeFocus.unfocus();
        productSelectionScreenKey.currentState?.setSearchAutofocusEnabled(false);
      },
      onQuantityDialogClose: () {
        productSelectionScreenKey.currentState?.setSearchAutofocusEnabled(true);
      },
    ),
    OrderPickupScreen(
      initialPickupQR: _pendingPickupQR,
      onPickupQRApplied: () {
        setState(() {
          _pendingPickupQR = null;
        });
      },
      onProductBarcodeScanned: (barcode) {
        // Navigate to create order page when product barcode is scanned on order pickup page
        _pendingBarcode = barcode;
        setState(() {
          _selectedIndex = 0;
        });
        // Process barcode after navigation
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pendingBarcode != null) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted && _pendingBarcode != null && productSelectionScreenKey.currentState != null) {
                productSelectionScreenKey.currentState!.processBarcode(_pendingBarcode!);
                _pendingBarcode = null;
              }
            });
          }
        });
      },
    ),
    OrderHistoryScreen(key: _orderHistoryKey),
    InventoryScreen(),
    ReportScreen(
      onTapPendingOrders: () {
        setState(() {
          _selectedIndex = 2; // Order History / Search Order tab
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _orderHistoryKey.currentState?.applyStatusFilter('pending');
          }
        });
      },
    ),
    UserManagementScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initializeData();
    _loadUserRole();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final syncStatus = Provider.of<SyncStatusProvider>(context, listen: false);
      await syncStatus.refreshPendingCount();
      final count = await DatabaseService.instance.getPendingOrdersCount();
      if (mounted && count > 0) {
        OfflineSyncService.start(() => syncStatus.refreshPendingCount());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final stocktakeStatus = Provider.of<StocktakeStatusProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      // Don't overwrite flag when we just logged in (login response already set it)
      if (authProvider.lastLoginResponse == null) {
        await stocktakeStatus.refreshFromServer();
      }
      if (!mounted) return;
      try {
        final storeId = Provider.of<OrderProvider>(context, listen: false).storeId;
        await ApiService.instance.recordStocktakeDayStart('first_login', storeId: storeId);
      } catch (_) {}
      if (!mounted) return;
      final flowProvider = Provider.of<StocktakeFlowProvider>(context, listen: false);
      if (!stocktakeStatus.hasPendingDayStartToday) {
        flowProvider.setAllowBarcodeFocus(true);
        return;
      }
      _showDayStartStocktakeDialog();
    });
  }

  void _showDayStartStocktakeDialog() {
    final l10n = AppLocalizations.of(context)!;
    final notificationProvider = Provider.of<NotificationBarProvider>(context, listen: false);
    final flowProvider = Provider.of<StocktakeFlowProvider>(context, listen: false);
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.stocktakeDayStartTitle),
        content: Text(l10n.stocktakeDayStartMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('skip'),
            child: Text(l10n.stocktakeSkip),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('do'),
            child: Text(l10n.stocktakeDoIt),
          ),
        ],
      ),
    ).then((result) async {
      if (result == 'do') {
        // User chose "Do stocktake" – push stocktake screen; on back without completing, show dialog again
        if (!mounted) return;
        final stocktakeResult = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const StocktakeFlowScreen(type: 'day_start')),
        );
        if (mounted) {
          flowProvider.setAllowBarcodeFocus(true);
          Provider.of<StocktakeStatusProvider>(context, listen: false).refresh();
          if (stocktakeResult == 'incomplete') _showDayStartStocktakeDialog();
        }
        return;
      }
      if (result != 'skip') return;
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      final reason = await StocktakeSkipReasonScreen.push(context, l10n.stocktakeSkipReasonHint);
      if (!mounted) return;
      if (reason == null) {
        _showDayStartStocktakeDialog();
        return;
      }
      if (reason.isEmpty) return;
      flowProvider.setAllowBarcodeFocus(true);
      try {
        final storeId = Provider.of<OrderProvider>(context, listen: false).storeId;
        await ApiService.instance.recordStocktakeDayStart('skipped', skipReason: reason, storeId: storeId);
      } catch (_) {}
      // Do not call recordDayStartDone() on skip — keep the reminder icon until they complete stocktake
      if (mounted) {
        await Provider.of<StocktakeStatusProvider>(context, listen: false).refresh();
      }
      final fullMessage = '${l10n.stocktakeDayStartTitle}: ${l10n.stocktakeSkippedNotificationShort}. Reason: $reason';
      notificationProvider.showPersistent(
        l10n.stocktakeSkippedNotificationShort,
        fullMessage: fullMessage,
        isError: true,
      );
    });
  }
  
  bool _shouldMaintainGlobalBarcodeFocus() {
    // Only maintain focus on screens that don't have their own barcode scanning
    // Index 0 = OrderScreen (has ProductSelectionScreen with its own barcode input)
    // Index 1 = OrderPickupScreen (has its own QR code scanning)
    // Other screens (inventory, order history, etc.) should use global listener
    return _selectedIndex != 0 && _selectedIndex != 1;
  }
  
  void _setupGlobalBarcodeListener() {
    // Focus the global barcode field after initialization (only on screens that need it)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _shouldMaintainGlobalBarcodeFocus()) {
        _globalBarcodeFocus.requestFocus();
      }
    });
  }
  
  @override
  void dispose() {
    OfflineSyncService.stop();
    _globalBarcodeController.dispose();
    _globalBarcodeFocus.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    await productProvider.loadProducts();
    // Ensure store ID is initialized
    if (orderProvider.storeId == null) {
      try {
        final deviceInfo = await DatabaseService.instance.getDeviceInfo();
        final storeId = deviceInfo?['store_id'] as int? ?? 1;
        orderProvider.setStore(storeId);
      } catch (e) {
        // Default to store ID 1
        orderProvider.setStore(1);
      }
    }
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('user_role');
    });
  }

  void _handleGlobalBarcode(String barcode) {
    // Ignore if it's the same barcode (duplicate scan)
    if (barcode == _lastProcessedBarcode) {
      return;
    }
    
    // Ignore if barcode is empty or too short (likely not a real barcode)
    if (barcode.trim().isEmpty || barcode.trim().length < 3) {
      return;
    }
    
    // If it contains pipe and is invoice/receipt QR, go to order pickup with the order
    final normalized = barcode.replaceAll('｜', '|').trim();
    if (normalized.contains('|')) {
      final parts = normalized.split('|');
      if (parts.length >= 2) {
        final orderNumber = parts[0].trim();
        final checkCode = parts[1].trim();
        final typeRaw = parts.length >= 3 ? parts[2].trim().toLowerCase() : null;
        if (orderNumber.isNotEmpty && checkCode.isNotEmpty) {
          final isInvoiceOrReceipt = typeRaw == null || typeRaw == 'invoice' || typeRaw == 'receipt';
          if (isInvoiceOrReceipt) {
            _lastProcessedBarcode = barcode;
            setState(() {
              _pendingPickupQR = {
                'orderNumber': orderNumber,
                'checkCode': checkCode,
                'receiptType': typeRaw ?? 'invoice',
              };
              _selectedIndex = 1;
            });
            _globalBarcodeController.clear();
            return;
          }
        }
      }
      return;
    }
    
    _lastProcessedBarcode = barcode;
    
    // Only process if we're NOT on the create order page
    // If we're on the create order page, let ProductSelectionScreen handle it
    if (_selectedIndex != 0) {
      // Move to create order page and release global barcode focus so
      // the order screen (and any dialogs like weight input) can manage focus.
      _pendingBarcode = barcode; // Store barcode to process after navigation
      setState(() {
        _selectedIndex = 0;
      });
      _globalBarcodeFocus.unfocus();
      
      // Clear the controller for next scan
      _globalBarcodeController.clear();
      
      // Process barcode after navigation
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pendingBarcode != null) {
          // Wait a bit for the screen to be fully built
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && _pendingBarcode != null && productSelectionScreenKey.currentState != null) {
              productSelectionScreenKey.currentState!.processBarcode(_pendingBarcode!);
              _pendingBarcode = null;
            }
          });
        }
        
        // DO NOT re-focus the global barcode field when navigating to the
        // create order page, so dialogs like weight input can grab focus.
        // Other screens will manage global focus via _shouldMaintainGlobalBarcodeFocus().
      });
    } else {
      // Already on create order page - clear the global field and let ProductSelectionScreen handle it
      _globalBarcodeController.clear();
      // Don't process here, let the ProductSelectionScreen's search field handle it
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Track user activity on any interaction
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    return Listener(
      onPointerDown: (_) => authProvider.updateLastActivity(),
      onPointerMove: (_) => authProvider.updateLastActivity(),
      child: GestureDetector(
        onTap: () => authProvider.updateLastActivity(),
        child: Stack(
          children: [
            Scaffold(
              body: Row(
                children: <Widget>[
                  NavigationRail(
                    selectedIndex: _selectedIndex,
                    extended: false, // compact to save space
                    groupAlignment: groupAlignment,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (int index) {
                      // Track activity on navigation
                      authProvider.updateLastActivity();
                      setState(() {
                        _selectedIndex = index;
                      });
                      // Refresh order history when navigating to it (index 2)
                      if (index == 2 && _orderHistoryKey.currentState != null) {
                        _orderHistoryKey.currentState!.refreshOrders();
                      }
                      // IMPORTANT: Do NOT change focus here anymore.
                      // Let each screen and dialog manage its own focus
                      // so inputs like weight and change-PIN fields work reliably.
                    },
                    leading: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: const [
                          Logo(fontSize: 12, textColor: Colors.black),
                        ],
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Consumer<SyncStatusProvider>(
                              builder: (context, syncStatus, _) {
                                return _SyncButtonWithLongPress(
                                  pendingCount: syncStatus.pendingOrdersCount + syncStatus.pendingStocktakesCount + syncStatus.pendingUserActivityEventsCount,
                                  onSync: _syncData,
                                  onFullResync: _fullResync,
                                  tooltip: l10n.sync,
                                );
                              },
                            ),
                            Text(
                              l10n.sync,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon:
                                  const Icon(Icons.language, color: Colors.grey),
                              onPressed: () {
                                _showLanguageDialog(context);
                              },
                              tooltip: l10n.language,
                            ),
                            Text(
                              l10n.language,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon:
                                  const Icon(Icons.settings, color: Colors.grey),
                              onPressed: () {
                                // When opening settings, release any barcode/search focus
                                // so text fields/dialogs on settings-related screens
                                // can receive keyboard input.
                                _globalBarcodeFocus.unfocus();
                                if (productSelectionScreenKey.currentState != null) {
                                  productSelectionScreenKey.currentState!
                                      .setSearchAutofocusEnabled(false);
                                }
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                ).then((_) async {
                                  if (!mounted) return;
                                  final should = Provider.of<StocktakeStatusProvider>(context, listen: false).hasPendingDayStartToday;
                                  if (!mounted) return;
                                  if (should) {
                                    final flowProvider = Provider.of<StocktakeFlowProvider>(context, listen: false);
                                    flowProvider.setAllowBarcodeFocus(false);
                                    _showDayStartStocktakeDialog();
                                  }
                                });
                              },
                              tooltip: l10n.settings,
                            ),
                            Text(
                              l10n.settings,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    destinations: <NavigationRailDestination>[
                      NavigationRailDestination(
                        icon: const Icon(Icons.add_box_outlined),
                        selectedIcon: const Icon(Icons.add_box_rounded),
                        label: Text(l10n.newOrder),
                      ),
                      NavigationRailDestination(
                        icon:
                            const Icon(Icons.qr_code_scanner_outlined),
                        selectedIcon: const Icon(Icons.qr_code_scanner),
                        label: Text(l10n.orderPickup ?? 'Order Pickup'),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.screen_search_desktop_outlined),
                        selectedIcon:
                            const Icon(Icons.screen_search_desktop_rounded),
                        label: Text(l10n.searchOrder),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.inventory_2_outlined),
                        selectedIcon: const Icon(Icons.inventory),
                        label: Text(l10n.inventory),
                      ),
                      if (_showUserManagement)
                        NavigationRailDestination(
                          icon: const Icon(Icons.people_alt_outlined),
                          selectedIcon: const Icon(Icons.people_alt),
                          label: Text(l10n.userManagement),
                        ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.dashboard_outlined),
                        selectedIcon: const Icon(Icons.dashboard_rounded),
                        label: Text(l10n.report),
                      ),
                    ],
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  // Main content
                  Expanded(
                    child: _pages[_pageIndex],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

      Future<void> _syncData() async {
        final l10n = AppLocalizations.of(context)!;
        final productProvider = Provider.of<ProductProvider>(context, listen: false);
        final syncStatus = Provider.of<SyncStatusProvider>(context, listen: false);
        final success = await productProvider.syncProducts();
        await OfflineSyncService.runSyncNow();
        if (mounted) syncStatus.refreshPendingCount();

        if (mounted) {
          context.showNotification(
            success ? l10n.dataSyncedSuccessfully : l10n.syncFailed('Failed to sync products'),
            isSuccess: success,
            isError: !success,
          );
        }
      }

      void _fullResync() {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FullSyncProgressScreen()),
        );
      }

      void _showLanguageDialog(BuildContext context) {
        final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
        final currentLocale = languageProvider.locale;

        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Select Language'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('English'),
                    trailing: currentLocale.languageCode == 'en'
                        ? const Icon(Icons.check, color: Colors.blue)
                        : null,
                    onTap: () {
                      languageProvider.setLanguage(const Locale('en'));
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    title: const Text('繁體中文'),
                    trailing: currentLocale.languageCode == 'zh' && currentLocale.countryCode == 'TW'
                        ? const Icon(Icons.check, color: Colors.blue)
                        : null,
                    onTap: () {
                      languageProvider.setLanguage(const Locale('zh', 'TW'));
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    title: const Text('简体中文'),
                    trailing: currentLocale.languageCode == 'zh' && currentLocale.countryCode == 'CN'
                        ? const Icon(Icons.check, color: Colors.blue)
                        : null,
                    onTap: () {
                      languageProvider.setLanguage(const Locale('zh', 'CN'));
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            );
          },
        );
      }

  void _showLogoutDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logout),
        content: Text(l10n.areYouSureLogout),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final should = await StocktakePromptService.shouldPromptDayEnd();
              if (!mounted) return;
              if (should) {
                _showDayEndStocktakeDialog();
              } else {
                _logout();
              }
            },
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }

  void _showDayEndStocktakeDialog() {
    final l10n = AppLocalizations.of(context)!;
    final notificationProvider = Provider.of<NotificationBarProvider>(context, listen: false);
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.stocktakeDayEndTitle),
        content: Text(l10n.stocktakeDayEndMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('skip'),
            child: Text(l10n.stocktakeSkip),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop('do');
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StocktakeFlowScreen(type: 'day_end')),
              );
            },
            child: Text(l10n.stocktakeDoIt),
          ),
        ],
      ),
    ).then((result) async {
      if (result != 'skip') return;
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      final reason = await StocktakeSkipReasonScreen.push(context, l10n.stocktakeSkipReasonHint);
      if (!mounted) return;
      if (reason == null) {
        _showDayEndStocktakeDialog();
        return;
      }
      if (reason.isEmpty) return;
      final storeId = Provider.of<OrderProvider>(context, listen: false).storeId;
      await ApiService.instance.recordStocktakeDayEndSkip(skipReason: reason, storeId: storeId);
      if (!mounted) return;
      final fullMessage = '${l10n.stocktakeDayEndTitle}: ${l10n.stocktakeSkippedNotificationShort}. Reason: $reason';
      notificationProvider.showPersistent(
        l10n.stocktakeSkippedNotificationShort,
        fullMessage: fullMessage,
        isError: true,
      );
      _logout();
    });
  }

  Future<void> _logout() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final notificationProvider = Provider.of<NotificationBarProvider>(context, listen: false);
    final storeId = Provider.of<OrderProvider>(context, listen: false).storeId;
    await authProvider.logout(storeId: storeId);
    notificationProvider.clear();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }
}

/// Sync button with 10-second hold for full resync; shows yellow progress bar while holding.
class _SyncButtonWithLongPress extends StatefulWidget {
  final int pendingCount;
  final VoidCallback onSync;
  final VoidCallback onFullResync;
  final String tooltip;

  const _SyncButtonWithLongPress({
    required this.pendingCount,
    required this.onSync,
    required this.onFullResync,
    required this.tooltip,
  });

  @override
  State<_SyncButtonWithLongPress> createState() => _SyncButtonWithLongPressState();
}

class _SyncButtonWithLongPressState extends State<_SyncButtonWithLongPress> {
  double _progress = 0.0;
  Timer? _timer;
  static const int _fullResyncSeconds = 5;
  static const int _tickMs = 100;
  static const double _tickStep = _tickMs / (_fullResyncSeconds * 1000);

  void _onPointerDown() {
    _timer?.cancel();
    setState(() => _progress = 0.0);
    _timer = Timer.periodic(const Duration(milliseconds: _tickMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _progress += _tickStep;
        if (_progress >= 1.0) {
          _progress = 1.0;
          t.cancel();
          // Don't trigger here; trigger on tap up so user can cancel by moving away
        }
      });
    });
  }

  void _onPointerUp() {
    _timer?.cancel();
    final progress = _progress;
    setState(() => _progress = 0.0);
    if (progress >= 1.0) {
      widget.onFullResync();
    } else if (progress < 0.02) {
      widget.onSync();
    }
    // If 0.02 <= progress < 1.0: released early, no action (user cancelled hold)
  }

  void _onPointerCancel() {
    _timer?.cancel();
    setState(() => _progress = 0.0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Badge(
          isLabelVisible: widget.pendingCount > 0,
          backgroundColor: Colors.red,
          label: Text('${widget.pendingCount}'),
          child: Listener(
            onPointerDown: (_) => _onPointerDown(),
            onPointerUp: (_) => _onPointerUp(),
            onPointerCancel: (_) => _onPointerCancel(),
            child: IconButton(
              icon: const Icon(Icons.sync, color: Colors.grey),
              onPressed: () {},
              tooltip: '${widget.tooltip} (hold 5s: full sync)',
            ),
          ),
        ),
        if (_progress > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: 48,
              height: 4,
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
              ),
            ),
          ),
      ],
    );
  }
}

// OrderScreen combines ProductSelectionScreen and CartScreen
class OrderScreen extends StatelessWidget {
  final void Function(Map<String, String>)? onInvoiceReceiptQRScanned;
  /// When the cart's update-quantity dialog opens (disable barcode autofocus).
  final VoidCallback? onQuantityDialogOpen;
  /// When the cart's update-quantity dialog closes (re-enable barcode autofocus).
  final VoidCallback? onQuantityDialogClose;

  const OrderScreen({
    super.key,
    this.onInvoiceReceiptQRScanned,
    this.onQuantityDialogOpen,
    this.onQuantityDialogClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        // Left: Product Selection (70%)
        Expanded(
          flex: 7,
          child: ProductSelectionScreen(
            key: productSelectionScreenKey,
            onInvoiceReceiptQRScanned: onInvoiceReceiptQRScanned,
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        // Right: Cart (30%)
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(
                child: CartScreen(
                  onQuantityDialogOpen: onQuantityDialogOpen,
                  onQuantityDialogClose: onQuantityDialogClose,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Consumer<OrderProvider>(
                  builder: (context, orderProvider, _) {
                    return ElevatedButton(
                      onPressed: orderProvider.cartItems.isEmpty
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        // 2x height checkout button
                        minimumSize: const Size(double.infinity, 96),
                        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                        textStyle: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: Text(l10n.checkout),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

