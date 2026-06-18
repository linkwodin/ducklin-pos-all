import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_labels.dart';
import '../models/wholesale_order.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../utils/wholesale_order_workflow.dart';
import '../widgets/status_chip.dart';
import '../widgets/async_body.dart';
import 'wholesale_order_create_screen.dart';
import 'wholesale_order_detail_screen.dart';

class WholesaleOrdersScreen extends StatefulWidget {
  const WholesaleOrdersScreen({super.key, this.onCreate});

  final VoidCallback? onCreate;

  @override
  State<WholesaleOrdersScreen> createState() => _WholesaleOrdersScreenState();
}

class _WholesaleOrdersScreenState extends State<WholesaleOrdersScreen> {
  var _loading = true;
  var _error = '';
  List<WholesaleOrder> _orders = [];
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
      final statusForApi = wholesaleOrderStatusFilterForApi(_status);
      final orders = await ApiService.instance.listWholesaleOrders(
        filters: statusForApi != null ? {'status': statusForApi} : null,
      );
      final filtered = filterWholesaleOrdersByStatus(orders, _status);
      filtered.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      if (!mounted) return;
      setState(() {
        _orders = filtered;
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

  void _onStatusChanged(String? status) {
    setState(() => _status = status);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (widget.onCreate != null) {
            widget.onCreate!();
          } else {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const WholesaleOrderCreateScreen()))
                .then((_) => _load());
          }
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: _status,
                    decoration: InputDecoration(labelText: l10n.status, isDense: true),
                    items: wholesaleOrderStatusFilterValues
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              l10n.wholesaleOrderStatusFilterLabel(value),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _onStatusChanged,
                  ),
                ),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
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
                    final workflowCtx = buildWholesaleWorkflowContext(order, const []);
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => WholesaleOrderDetailScreen(orderId: order.id),
                            ),
                          );
                          _load();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      order.orderNumber,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(order.client?.name ?? '—'),
                                    const SizedBox(height: 2),
                                    Text(
                                      formatDate(order.createdAt),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  StatusChip(
                                    label: l10n.wholesaleOrderWorkflowStatusLabel(order, workflowCtx),
                                    color: wholesaleOrderStatusColor(order, workflowCtx),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    formatMoney(order.amountDue ?? order.itemsTotal),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
