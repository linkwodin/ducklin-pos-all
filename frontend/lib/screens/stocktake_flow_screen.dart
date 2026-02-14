import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/stock_provider.dart';
import '../providers/stocktake_status_provider.dart';
import '../providers/product_provider.dart';
import '../providers/language_provider.dart';
import '../providers/notification_bar_provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/offline_sync_service.dart';
import '../services/stocktake_prompt_service.dart';
import 'weight_input_dialog.dart';

/// Full-screen stocktake flow (day start or day end). Opened from inventory FAB or from notification/day-start prompt.
class StocktakeFlowScreen extends StatefulWidget {
  const StocktakeFlowScreen({super.key, required this.type});

  final String type; // 'day_start' | 'day_end'

  @override
  State<StocktakeFlowScreen> createState() => _StocktakeFlowScreenState();
}

class _StocktakeFlowScreenState extends State<StocktakeFlowScreen> {
  int? _selectedStoreId;
  final List<Map<String, dynamic>> _stocktakeCounted = [];
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadStoreId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _barcodeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  Future<void> _loadStoreId() async {
    final deviceInfo = await DatabaseService.instance.getDeviceInfo();
    final storeId = deviceInfo?['store_id'] as int? ?? 1;
    if (mounted) setState(() => _selectedStoreId = storeId);
  }

  Future<void> _onBarcodeSubmitted(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty || _selectedStoreId == null) return;

    final product = await DatabaseService.instance.getProductByBarcode(code);
    if (product == null || !mounted) {
      if (mounted) {
        context.showNotification('Product not found for barcode: $code', isError: true);
      }
      _barcodeController.clear();
      return;
    }

    final productId = product['id'] as int;
    final productName = _getProductName(product, context);
    final unitType = (product['unit_type'] ?? 'quantity').toString().toLowerCase();
    final isWeight = unitType == 'weight';

    if (isWeight) {
      final weight = await showDialog<double>(
        context: context,
        builder: (ctx) => const WeightInputDialog(),
      );
      if (weight == null || weight <= 0 || !mounted) {
        _barcodeController.clear();
        return;
      }
      final idx = _stocktakeCounted.indexWhere((e) => (e['product'] as Map)['id'] == productId);
      if (idx >= 0) {
        final cur = (_stocktakeCounted[idx]['countedQty'] as num).toDouble();
        _stocktakeCounted[idx]['countedQty'] = cur + weight;
      } else {
        _stocktakeCounted.add({'product': product, 'productName': productName, 'countedQty': weight});
      }
    } else {
      final idx = _stocktakeCounted.indexWhere((e) => (e['product'] as Map)['id'] == productId);
      if (idx >= 0) {
        final cur = (_stocktakeCounted[idx]['countedQty'] as num).toDouble();
        _stocktakeCounted[idx]['countedQty'] = cur + 1;
      } else {
        _stocktakeCounted.add({'product': product, 'productName': productName, 'countedQty': 1.0});
      }
    }
    _barcodeController.clear();
    if (mounted) setState(() {});
    if (mounted) _barcodeFocus.requestFocus();
  }

  void _removeItem(int productId) {
    setState(() {
      _stocktakeCounted.removeWhere((e) => (e['product'] as Map)['id'] == productId);
    });
  }

  Future<void> _completeStocktake() async {
    if (_stocktakeCounted.isEmpty || _selectedStoreId == null) return;
    final stockProvider = Provider.of<StockProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final baseReason = widget.type == 'day_start' ? 'stocktake_day_start' : 'stocktake_day_end';

    final discrepancies = <Map<String, dynamic>>[];
    final scannedProductIds = <int>{};
    for (final entry in _stocktakeCounted) {
      final product = entry['product'] as Map<String, dynamic>;
      final productId = product['id'] as int;
      scannedProductIds.add(productId);
      final countedQty = (entry['countedQty'] as num).toDouble();
      final stockKey = '${productId}_$_selectedStoreId';
      final systemQty = stockProvider.stock.containsKey(stockKey)
          ? (stockProvider.stock[stockKey]!['quantity'] as num).toDouble()
          : 0.0;
      if ((countedQty - systemQty).abs() > 0.0001) {
        discrepancies.add({
          'productName': entry['productName'] as String,
          'systemQty': systemQty,
          'countedQty': countedQty,
          'product': product,
        });
      }
    }

    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    for (final entry in stockProvider.stock.entries) {
      final key = entry.key;
      final parts = key.split('_');
      if (parts.length < 2) continue;
      final storeIdFromKey = int.tryParse(parts.sublist(1).join('_'));
      if (storeIdFromKey != _selectedStoreId) continue;
      final productId = int.tryParse(parts[0]);
      if (productId == null || scannedProductIds.contains(productId)) continue;
      final systemQty = (entry.value['quantity'] as num).toDouble();
      if (systemQty.abs() < 0.0001) continue;
      final productList = productProvider.products.where((p) => p['id'] == productId).toList();
      final product = productList.isNotEmpty ? productList.first as Map<String, dynamic> : null;
      final productName = product != null ? _getProductName(product, context) : 'Product $productId';
      final productMap = product ?? {'id': productId, 'unit_type': 'quantity'};
      discrepancies.add({
        'productName': productName,
        'systemQty': systemQty,
        'countedQty': 0.0,
        'product': productMap,
      });
    }

    String? adjustmentReason;
    Map<int, String> adjustmentRemarks = {};
    if (discrepancies.isNotEmpty) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StocktakeDiscrepancyDialog(
          l10n: l10n,
          discrepancies: discrepancies,
        ),
      );
      if (result == null) return;
      adjustmentReason = result['reason'] as String?;
      adjustmentRemarks = (result['remarks'] as Map<int, String>?) ?? {};
      if (adjustmentReason == null || adjustmentReason.isEmpty) return;
    }

    setState(() => _submitting = true);
    final baseReasonStr = adjustmentReason ?? baseReason;
    try {
      final isOnline = await ApiService.instance.healthCheck();
      if (!isOnline) {
        final items = <Map<String, dynamic>>[];
        for (final e in _stocktakeCounted) {
          final product = e['product'] as Map<String, dynamic>;
          final productId = product['id'] as int;
          final remark = adjustmentRemarks[productId]?.trim();
          final reason = remark != null && remark.isNotEmpty ? '$baseReasonStr | $remark' : baseReasonStr;
          items.add({
            'product_id': productId,
            'quantity': (e['countedQty'] as num).toDouble(),
            'reason': reason,
          });
        }
        for (final d in discrepancies) {
          if ((d['countedQty'] as num).toDouble() != 0) continue;
          final productId = (d['product'] as Map)['id'] as int;
          final remark = adjustmentRemarks[productId]?.trim();
          final reason = remark != null && remark.isNotEmpty ? '$baseReasonStr | $remark' : baseReasonStr;
          items.add({'product_id': productId, 'quantity': 0.0, 'reason': reason});
        }
        await DatabaseService.instance.savePendingStocktake(
          storeId: _selectedStoreId!,
          type: widget.type,
          reason: baseReasonStr,
          items: items,
        );
        for (final entry in _stocktakeCounted) {
          final product = entry['product'] as Map<String, dynamic>;
          final productId = product['id'] as int;
          final qty = (entry['countedQty'] as num).toDouble();
          await stockProvider.updateLocalStock(productId, _selectedStoreId!, qty);
        }
        for (final d in discrepancies) {
          if ((d['countedQty'] as num).toDouble() != 0) continue;
          final productId = (d['product'] as Map)['id'] as int;
          await stockProvider.updateLocalStock(productId, _selectedStoreId!, 0);
        }
        OfflineSyncService.start(() {});
        if (mounted) {
          if (widget.type == 'day_start') {
            try {
              await ApiService.instance.recordStocktakeDayStart('done', storeId: _selectedStoreId);
            } catch (_) {}
            Provider.of<StocktakeStatusProvider>(context, listen: false).setPendingDone();
          } else if (widget.type == 'day_end') {
            await StocktakePromptService.recordDayEndDone();
          }
          setState(() {
            _stocktakeCounted.clear();
            _submitting = false;
          });
          context.showNotification(l10n.stocktakeSavedOffline, isSuccess: true);
        }
        if (mounted) Navigator.of(context).pop();
        return;
      }
      for (final entry in _stocktakeCounted) {
        final product = entry['product'] as Map<String, dynamic>;
        final productId = product['id'] as int;
        final qty = (entry['countedQty'] as num).toDouble();
        final remark = adjustmentRemarks[productId]?.trim();
        final reason = remark != null && remark.isNotEmpty ? '$baseReasonStr | $remark' : baseReasonStr;
        await ApiService.instance.updateStock(
          productId,
          _selectedStoreId!,
          quantity: qty,
          reason: reason,
        );
      }
      for (final d in discrepancies) {
        if ((d['countedQty'] as num).toDouble() != 0) continue;
        final productId = (d['product'] as Map)['id'] as int;
        final remark = adjustmentRemarks[productId]?.trim();
        final reason = remark != null && remark.isNotEmpty ? '$baseReasonStr | $remark' : baseReasonStr;
        await ApiService.instance.updateStock(
          productId,
          _selectedStoreId!,
          quantity: 0,
          reason: reason,
        );
      }
      await stockProvider.syncStock(_selectedStoreId!);
      final count = _stocktakeCounted.length + discrepancies.where((d) => (d['countedQty'] as num).toDouble() == 0).length;
      if (mounted) {
        if (widget.type == 'day_start') {
          try {
            await ApiService.instance.recordStocktakeDayStart('done', storeId: _selectedStoreId);
          } catch (_) {}
          Provider.of<StocktakeStatusProvider>(context, listen: false).setPendingDone();
        } else if (widget.type == 'day_end') {
          await StocktakePromptService.recordDayEndDone();
        }
        setState(() {
          _stocktakeCounted.clear();
          _submitting = false;
        });
        context.showNotification('Stocktake completed. $count items updated.', isSuccess: true);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        context.showNotification('Stocktake failed: $e', isError: true);
      }
    }
  }

  String _getProductName(Map<String, dynamic> product, BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final currentLocale = languageProvider.locale;
    if (currentLocale.languageCode == 'zh') {
      final nameChinese = product['name_chinese']?.toString();
      if (nameChinese != null && nameChinese.isNotEmpty) return nameChinese;
    }
    return product['name']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDayStart = widget.type == 'day_start';

    return PopScope(
      canPop: !isDayStart,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isDayStart) {
          Navigator.of(context).pop('incomplete');
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isDayStart ? 'Stocktake – Day start' : 'Stocktake – Day end'),
        ),
        body: _selectedStoreId == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (_stocktakeCounted.isNotEmpty)
                        Text(
                          '${_stocktakeCounted.length} counted',
                          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _barcodeController,
                    focusNode: _barcodeFocus,
                    decoration: const InputDecoration(
                      hintText: 'Scan barcode...',
                      prefixIcon: Icon(Icons.qr_code_scanner),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _onBarcodeSubmitted,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _stocktakeCounted.isEmpty
                      ? Center(
                          child: Text(
                            'Scan each stock item. By-weight products: enter weight (g) after scan.',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _stocktakeCounted.length,
                          itemBuilder: (ctx, i) {
                            final e = _stocktakeCounted[i];
                            final name = e['productName'] as String;
                            final qty = (e['countedQty'] as num).toDouble();
                            final product = e['product'] as Map<String, dynamic>;
                            final productId = product['id'] as int;
                            final isWeight = ((product['unit_type'] ?? 'quantity').toString().toLowerCase() == 'weight');
                            final qtyText = isWeight ? l10n.weightDisplay(qty.toStringAsFixed(2)) : qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2);
                            return ListTile(
                              title: Text(name),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(qtyText, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => _removeItem(productId),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle),
                      label: Text(_submitting ? 'Submitting...' : 'Complete stocktake'),
                      onPressed: _submitting || _stocktakeCounted.isEmpty ? null : _completeStocktake,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

class StocktakeDiscrepancyDialog extends StatefulWidget {
  const StocktakeDiscrepancyDialog({
    super.key,
    required this.l10n,
    required this.discrepancies,
  });

  final AppLocalizations l10n;
  final List<Map<String, dynamic>> discrepancies;

  @override
  State<StocktakeDiscrepancyDialog> createState() => _StocktakeDiscrepancyDialogState();
}

class _StocktakeDiscrepancyDialogState extends State<StocktakeDiscrepancyDialog> {
  late final TextEditingController _reasonController;
  late final List<TextEditingController> _remarkControllers;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
    _remarkControllers = List.generate(
      widget.discrepancies.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    for (final c in _remarkControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) return;
    final remarks = <int, String>{};
    for (var i = 0; i < widget.discrepancies.length; i++) {
      final productId = (widget.discrepancies[i]['product'] as Map)['id'] as int;
      final remark = _remarkControllers[i].text.trim();
      if (remark.isNotEmpty) remarks[productId] = remark;
    }
    Navigator.pop(context, {'reason': reason, 'remarks': remarks});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final discrepancies = widget.discrepancies;

    return AlertDialog(
      title: Text(l10n.stocktakeDiscrepancyTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.stocktakeDiscrepancyMessage,
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            ...List.generate(discrepancies.length, (i) {
              final d = discrepancies[i];
              final sys = (d['systemQty'] as num).toDouble();
              final cnt = (d['countedQty'] as num).toDouble();
              final product = d['product'] as Map<String, dynamic>;
              final isW = (product['unit_type']?.toString().toLowerCase() == 'weight');
              final suffix = isW ? 'g' : '';
              final sysStr = isW ? sys.toStringAsFixed(2) : (sys == sys.roundToDouble() ? sys.toInt().toString() : sys.toStringAsFixed(2));
              final cntStr = isW ? cnt.toStringAsFixed(2) : (cnt == cnt.roundToDouble() ? cnt.toInt().toString() : cnt.toStringAsFixed(2));
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${d['productName']}: $sysStr$suffix → $cntStr$suffix',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _remarkControllers[i],
                      decoration: InputDecoration(
                        labelText: l10n.stocktakeRemarkHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: l10n.stocktakeReasonHint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
              onSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}
