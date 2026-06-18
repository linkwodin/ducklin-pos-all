import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/stock.dart';
import '../models/store.dart';
import '../services/api_service.dart';
import '../widgets/async_body.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  var _loading = true;
  var _error = '';
  List<StockRow> _rows = [];
  List<Store> _stores = [];
  int? _storeId;

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
      final stores = await ApiService.instance.listStores();
      final rows = await ApiService.instance.listStock(storeId: _storeId);
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _rows = rows;
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

  Future<void> _adjust(StockRow row) async {
    final l10n = AppLocalizations.of(context)!;
    final qty = TextEditingController(text: '${row.quantity}');
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.adjustStockTitle(row.product?.displayName() ?? l10n.adjustStock)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qty,
              decoration: InputDecoration(labelText: l10n.quantity),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: reason,
              decoration: InputDecoration(labelText: l10n.reason),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.save)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.instance.updateStock(
        row.productId,
        row.storeId,
        quantity: double.tryParse(qty.text.trim()) ?? row.quantity,
        reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
      }
    }
    qty.dispose();
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<int?>(
            value: _storeId,
            decoration: InputDecoration(labelText: l10n.store),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.allStores)),
              ..._stores.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
            ],
            onChanged: (v) {
              setState(() => _storeId = v);
              _load();
            },
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
                itemCount: _rows.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  return Card(
                    child: ListTile(
                      title: Text(row.product?.displayName() ?? 'Product #${row.productId}'),
                      subtitle: Text(row.storeName ?? 'Store #${row.storeId}'),
                      trailing: Text(l10n.qtyLabel('${row.quantity}')),
                      onTap: () => _adjust(row),
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
