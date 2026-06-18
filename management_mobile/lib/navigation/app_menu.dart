import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class AppMenuItem {
  const AppMenuItem({
    required this.id,
    required this.title,
    required this.icon,
    this.children = const [],
  });

  final String id;
  final String title;
  final IconData icon;
  final List<AppMenuItem> children;

  bool get isGroup => children.isNotEmpty;
}

List<AppMenuItem> buildAppMenu(AppLocalizations l10n) => [
      AppMenuItem(id: 'dashboard', title: l10n.menuDashboard, icon: Icons.dashboard_outlined),
      AppMenuItem(id: 'reports', title: l10n.menuReports, icon: Icons.table_chart_outlined),
      AppMenuItem(
        id: 'products_group',
        title: l10n.menuProductsGroup,
        icon: Icons.menu_book_outlined,
        children: [
          AppMenuItem(id: 'products', title: l10n.menuProducts, icon: Icons.inventory_2_outlined),
          AppMenuItem(id: 'categories', title: l10n.menuCategories, icon: Icons.label_outline),
          AppMenuItem(id: 'sectors', title: l10n.menuSectors, icon: Icons.category_outlined),
        ],
      ),
      AppMenuItem(
        id: 'inventory_group',
        title: l10n.menuInventoryGroup,
        icon: Icons.warehouse_outlined,
        children: [
          AppMenuItem(id: 'stock', title: l10n.menuStock, icon: Icons.warehouse_outlined),
          AppMenuItem(id: 'restock', title: l10n.menuRestock, icon: Icons.local_shipping_outlined),
        ],
      ),
      AppMenuItem(id: 'pos_orders', title: l10n.menuPosOrders, icon: Icons.shopping_cart_outlined),
      AppMenuItem(
        id: 'wholesale_group',
        title: l10n.menuWholesaleGroup,
        icon: Icons.local_shipping_outlined,
        children: [
          AppMenuItem(id: 'wholesale_orders', title: l10n.menuWholesaleOrders, icon: Icons.receipt_long_outlined),
          AppMenuItem(id: 'shipments', title: l10n.menuShipments, icon: Icons.local_shipping_outlined),
          AppMenuItem(id: 'wholesale_clients', title: l10n.menuWholesaleClients, icon: Icons.people_outline),
        ],
      ),
      AppMenuItem(
        id: 'settings_group',
        title: l10n.menuSettingsGroup,
        icon: Icons.settings_outlined,
        children: [
          AppMenuItem(id: 'users', title: l10n.menuUsers, icon: Icons.people_outline),
          AppMenuItem(id: 'stores', title: l10n.menuStores, icon: Icons.store_outlined),
          AppMenuItem(id: 'devices', title: l10n.menuDevices, icon: Icons.phone_android_outlined),
          AppMenuItem(id: 'currency', title: l10n.menuCurrency, icon: Icons.currency_exchange),
          AppMenuItem(id: 'company', title: l10n.menuCompany, icon: Icons.business_outlined),
          AppMenuItem(id: 'logout', title: l10n.logout, icon: Icons.logout),
        ],
      ),
    ];

String titleForMenuId(String id, AppLocalizations l10n) {
  for (final item in buildAppMenu(l10n)) {
    if (item.id == id) return item.title;
    for (final child in item.children) {
      if (child.id == id) return child.title;
    }
  }
  return l10n.management;
}
