import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_labels.dart';
import '../models/pos_order.dart';
import '../models/store.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../widgets/async_body.dart';
import 'pos_order_detail_screen.dart';

class PosOrdersScreen extends StatefulWidget {
  const PosOrdersScreen({super.key});

  @override
  State<PosOrdersScreen> createState() => _PosOrdersScreenState();
}

class _PosOrdersScreenState extends State<PosOrdersScreen> {
  var _loading = true;
  var _error = '';
  List<PosOrder> _orders = [];
  List<Store> _stores = [];
  int? _storeId;
  String? _status;

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
      final stores = await ApiService.instance.listStores(excludeWarehouseOnly: true);
      final orders = await ApiService.instance.listPosOrders(
        storeId: _storeId,
        status: _status,
      );
      orders.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _orders = orders;
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _storeId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l10n.store, isDense: true),
                      items: [
                        DropdownMenuItem(value: null, child: Text(l10n.allStores)),
                        ..._stores.map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      selectedItemBuilder: (context) => [
                        Text(l10n.allStores, overflow: TextOverflow.ellipsis, maxLines: 1),
                        ..._stores.map(
                          (s) => Text(s.name, overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _storeId = v);
                        _load();
                      },
                    ),
                  ),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: _status,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.status, isDense: true),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.all)),
                  DropdownMenuItem(value: 'pending', child: Text(l10n.posFilterPending)),
                  DropdownMenuItem(value: 'paid', child: Text(l10n.posFilterPaid)),
                  DropdownMenuItem(value: 'picked_up', child: Text(l10n.posFilterPickedUp)),
                  DropdownMenuItem(value: 'completed', child: Text(l10n.filterCompleted)),
                  DropdownMenuItem(value: 'cancelled', child: Text(l10n.posFilterCancelled)),
                ],
                onChanged: (v) {
                  setState(() => _status = v);
                  _load();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _orders.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final order = _orders[index];
                  return Card(
                    child: ListTile(
                      title: Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${order.store?.name ?? 'Store #${order.storeId}'} · ${formatDateTime(order.createdAt)}',
                      ),
                      trailing: SizedBox(
                        width: 80,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatMoney(order.totalAmount),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Text(
                              l10n.posOrderStatusFilterLabel(order.status),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => PosOrderDetailScreen(orderId: order.id)),
                        );
                        _load();
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
