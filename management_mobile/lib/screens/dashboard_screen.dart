import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../widgets/async_body.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onNavigate});

  final void Function(String route)? onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  var _loading = true;
  var _error = '';
  var _lowStock = 0;
  var _pendingRestocks = 0;
  var _pendingWholesale = 0;
  var _todayRevenue = 0.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final results = await Future.wait([
        ApiService.instance.getLowStock(),
        ApiService.instance.listRestockOrders(status: 'initiated'),
        ApiService.instance.listWholesaleOrders(filters: {'status': 'pending_approval'}),
        ApiService.instance.listWholesaleOrders(filters: {'status': 'assign_shipment'}),
        ApiService.instance.getTodayPosRevenue(),
      ]);
      if (!mounted) return;
      setState(() {
        _lowStock = (results[0] as List).length;
        _pendingRestocks = (results[1] as List).length;
        _pendingWholesale =
            (results[2] as List).length + (results[3] as List).length;
        _todayRevenue = results[4] as double;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.instance.errorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.menuDashboard, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            ApiService.instance.apiBaseUrl,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          AsyncBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            child: Column(
              children: [
                _StatCard(
                  icon: Icons.attach_money,
                  label: l10n.todayPosRevenue,
                  value: formatMoney(_todayRevenue),
                  onTap: () => widget.onNavigate?.call('pos_orders'),
                ),
                _StatCard(
                  icon: Icons.warning_amber,
                  label: l10n.lowStockItems,
                  value: '$_lowStock',
                  onTap: () => widget.onNavigate?.call('stock'),
                ),
                _StatCard(
                  icon: Icons.local_shipping_outlined,
                  label: l10n.pendingRestocks,
                  value: '$_pendingRestocks',
                  onTap: () => widget.onNavigate?.call('restock'),
                ),
                _StatCard(
                  icon: Icons.receipt_long,
                  label: l10n.pendingWholesaleOrders,
                  value: '$_pendingWholesale',
                  onTap: () => widget.onNavigate?.call('wholesale_orders'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(label),
        subtitle: Text(value, style: Theme.of(context).textTheme.titleMedium),
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}
