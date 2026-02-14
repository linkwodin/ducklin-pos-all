import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/sync_status_provider.dart';
import '../providers/product_provider.dart';
import '../providers/stock_provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/image_cache_service.dart';

enum _StepStatus { idle, running, done, error }

class _StepState {
  _StepStatus status = _StepStatus.idle;
  int current = 0;
  int total = 0;
  String? error;
  _StepState();
}

class FullSyncProgressScreen extends StatefulWidget {
  const FullSyncProgressScreen({super.key});

  @override
  State<FullSyncProgressScreen> createState() => _FullSyncProgressScreenState();
}

class _FullSyncProgressScreenState extends State<FullSyncProgressScreen> {
  final List<_StepState> _steps = List.generate(5, (_) => _StepState());
  bool _completed = false;
  String? _overallError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runFullSync());
  }

  Future<void> _runFullSync() async {
    final l10n = AppLocalizations.of(context)!;
    final deviceCode = ApiService.instance.deviceCode;
    if (deviceCode == null || deviceCode.isEmpty) {
      setState(() {
        _overallError = 'Device not configured';
        _completed = true;
      });
      return;
    }

    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final stockProvider = Provider.of<StockProvider>(context, listen: false);
    final syncStatus = Provider.of<SyncStatusProvider>(context, listen: false);

    try {
      // 1. Sync users
      _setStep(0, status: _StepStatus.running, total: 0);
      try {
        final users = await ApiService.instance.getUsersForDevice(deviceCode);
        final userList = users.cast<Map<String, dynamic>>();
        final n = userList.length;
        _setStep(0, total: n, current: 0);
        if (n > 0) {
          final ids = userList
              .map((u) => u['id'])
              .where((x) => x != null)
              .map((x) => x is int ? x : (x as num).toInt())
              .toList();
          await DatabaseService.instance.deleteUsersNotInIds(ids);
          await DatabaseService.instance.saveUsers(userList);
        }
        _setStep(0, status: _StepStatus.done, current: n, total: n);
      } catch (e) {
        _setStep(0, status: _StepStatus.error, error: e.toString());
      }

      // 2. Sync products
      _setStep(1, status: _StepStatus.running, total: 0);
      try {
        final products = await ApiService.instance.getProductsForDevice(deviceCode);
        final productList = products.cast<Map<String, dynamic>>();
        final n = productList.length;
        _setStep(1, total: n, current: 0);
        if (n > 0) {
          final ids = productList
              .map((p) => p['id'])
              .where((x) => x != null)
              .map((x) => x is int ? x : (x as num).toInt())
              .toList();
          await DatabaseService.instance.deleteProductsNotInIds(ids);
          await DatabaseService.instance.saveProducts(productList);
        }
        await productProvider.loadProducts();
        _setStep(1, status: _StepStatus.done, current: n, total: n);
      } catch (e) {
        _setStep(1, status: _StepStatus.error, error: e.toString());
      }

      // 3. Sync product images (clear cache)
      _setStep(2, status: _StepStatus.running, total: 1, current: 0);
      try {
        await ImageCacheService.clearProductImageCache();
        _setStep(2, status: _StepStatus.done, current: 1, total: 1);
      } catch (e) {
        _setStep(2, status: _StepStatus.error, error: e.toString());
      }

      // 4. Sync orders (pending orders + pending stocktakes)
      _setStep(3, status: _StepStatus.running, total: 0, current: 0);
      try {
        final pendingOrders = await DatabaseService.instance.getPendingOrders();
        final pendingStocktakes = await DatabaseService.instance.getPendingStocktakes();
        int totalItems = pendingOrders.length + pendingStocktakes.length;
        if (totalItems == 0) totalItems = 1;
        _setStep(3, total: totalItems, current: 0);
        int done = 0;
        for (final order in pendingOrders) {
          if (!mounted) return;
          try {
            final orderId = order['id'] as int;
            final items = await DatabaseService.instance.getOrderItems(orderId);
            final createdAt = order['created_at'];
            final created_at_iso = createdAt != null
                ? DateTime.fromMillisecondsSinceEpoch(createdAt as int).toUtc().toIso8601String()
                : null;
            final orderData = {
              'store_id': order['store_id'],
              'device_code': deviceCode,
              'sector_id': order['sector_id'],
              'order_number': order['order_number'],
              if (created_at_iso != null) 'created_at': created_at_iso,
              'items': items.map((item) => {
                    'product_id': item['product_id'],
                    'quantity': item['quantity'],
                    'unit_type': item['unit_type'] ?? 'quantity',
                  }).toList(),
            };
            final response = await ApiService.instance.createOrder(orderData);
            final backendOrderId = response['id'] as int?;
            if (backendOrderId != null) {
              try {
                await ApiService.instance.markOrderPaid(backendOrderId);
                await ApiService.instance.markOrderComplete(backendOrderId);
                // If order was picked up locally before sync, record pickup on backend too
                if (order['picked_up_at'] != null) {
                  try {
                    await ApiService.instance.confirmOrderPickup(order['order_number'] as String);
                  } catch (_) {}
                }
              } catch (_) {}
            }
            await DatabaseService.instance.markOrderSynced(orderId);
            await DatabaseService.instance.updateOrderStatusByOrderNumber(
              order['order_number'] as String,
              status: 'completed',
            );
          } catch (_) {}
          done++;
          _setStep(3, current: done, total: totalItems);
        }
        for (final st in pendingStocktakes) {
          if (!mounted) return;
          try {
            final stocktakeId = st['id'] as int;
            final storeId = st['store_id'] as int;
            final defaultReason = (st['reason'] as String?) ?? (st['type'] == 'day_start' ? 'stocktake_day_start' : 'stocktake_day_end');
            final stItems = await DatabaseService.instance.getPendingStocktakeItems(stocktakeId);
            for (final item in stItems) {
              final reason = (item['reason'] as String?)?.trim().isNotEmpty == true
                  ? item['reason'] as String
                  : defaultReason;
              await ApiService.instance.updateStock(
                item['product_id'] as int,
                storeId,
                quantity: (item['quantity'] as num).toDouble(),
                reason: reason,
              );
            }
            await DatabaseService.instance.markStocktakeSynced(stocktakeId);
          } catch (_) {}
          done++;
          _setStep(3, current: done, total: totalItems);
        }
        if (pendingOrders.isEmpty && pendingStocktakes.isEmpty) {
          _setStep(3, current: 1, total: 1);
        }
        _setStep(3, status: _StepStatus.done);
      } catch (e) {
        _setStep(3, status: _StepStatus.error, error: e.toString());
      }

      // 5. Sync inventory (stock from API)
      _setStep(4, status: _StepStatus.running, total: 1, current: 0);
      try {
        final deviceInfo = await DatabaseService.instance.getDeviceInfo();
        final storeId = deviceInfo?['store_id'] as int? ?? 1;
        await stockProvider.syncStock(storeId);
        _setStep(4, status: _StepStatus.done, current: 1, total: 1);
      } catch (e) {
        _setStep(4, status: _StepStatus.error, error: e.toString());
      }

      if (mounted) await syncStatus.refreshPendingCount();
    } catch (e) {
      if (mounted) setState(() => _overallError = e.toString());
    }

    if (mounted) setState(() => _completed = true);
  }

  void _setStep(int index, {_StepStatus? status, int? current, int? total, String? error}) {
    if (!mounted) return;
    setState(() {
      final s = _steps[index];
      if (status != null) s.status = status;
      if (current != null) s.current = current;
      if (total != null) s.total = total;
      if (error != null) s.error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = [
      l10n.fullSyncUsers,
      l10n.fullSyncProducts,
      l10n.fullSyncProductImages,
      l10n.fullSyncOrders,
      l10n.fullSyncInventory,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.fullSyncTitle),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: 5,
                itemBuilder: (context, i) {
                  final s = _steps[i];
                  final progressText = s.total > 0 ? '${s.current}/${s.total}' : (s.status == _StepStatus.running ? '0/?' : '—');
                  IconData icon = Icons.hourglass_empty;
                  Color? iconColor;
                  if (s.status == _StepStatus.done) {
                    icon = Icons.check_circle;
                    iconColor = Colors.green;
                  } else if (s.status == _StepStatus.error) {
                    icon = Icons.error;
                    iconColor = Colors.red;
                  } else if (s.status == _StepStatus.running) {
                    icon = Icons.sync;
                    iconColor = Theme.of(context).colorScheme.primary;
                  }
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Icon(icon, color: iconColor, size: 28),
                      title: Text(labels[i], style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: s.error != null
                          ? Text(s.error!, style: TextStyle(color: Colors.red[700], fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: SizedBox(
                        width: 48,
                        child: Text(
                          progressText,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: s.status == _StepStatus.running ? Theme.of(context).colorScheme.primary : null,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_overallError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_overallError!, style: TextStyle(color: Colors.red[700])),
              ),
            if (_completed)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.close),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
