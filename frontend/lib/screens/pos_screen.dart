import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/product_provider.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/database_service.dart';
import '../widgets/logo.dart';
import 'product_selection_screen.dart';
import 'cart_screen.dart';
import 'checkout_screen.dart';
import 'order_history_screen.dart';
import 'inventory_screen.dart';
import 'user_management_screen.dart';
import 'report_screen.dart';
import 'login_screen.dart';
import 'printer_settings_screen.dart';
import 'order_pickup_screen.dart';
import 'user_profile_screen.dart';
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
  
  // List of pages for navigation
  List<Widget> get _pages => [
    OrderScreen(),
    OrderPickupScreen(
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
    UserManagementScreen(),
    ReportScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initializeData();
    _loadUserRole();
    _setupGlobalBarcodeListener();
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
    
    // Listen for focus changes to maintain focus (only on screens that need it)
    _globalBarcodeFocus.addListener(() {
      if (!_globalBarcodeFocus.hasFocus && mounted && _shouldMaintainGlobalBarcodeFocus()) {
        // Re-focus after a short delay to allow other interactions
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _shouldMaintainGlobalBarcodeFocus() && !_globalBarcodeFocus.hasFocus) {
            _globalBarcodeFocus.requestFocus();
          }
        });
      }
    });
  }
  
  @override
  void dispose() {
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
    
    // Ignore if it contains pipe characters (likely a QR code from order pickup, not a product barcode)
    if (barcode.contains('|') || barcode.contains('｜')) {
      return;
    }
    
    _lastProcessedBarcode = barcode;
    
    // Only process if we're NOT on the create order page
    // If we're on the create order page, let ProductSelectionScreen handle it
    if (_selectedIndex != 0) {
      _pendingBarcode = barcode; // Store barcode to process after navigation
      setState(() {
        _selectedIndex = 0;
      });
      
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
        
        // Re-focus the global barcode field after a delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _globalBarcodeFocus.requestFocus();
          }
        });
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
              // Update global barcode field focus based on current page
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  if (index == 0) {
                    // On create order page - unfocus global field to let ProductSelectionScreen handle barcodes
                    _globalBarcodeFocus.unfocus();
                  } else if (_shouldMaintainGlobalBarcodeFocus()) {
                    // On other pages (including order pickup) - focus global field to capture product barcodes
                    // On order pickup page, both fields can work: pickup page handles QR codes, global handles product barcodes
                    _globalBarcodeFocus.requestFocus();
                  }
                }
              });
            },
            groupAlignment: groupAlignment,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  const Logo(fontSize: 12, textColor: Colors.black),
                ],
              ),
            ),
            trailing: Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.sync, color: Colors.grey),
                        onPressed: _syncData,
                        tooltip: l10n.sync,
                      ),
                      Text(
                        l10n.sync,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.language, color: Colors.grey),
                        onPressed: () {
                          _showLanguageDialog(context);
                        },
                        tooltip: l10n.language,
                      ),
                      Text(
                        l10n.language,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.person, color: Colors.grey),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const UserProfileScreen(),
                            ),
                          );
                        },
                        tooltip: l10n.profile ?? 'Profile',
                      ),
                      Text(
                        l10n.profile ?? 'Profile',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.grey),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrinterSettingsScreen(),
                            ),
                          );
                        },
                        tooltip: l10n.settings,
                      ),
                      Text(
                        l10n.settings,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.grey),
                        onPressed: _showLogoutDialog,
                        tooltip: l10n.logout,
                      ),
                      Text(
                        l10n.logout,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            destinations: <NavigationRailDestination>[
              NavigationRailDestination(
                icon: const Icon(Icons.add_box_outlined),
                selectedIcon: const Icon(Icons.add_box_rounded),
                label: Text(l10n.newOrder),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.qr_code_scanner_outlined),
                selectedIcon: const Icon(Icons.qr_code_scanner),
                label: Text(l10n.orderPickup ?? 'Order Pickup'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.screen_search_desktop_outlined),
                selectedIcon: const Icon(Icons.screen_search_desktop_rounded),
                label: Text(l10n.searchOrder),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.inventory_2_outlined),
                selectedIcon: const Icon(Icons.inventory),
                label: Text(l10n.inventory),
              ),
              if (_userRole == 'admin' || _userRole == 'management' || _userRole == 'supervisor') ...[
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
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Main content
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
          ),
        ),
            // Hidden global barcode scanner input (always focused, invisible)
            Positioned(
              left: -1000,
              top: -1000,
              child: SizedBox(
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _globalBarcodeController,
                    focusNode: _globalBarcodeFocus,
                    autofocus: true,
                    onSubmitted: (value) {
                      // Process barcodes on all screens except create order page
                      // On order pickup page, QR codes (with pipes) will be handled by that screen's field
                      // Product barcodes (no pipes) should navigate to create order page
                      if (value.trim().isNotEmpty && _selectedIndex != 0) {
                        _handleGlobalBarcode(value.trim());
                      }
                    },
                  ),
                ),
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
        final success = await productProvider.syncProducts();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? l10n.dataSyncedSuccessfully : l10n.syncFailed('Failed to sync products')),
              action: SnackBarAction(
                label: 'Close',
                onPressed: () {},
              ),
            ),
          );
        }
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
      builder: (context) => AlertDialog(
        title: Text(l10n.logout),
        content: Text(l10n.areYouSureLogout),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.logout();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }
}

// OrderScreen combines ProductSelectionScreen and CartScreen
class OrderScreen extends StatelessWidget {
  const OrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        // Left: Product Selection (70%)
        Expanded(
          flex: 7,
          child: ProductSelectionScreen(key: productSelectionScreenKey),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        // Right: Cart (30%)
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(
                child: const CartScreen(),
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
                        minimumSize: const Size(double.infinity, 48),
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

