import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_labels.dart';
import '../models/admin.dart';
import '../services/api_service.dart';
import '../widgets/async_body.dart';

class RestockOrdersScreen extends StatefulWidget {
  const RestockOrdersScreen({super.key});

  @override
  State<RestockOrdersScreen> createState() => _RestockOrdersScreenState();
}

class _RestockOrdersScreenState extends State<RestockOrdersScreen> {
  var _loading = true;
  var _error = '';
  List<RestockOrder> _orders = [];

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
      final orders = await ApiService.instance.listRestockOrders();
      if (!mounted) return;
      setState(() {
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
    return AsyncBody(
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
                title: Text(l10n.restockNumber(order.id)),
                subtitle: Text('${order.store?.name ?? l10n.storeNumber(order.storeId)} · ${l10n.restockStatusLabel(order.status)}'),
                trailing: order.status == 'initiated' || order.status == 'in_transit'
                    ? FilledButton(
                        onPressed: () async {
                          try {
                            await ApiService.instance.receiveRestockOrder(order.id);
                            _load();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(ApiService.instance.errorMessage(e))),
                              );
                            }
                          }
                        },
                        child: Text(l10n.receive),
                      )
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
