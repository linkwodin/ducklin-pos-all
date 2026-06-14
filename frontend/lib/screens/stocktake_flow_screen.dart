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
import '../utils/product_inventory.dart';
import '../utils/product_barcode.dart';
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
  /// productId -> counted values and scan flags
  final Map<int, Map<String, dynamic>> _stocktakeByProduct = {};
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
    if (mounted) {
      setState(() => _selectedStoreId = storeId);
      if (mounted) {
        await Provider.of<StockProvider>(context, listen: false).syncStock(storeId);
      }
    }
  }

  Map<String, dynamic>? _stockRow(int productId) {
    if (_selectedStoreId == null) return null;
    return Provider.of<StockProvider>(context, listen: false)
        .getStockRow(productId, _selectedStoreId!);
  }

  Map<String, dynamic> _ensureEntry(Map<String, dynamic> product, String productName) {
    final productId = product['id'] as int;
    return _stocktakeByProduct.putIfAbsent(productId, () => {
          'product': product,
          'productName': productName,
          'countedPrepacked': 0.0,
          'countedWeightG': 0.0,
          'scannedPrepacked': false,
          'scannedWeightG': false,
        });
  }

  Future<void> _onBarcodeSubmitted(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty || _selectedStoreId == null) return;

    final product = await DatabaseService.instance.resolveProductScan(code);
    if (product == null || !mounted) {
      if (mounted) {
        context.showNotification('Product not found for barcode: $code', isError: true);
      }
      _barcodeController.clear();
      return;
    }

    final productId = product['id'] as int;
    final productName = _getProductName(product, context);
    final stock = _stockRow(productId);
    final scanWeight = scanIsWeightMode(product);
    final trackPrepacked = stockTracksPrepacked(stock, product) && scanIsQtyMode(product);
    final trackWeight = stockTracksWeight(stock, product) && scanWeight;

    if (!trackPrepacked && !trackWeight) {
      context.showNotification('This barcode is not tracked for stocktake at this store.', isError: true);
      _barcodeController.clear();
      return;
    }

    final entry = _ensureEntry(product, productName);

    if (scanWeight) {
      final initialWeight = parsedWeightGramsFromScan(product);
      final weight = await showDialog<double>(
        context: context,
        builder: (ctx) => WeightInputDialog(
          product: product,
          initialWeightG: initialWeight,
        ),
      );
      if (weight == null || weight <= 0 || !mounted) {
        _barcodeController.clear();
        return;
      }
      entry['countedWeightG'] = (entry['countedWeightG'] as num).toDouble() + weight;
      entry['scannedWeightG'] = true;
    } else {
      entry['countedPrepacked'] = (entry['countedPrepacked'] as num).toDouble() + 1;
      entry['scannedPrepacked'] = true;
    }

    _barcodeController.clear();
    if (mounted) setState(() {});
    if (mounted) _barcodeFocus.requestFocus();
  }

  void _removeItem(int productId) {
    setState(() => _stocktakeByProduct.remove(productId));
  }

  List<Map<String, dynamic>> _buildDiscrepancies(StockProvider stockProvider) {
    final discrepancies = <Map<String, dynamic>>[];
    final storeId = _selectedStoreId!;

    for (final entry in _stocktakeByProduct.values) {
      final product = entry['product'] as Map<String, dynamic>;
      final productId = product['id'] as int;
      final stock = stockProvider.getStockRow(productId, storeId);
      final trackPrepacked = stockTracksPrepacked(stock, product);
      final trackWeight = stockTracksWeight(stock, product);
      final sysPre = systemPrepackedQuantity(stock, product);
      final sysWt = systemWeightQuantityG(stock, product);
      final cntPre = (entry['countedPrepacked'] as num).toDouble();
      final cntWt = (entry['countedWeightG'] as num).toDouble();
      final preDiff = trackPrepacked && (cntPre - sysPre).abs() > 0.0001;
      final wtDiff = trackWeight && (cntWt - sysWt).abs() > 0.0001;
      if (preDiff || wtDiff) {
        discrepancies.add(_discrepancyEntry(
          product: product,
          productName: entry['productName'] as String,
          trackPrepacked: trackPrepacked,
          trackWeight: trackWeight,
          systemPrepacked: sysPre,
          countedPrepacked: cntPre,
          systemWeightG: sysWt,
          countedWeightG: cntWt,
        ));
      }
    }

    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    for (final row in stockProvider.stock.entries) {
      final key = row.key;
      final parts = key.split('_');
      if (parts.length < 2) continue;
      final storeIdFromKey = int.tryParse(parts.sublist(1).join('_'));
      if (storeIdFromKey != storeId) continue;
      final productId = int.tryParse(parts[0]);
      if (productId == null || _stocktakeByProduct.containsKey(productId)) continue;

      final stock = row.value;
      final productList = productProvider.products.where((p) => p['id'] == productId).toList();
      final product = productList.isNotEmpty
          ? productList.first as Map<String, dynamic>
          : {'id': productId, 'unit_type': 'quantity'};
      final trackPrepacked = stockTracksPrepacked(stock, product);
      final trackWeight = stockTracksWeight(stock, product);
      final sysPre = systemPrepackedQuantity(stock, product);
      final sysWt = systemWeightQuantityG(stock, product);
      if ((trackPrepacked && sysPre.abs() > 0.0001) || (trackWeight && sysWt.abs() > 0.0001)) {
        final productName = productList.isNotEmpty
            ? _getProductName(product, context)
            : 'Product $productId';
        discrepancies.add(_discrepancyEntry(
          product: product,
          productName: productName,
          trackPrepacked: trackPrepacked,
          trackWeight: trackWeight,
          systemPrepacked: sysPre,
          countedPrepacked: 0,
          systemWeightG: sysWt,
          countedWeightG: 0,
        ));
      }
    }

    return discrepancies;
  }

  Map<String, dynamic> _discrepancyEntry({
    required Map<String, dynamic> product,
    required String productName,
    required bool trackPrepacked,
    required bool trackWeight,
    required double systemPrepacked,
    required double countedPrepacked,
    required double systemWeightG,
    required double countedWeightG,
  }) {
    return {
      'productName': productName,
      'product': product,
      'trackPrepacked': trackPrepacked,
      'trackWeight': trackWeight,
      'systemPrepacked': systemPrepacked,
      'countedPrepacked': countedPrepacked,
      'systemWeightG': systemWeightG,
      'countedWeightG': countedWeightG,
    };
  }

  /// Final quantity/weight per product to send to the API.
  List<Map<String, dynamic>> _buildStockUpdates(StockProvider stockProvider) {
    final updates = <Map<String, dynamic>>[];
    final seen = <int>{};

    void addUpdate(int productId, Map<String, dynamic> product, double quantity, double weightG) {
      if (seen.contains(productId)) return;
      seen.add(productId);
      updates.add({
        'product_id': productId,
        'product': product,
        'quantity': quantity,
        'weight_quantity_g': weightG,
      });
    }

    for (final entry in _stocktakeByProduct.values) {
      final product = entry['product'] as Map<String, dynamic>;
      final productId = product['id'] as int;
      final stock = stockProvider.getStockRow(productId, _selectedStoreId!);
      final trackPrepacked = stockTracksPrepacked(stock, product);
      final trackWeight = stockTracksWeight(stock, product);
      final sysPre = systemPrepackedQuantity(stock, product);
      final sysWt = systemWeightQuantityG(stock, product);
      final cntPre = (entry['countedPrepacked'] as num).toDouble();
      final cntWt = (entry['countedWeightG'] as num).toDouble();
      addUpdate(
        productId,
        product,
        trackPrepacked ? cntPre : sysPre,
        trackWeight ? cntWt : sysWt,
      );
    }

    for (final row in stockProvider.stock.entries) {
      final parts = row.key.split('_');
      if (parts.length < 2) continue;
      final storeIdFromKey = int.tryParse(parts.sublist(1).join('_'));
      if (storeIdFromKey != _selectedStoreId) continue;
      final productId = int.tryParse(parts[0]);
      if (productId == null || seen.contains(productId)) continue;

      final stock = row.value;
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      final productList = productProvider.products.where((p) => p['id'] == productId).toList();
      final product = productList.isNotEmpty
          ? productList.first as Map<String, dynamic>
          : {'id': productId, 'unit_type': 'quantity'};
      final trackPrepacked = stockTracksPrepacked(stock, product);
      final trackWeight = stockTracksWeight(stock, product);
      final sysPre = systemPrepackedQuantity(stock, product);
      final sysWt = systemWeightQuantityG(stock, product);
      if ((trackPrepacked && sysPre.abs() > 0.0001) || (trackWeight && sysWt.abs() > 0.0001)) {
        addUpdate(
          productId,
          product,
          trackPrepacked ? 0.0 : sysPre,
          trackWeight ? 0.0 : sysWt,
        );
      }
    }

    return updates;
  }

  Future<void> _completeStocktake() async {
    if (_stocktakeByProduct.isEmpty || _selectedStoreId == null) return;
    final stockProvider = Provider.of<StockProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final baseReason = widget.type == 'day_start' ? 'stocktake_day_start' : 'stocktake_day_end';

    final discrepancies = _buildDiscrepancies(stockProvider);

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
    final updates = _buildStockUpdates(stockProvider);

    try {
      final isOnline = await ApiService.instance.healthCheck();
      if (!isOnline) {
        final items = <Map<String, dynamic>>[];
        for (final u in updates) {
          final productId = u['product_id'] as int;
          final remark = adjustmentRemarks[productId]?.trim();
          final reason = remark != null && remark.isNotEmpty ? '$baseReasonStr | $remark' : baseReasonStr;
          items.add({
            'product_id': productId,
            'quantity': u['quantity'] as double,
            'weight_quantity_g': u['weight_quantity_g'] as double,
            'reason': reason,
          });
        }
        await DatabaseService.instance.savePendingStocktake(
          storeId: _selectedStoreId!,
          type: widget.type,
          reason: baseReasonStr,
          items: items,
        );
        for (final u in updates) {
          await stockProvider.updateLocalStock(
            u['product_id'] as int,
            _selectedStoreId!,
            quantity: u['quantity'] as double,
            weightQuantityG: u['weight_quantity_g'] as double,
          );
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
            _stocktakeByProduct.clear();
            _submitting = false;
          });
          context.showNotification(l10n.stocktakeSavedOffline, isSuccess: true);
        }
        if (mounted) Navigator.of(context).pop();
        return;
      }

      for (final u in updates) {
        final productId = u['product_id'] as int;
        final remark = adjustmentRemarks[productId]?.trim();
        final reason = remark != null && remark.isNotEmpty ? '$baseReasonStr | $remark' : baseReasonStr;
        await ApiService.instance.updateStock(
          productId,
          _selectedStoreId!,
          quantity: u['quantity'] as double,
          weightQuantityG: u['weight_quantity_g'] as double,
          reason: reason,
        );
      }
      await stockProvider.syncStock(_selectedStoreId!);
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
          _stocktakeByProduct.clear();
          _submitting = false;
        });
        context.showNotification(
          'Stocktake completed. ${updates.length} items updated.',
          isSuccess: true,
        );
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

  String _formatQtyLine(
    Map<String, dynamic> product,
    Map<String, dynamic>? stock,
    Map<String, dynamic> entry,
    AppLocalizations l10n,
  ) {
    final parts = <String>[];
    if (stockTracksPrepacked(stock, product)) {
      final q = (entry['countedPrepacked'] as num).toDouble();
      parts.add('Pre: ${q == q.roundToDouble() ? q.toInt() : q.toStringAsFixed(2)}');
    }
    if (stockTracksWeight(stock, product)) {
      final w = (entry['countedWeightG'] as num).toDouble();
      parts.add('Wt: ${l10n.weightDisplay(w.toStringAsFixed(2))}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDayStart = widget.type == 'day_start';
    final counted = _stocktakeByProduct.values.toList();

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
                        if (counted.isNotEmpty)
                          Text(
                            '${counted.length} products counted',
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
                    child: counted.isEmpty
                        ? Center(
                            child: Text(
                              'Scan each stock item. Use the qty or weight barcode for dual-inventory products.',
                              style: TextStyle(color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: counted.length,
                            itemBuilder: (ctx, i) {
                              final entry = counted[i];
                              final name = entry['productName'] as String;
                              final product = entry['product'] as Map<String, dynamic>;
                              final productId = product['id'] as int;
                              final stock = _stockRow(productId);
                              final qtyText = _formatQtyLine(product, stock, entry, l10n);
                              return ListTile(
                                title: Text(name),
                                subtitle: qtyText.isNotEmpty ? Text(qtyText) : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
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
                        icon: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle),
                        label: Text(_submitting ? 'Submitting...' : 'Complete stocktake'),
                        onPressed: _submitting || counted.isEmpty ? null : _completeStocktake,
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

  String _formatDiscrepancyLine(Map<String, dynamic> d) {
    final parts = <String>[];
    if (d['trackPrepacked'] == true) {
      final sys = (d['systemPrepacked'] as num).toDouble();
      final cnt = (d['countedPrepacked'] as num).toDouble();
      final sysStr = sys == sys.roundToDouble() ? sys.toInt().toString() : sys.toStringAsFixed(2);
      final cntStr = cnt == cnt.roundToDouble() ? cnt.toInt().toString() : cnt.toStringAsFixed(2);
      parts.add('Pre $sysStr → $cntStr');
    }
    if (d['trackWeight'] == true) {
      final sys = (d['systemWeightG'] as num).toDouble();
      final cnt = (d['countedWeightG'] as num).toDouble();
      parts.add('Wt ${sys.toStringAsFixed(2)}g → ${cnt.toStringAsFixed(2)}g');
    }
    return parts.join('; ');
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
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${d['productName']}: ${_formatDiscrepancyLine(d)}',
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
