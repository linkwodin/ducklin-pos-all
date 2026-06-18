import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../utils/role_labels.dart';
import '../utils/user_avatar.dart';
import '../widgets/language_selector.dart';
import '../screens/categories_screen.dart';
import '../screens/company_settings_screen.dart';
import '../screens/currency_rates_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/devices_screen.dart';
import '../screens/pos_orders_screen.dart';
import '../screens/products_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/restock_orders_screen.dart';
import '../screens/sectors_screen.dart';
import '../screens/shipments_screen.dart';
import '../screens/stock_screen.dart';
import '../screens/stores_screen.dart';
import '../screens/users_screen.dart';
import '../screens/wholesale_client_form_screen.dart';
import '../screens/wholesale_clients_screen.dart';
import '../screens/wholesale_order_create_screen.dart';
import '../screens/wholesale_orders_screen.dart';
import 'app_menu.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _route = 'dashboard';
  final _expandedGroups = <String>{};

  Widget _screenFor(String id) {
    switch (id) {
      case 'dashboard':
        return DashboardScreen(onNavigate: _navigate);
      case 'reports':
        return const ReportsScreen();
      case 'products':
        return const ProductsScreen();
      case 'categories':
        return const CategoriesScreen();
      case 'sectors':
        return const SectorsScreen();
      case 'stock':
        return const StockScreen();
      case 'restock':
        return const RestockOrdersScreen();
      case 'pos_orders':
        return const PosOrdersScreen();
      case 'wholesale_orders':
        return WholesaleOrdersScreen(
          onCreate: () => _push(const WholesaleOrderCreateScreen()),
        );
      case 'shipments':
        return const ShipmentsScreen();
      case 'wholesale_clients':
        return WholesaleClientsScreen(onCreate: () => _push(const WholesaleClientFormScreen()));
      case 'users':
        return const UsersScreen();
      case 'stores':
        return const StoresScreen();
      case 'devices':
        return const DevicesScreen();
      case 'currency':
        return const CurrencyRatesScreen();
      case 'company':
        return const CompanySettingsScreen();
      default:
        return DashboardScreen(onNavigate: _navigate);
    }
  }

  void _navigate(String route) {
    setState(() => _route = route);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _confirmLogout() async {
    final auth = context.read<AuthProvider>();
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logoutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.logout)),
        ],
      ),
    );
    if (ok == true && mounted) await auth.logout();
  }

  Future<void> _onMenuTap(AppMenuItem item) async {
    if (item.id == 'logout') {
      Navigator.pop(context);
      await _confirmLogout();
      return;
    }
    setState(() => _route = item.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final l10n = AppLocalizations.of(context)!;
    final menu = buildAppMenu(l10n);
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: Text(titleForMenuId(_route, l10n)),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DrawerUserHeader(
                user: user,
                roleLabel: user != null ? roleLabel(l10n, user.role) : '',
                onLanguageTap: () => showLanguagePicker(context),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final item in menu) ...[
                      if (item.isGroup) ...[
                        ListTile(
                          leading: Icon(item.icon),
                          title: Text(item.title),
                          trailing: Icon(
                            _expandedGroups.contains(item.id)
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          onTap: () => setState(() {
                            if (_expandedGroups.contains(item.id)) {
                              _expandedGroups.remove(item.id);
                            } else {
                              _expandedGroups.add(item.id);
                            }
                          }),
                        ),
                        if (_expandedGroups.contains(item.id))
                          for (final child in item.children)
                            ListTile(
                              leading: Icon(
                                child.icon,
                                size: 20,
                                color: child.id == 'logout'
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                              title: Text(
                                child.title,
                                style: child.id == 'logout'
                                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                                    : null,
                              ),
                              selected: _route == child.id,
                              onTap: () => _onMenuTap(child),
                              contentPadding: const EdgeInsets.only(left: 32, right: 16),
                            ),
                      ] else
                        ListTile(
                          leading: Icon(item.icon),
                          title: Text(item.title),
                          selected: _route == item.id,
                          onTap: () => _onMenuTap(item),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (_) => _screenFor(_route),
        ),
      ),
    );
  }
}
