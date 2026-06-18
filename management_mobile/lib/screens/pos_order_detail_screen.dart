import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_labels.dart';
import '../models/pos_order.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../widgets/async_body.dart';

class PosOrderDetailScreen extends StatefulWidget {
  const PosOrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<PosOrderDetailScreen> createState() => _PosOrderDetailScreenState();
}

class _PosOrderDetailScreenState extends State<PosOrderDetailScreen> {
  var _loading = true;
  var _error = '';
  var _actioning = false;
  PosOrder? _order;

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
      final order = await ApiService.instance.getPosOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
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

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _actioning = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(order?.orderNumber ?? l10n.posOrder),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: order == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Info(l10n.store, order.store?.name ?? '—'),
                  _Info(l10n.staff, order.user?.displayName ?? '—'),
                  _Info(l10n.status, l10n.posOrderStatusFilterLabel(order.status)),
                  _Info(l10n.created, formatDateTime(order.createdAt)),
                  _Info(l10n.subtotal, formatMoney(order.subtotal)),
                  _Info(l10n.discount, formatMoney(order.discountAmount)),
                  _Info(l10n.total, formatMoney(order.totalAmount)),
                  const SizedBox(height: 16),
                  Text(l10n.items, style: Theme.of(context).textTheme.titleMedium),
                  ...order.items.map(
                    (item) => Card(
                      child: ListTile(
                        title: Text(item.product?.displayName() ?? '${l10n.product} #${item.productId}'),
                        subtitle: Text(l10n.qtyTimes('${item.quantity}', formatMoney(item.unitPrice))),
                        trailing: Text(formatMoney(item.lineTotal)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_actioning) const Center(child: CircularProgressIndicator()),
                  if (!_actioning && order.status == 'pending')
                    FilledButton(
                      onPressed: () => _run(() => ApiService.instance.markPosOrderPaid(order.id)),
                      child: Text(l10n.markPaid),
                    ),
                  if (!_actioning && order.status == 'paid')
                    FilledButton(
                      onPressed: () => _run(() => ApiService.instance.markPosOrderComplete(order.id)),
                      child: Text(l10n.markComplete),
                    ),
                  if (!_actioning && order.status != 'cancelled' && order.status != 'completed')
                    TextButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(l10n.cancelOrder),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.no)),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(l10n.cancelOrderAction),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await _run(() => ApiService.instance.cancelPosOrder(order.id));
                        }
                      },
                      child: Text(l10n.cancelOrderAction, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: Colors.grey[600]))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
