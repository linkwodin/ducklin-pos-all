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
  
  // List of pages for navigation
  List<Widget> get _pages => [
    OrderScreen(),
    OrderPickupScreen(),
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
        child: Scaffold(
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
      ),
    );
  }

      Future<void> _syncData() async {
        final l10n = AppLocalizations.of(context)!;
        final productProvider = Provider.of<ProductProvider>(context, listen: false);
        await productProvider.syncProducts();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.dataSyncedSuccessfully)),
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
          child: const ProductSelectionScreen(),
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

