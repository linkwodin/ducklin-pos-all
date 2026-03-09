import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/order_provider.dart';
import '../providers/product_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../widgets/cached_product_image.dart';

class _LineItem {
  int? productId;
  double quantity;
  double discountAmount;

  _LineItem({this.productId, this.quantity = 1, this.discountAmount = 0});
}

class CreateWholesaleOrderScreen extends StatefulWidget {
  const CreateWholesaleOrderScreen({super.key});

  @override
  State<CreateWholesaleOrderScreen> createState() => _CreateWholesaleOrderScreenState();
}

class _CreateWholesaleOrderScreenState extends State<CreateWholesaleOrderScreen> {
  List<dynamic> _stores = [];
  List<dynamic> _clients = [];
  int? _selectedStoreId;
  int? _selectedClientId;
  final TextEditingController _notesController = TextEditingController();
  final List<_LineItem> _lines = [_LineItem()];
  bool _orderDiscountIsRate = false; // false = amount in £, true = rate %
  double _orderDiscountValue = 0; // amount or rate, depending on _orderDiscountIsRate
  bool _loadingStores = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loadingStores = true);
    try {
      final storeList = await ApiService.instance.getStores();
      final clientList = await ApiService.instance.listWholesaleClients(activeOnly: true);
      setState(() {
        _stores = storeList;
        _clients = clientList;
        _loadingStores = false;
        if (_selectedStoreId == null && storeList.isNotEmpty) {
          final orderProvider = Provider.of<OrderProvider>(context, listen: false);
          final deviceStoreId = orderProvider.storeId;
          final hasMatch = storeList.any((s) => _storeId(s) == deviceStoreId);
          _selectedStoreId = hasMatch ? deviceStoreId : _storeId(storeList.first);
        }
        if (_selectedClientId == null && clientList.isNotEmpty) {
          _selectedClientId = _clientId(clientList.first);
        }
      });
    } catch (_) {
      setState(() => _loadingStores = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load stores/clients'), backgroundColor: Colors.red),
        );
      }
    }
  }

  int _storeId(dynamic s) => s is Map ? (s['id'] is int ? s['id'] as int : (s['id'] as num).toInt()) : 0;
  String _storeName(dynamic s) => s is Map ? (s['name'] ?? '').toString() : '';
  int _clientId(dynamic c) => c is Map ? (c['id'] is int ? c['id'] as int : (c['id'] as num).toInt()) : 0;
  String _clientName(dynamic c) => c is Map ? (c['name'] ?? '').toString() : '';

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool get _isChinese {
    final locale = Provider.of<LanguageProvider>(context, listen: false).locale;
    return locale.languageCode == 'zh';
  }

  String _productName(Map<String, dynamic> p) {
    final name = p['name']?.toString() ?? '';
    final zh = p['name_chinese']?.toString();
    if (_isChinese && zh != null && zh.isNotEmpty) return zh;
    return name.isNotEmpty ? name : (zh ?? '');
  }

  int? get _clientSectorId {
    if (_selectedClientId == null) return null;
    for (final c in _clients) {
      if (c is Map && _clientId(c) == _selectedClientId) {
        final sid = c['sector_id'];
        return sid is int ? sid : (sid is num ? sid.toInt() : null);
      }
    }
    return null;
  }

  String? get _clientSectorName {
    if (_selectedClientId == null) return null;
    for (final c in _clients) {
      if (c is Map && _clientId(c) == _selectedClientId) {
        final sector = c['sector'];
        if (sector is Map) return sector['name']?.toString();
      }
    }
    return null;
  }

  double _unitPrice(Map<String, dynamic> product) {
    final cost = product['current_cost'];
    double price = 0;
    if (cost is Map) {
      final wholesale = (cost['wholesale_cost_gbp'] as num?)?.toDouble() ?? 0.0;
      final directRetail = (cost['direct_retail_online_store_price_gbp'] as num?)?.toDouble() ?? 0.0;
      price = wholesale > 0 ? wholesale : directRetail;
    }

    final sectorId = _clientSectorId;
    if (sectorId != null) {
      final discounts = product['discounts'];
      if (discounts is List) {
        for (final d in discounts) {
          if (d is Map && (d['sector_id'] as num?)?.toInt() == sectorId) {
            final sectorPrice = (d['sector_price_gbp'] as num?)?.toDouble() ?? 0;
            if (sectorPrice > 0) return sectorPrice;
            final pct = (d['discount_percent'] as num?)?.toDouble() ?? 0;
            if (pct > 0 && price > 0) {
              price = (price * (1 - pct / 100) * 100).roundToDouble() / 100;
            }
            break;
          }
        }
      }
    }
    return price;
  }

  double _lineSubtotal(_LineItem line, List<dynamic> products) {
    if (line.productId == null || line.quantity <= 0) return 0.0;
    Map<String, dynamic>? product;
    for (final p in products) {
      if (p is Map) {
        final id = p['id'] is int ? p['id'] as int : (p['id'] as num?)?.toInt();
        if (id != null && id == line.productId) {
          product = p.cast<String, dynamic>();
          break;
        }
      }
    }
    if (product == null) return 0.0;
    final unit = _unitPrice(product);
    final before = unit * line.quantity;
    final discount = line.discountAmount.clamp(0, before);
    final subtotal = before - discount;
    return subtotal < 0 ? 0.0 : subtotal;
  }

  double _orderSubtotal(List<dynamic> products) {
    double sum = 0;
    for (final line in _lines) {
      sum += _lineSubtotal(line, products);
    }
    return sum;
  }

  double _orderDiscountAmount(double subtotal) {
    if (subtotal <= 0) return 0.0;
    if (_orderDiscountIsRate) {
      final rate = _orderDiscountValue.clamp(0, 100).toDouble();
      return subtotal * rate / 100;
    }
    final amount = _orderDiscountValue.clamp(0, subtotal).toDouble();
    return amount < 0 ? 0.0 : amount;
  }

  Future<void> _editLineDiscount(_LineItem line, Map<String, dynamic> product) async {
    final unitPrice = _unitPrice(product);
    final before = unitPrice * line.quantity;
    double tempAmount = line.discountAmount;
    bool isRateMode = false;

    if (before > 0 && line.discountAmount > 0) {
      final currentRate = (line.discountAmount / before) * 100;
      // Default to amount mode but allow switching to rate with a sensible initial value.
      tempAmount = line.discountAmount;
      isRateMode = false;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        String input = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final effectiveAmount = () {
              final parsed = double.tryParse(input);
              if (parsed == null || parsed <= 0) return tempAmount;
              if (isRateMode) {
                if (before <= 0) return 0.0;
                final rate = parsed.clamp(0, 100);
                return before * rate / 100;
              }
              return parsed.clamp(0, before);
            }();
            final rateDisplay = before > 0 ? (effectiveAmount / before) * 100 : 0.0;

            return AlertDialog(
              title: const Text('Line discount'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Amount £'),
                        selected: !isRateMode,
                        onSelected: (sel) {
                          if (!sel) return;
                          setStateDialog(() {
                            isRateMode = false;
                            input = '';
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Rate %'),
                        selected: isRateMode,
                        onSelected: (sel) {
                          if (!sel) return;
                          setStateDialog(() {
                            isRateMode = true;
                            input = '';
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: isRateMode ? 'Discount rate (%)' : 'Discount amount (£)',
                    ),
                    onChanged: (v) => setStateDialog(() => input = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Will apply: £${effectiveAmount.toStringAsFixed(2)}'
                    '${before > 0 ? ' (${rateDisplay.toStringAsFixed(0)}%)' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final parsed = double.tryParse(input);
                    double newAmount;
                    if (parsed == null || parsed <= 0) {
                      newAmount = 0;
                    } else if (isRateMode) {
                      if (before <= 0) {
                        newAmount = 0;
                      } else {
                        final rate = parsed.clamp(0, 100);
                        newAmount = before * rate / 100;
                      }
                    } else {
                      newAmount = parsed.clamp(0, before);
                    }
                    setState(() {
                      line.discountAmount = newAmount;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editOrderDiscount(double subtotal) async {
    bool isRateMode = _orderDiscountIsRate;
    String input = '';

    // Release any global focus (e.g. barcode listener) so this dialog can take keyboard input.
    FocusManager.instance.primaryFocus?.unfocus();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final effectiveAmount = () {
              final parsed = double.tryParse(input);
              if (parsed == null || parsed <= 0) {
                return _orderDiscountAmount(subtotal);
              }
              if (isRateMode) {
                if (subtotal <= 0) return 0.0;
                final rate = parsed.clamp(0, 100);
                return subtotal * rate / 100;
              }
              return parsed.clamp(0, subtotal);
            }();
            final rateDisplay = subtotal > 0 ? (effectiveAmount / subtotal) * 100 : 0.0;

            return AlertDialog(
              title: const Text('Order discount'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Amount £'),
                        selected: !isRateMode,
                        onSelected: (sel) {
                          if (!sel) return;
                          setStateDialog(() {
                            isRateMode = false;
                            input = '';
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Rate %'),
                        selected: isRateMode,
                        onSelected: (sel) {
                          if (!sel) return;
                          setStateDialog(() {
                            isRateMode = true;
                            input = '';
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: isRateMode ? 'Discount rate (%)' : 'Discount amount (£)',
                    ),
                    onChanged: (v) {
                      // Uncomment for debugging if needed:
                      // debugPrint('Order discount input: $v');
                      setStateDialog(() => input = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Will apply: £${effectiveAmount.toStringAsFixed(2)}'
                    '${subtotal > 0 ? ' (${rateDisplay.toStringAsFixed(0)}%)' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final parsed = double.tryParse(input);
                    double newAmount;
                    double newValue;
                    bool newIsRate;

                    if (parsed == null || parsed <= 0) {
                      newAmount = 0;
                      newValue = 0;
                      newIsRate = isRateMode;
                    } else if (isRateMode) {
                      if (subtotal <= 0) {
                        newAmount = 0;
                        newValue = 0;
                        newIsRate = true;
                      } else {
                        final rate = parsed.clamp(0, 100);
                        newAmount = subtotal * rate / 100;
                        newValue = rate.toDouble();
                        newIsRate = true;
                      }
                    } else {
                      newAmount = parsed.clamp(0, subtotal);
                      newValue = newAmount;
                      newIsRate = false;
                    }

                    setState(() {
                      _orderDiscountIsRate = newIsRate;
                      _orderDiscountValue = newValue;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showImageEnlarge(String? imageUrl, String productName) {
    if (imageUrl == null || imageUrl.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(productName, style: Theme.of(context).textTheme.titleSmall),
            ),
            CachedProductImage(imageUrl: imageUrl, width: 320, height: 320, fit: BoxFit.contain),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedClientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a wholesale client'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (_selectedStoreId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a store'), backgroundColor: Colors.orange),
      );
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (final line in _lines) {
      if (line.productId == null || line.quantity <= 0) continue;
      items.add({
        'product_id': line.productId,
        'quantity': line.quantity,
        'line_discount_amount': line.discountAmount,
      });
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one product with quantity'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      // Compute order-level discount amount from current lines and discount settings
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      final products = productProvider.products;
      final subtotal = _orderSubtotal(products);
      final orderDiscountAmount = _orderDiscountAmount(subtotal);

      final result = await ApiService.instance.createWholesaleOrder(
        wholesaleClientId: _selectedClientId!,
        storeId: _selectedStoreId!,
        sectorId: _clientSectorId,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        items: items,
        totalDiscount: orderDiscountAmount,
      );
      if (!mounted) return;
      final orderNumber = result['order_number']?.toString() ?? '—';
      setState(() => _submitting = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Submitted'),
          content: Text('Your wholesale order has been submitted for approval.\n\nOrder: $orderNumber'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: ${e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = Provider.of<ProductProvider>(context);
    final products = productProvider.products;
    final subtotal = _orderSubtotal(products);
    final orderDiscountAmount = _orderDiscountAmount(subtotal);
    final orderDiscountRateDisplay =
        subtotal > 0 ? (orderDiscountAmount / subtotal) * 100 : 0.0;
    final totalAfterOrderDiscount =
        (subtotal - orderDiscountAmount).clamp(0, double.infinity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create wholesale order'),
      ),
      body: _loadingStores
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Wholesale client', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          value: _selectedClientId,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: _clients.map((c) {
                            final id = _clientId(c);
                            return DropdownMenuItem(value: id, child: Text(_clientName(c)));
                          }).toList(),
                          onChanged: (v) => setState(() => _selectedClientId = v),
                        ),
                        if (_clientSectorName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Sector pricing: $_clientSectorName — unit prices reflect sector discount',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ),
                        const SizedBox(height: 16),
                        const Text('Store', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          value: _selectedStoreId,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: _stores.map((s) {
                            final id = _storeId(s);
                            return DropdownMenuItem(value: id, child: Text(_storeName(s)));
                          }).toList(),
                          onChanged: (v) => setState(() => _selectedStoreId = v),
                        ),
                        const SizedBox(height: 16),
                        const Text('Notes (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _notesController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Notes for this order',
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            TextButton.icon(
                              onPressed: () => setState(() => _lines.add(_LineItem())),
                              icon: const Icon(Icons.add, size: 20),
                              label: const Text('Add line'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(_lines.length, (index) {
                          final line = _lines[index];
                          final productList = line.productId == null
                              ? <Map<String, dynamic>>[]
                              : products
                                  .cast<Map<String, dynamic>>()
                                  .where((p) => (p['id'] is int ? p['id'] as int : (p['id'] as num).toInt()) == line.productId)
                                  .toList();
                          final product = productList.isEmpty ? null : productList.first;
                          final imageUrl = product?['image_url']?.toString();
                          final productName = product != null ? _productName(product) : '';

                          final unitPrice = product != null ? _unitPrice(product) : 0.0;
                          final beforeDiscount = unitPrice * line.quantity;
                          final lineDiscount = line.discountAmount;
                          final subtotal = (beforeDiscount - lineDiscount).clamp(0, double.infinity);
                          final discountRate = beforeDiscount > 0 ? (lineDiscount / beforeDiscount) * 100 : 0.0;

                          String discountLabel;
                          if (lineDiscount > 0) {
                            final ratePart = discountRate > 0 ? ' (${discountRate.toStringAsFixed(0)}%)' : '';
                            discountLabel = '£${lineDiscount.toStringAsFixed(2)}$ratePart';
                          } else {
                            discountLabel = 'Add discount';
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () => _showImageEnlarge(imageUrl, productName),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: imageUrl != null && imageUrl.isNotEmpty
                                        ? CachedProductImage(imageUrl: imageUrl, width: 44, height: 44, fit: BoxFit.cover)
                                        : Container(
                                            color: Colors.grey[300],
                                            child: const Center(child: Text('?', style: TextStyle(color: Colors.grey))),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<int?>(
                                    value: line.productId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                    ),
                                    hint: const Text('Select product'),
                                    items: [
                                      const DropdownMenuItem<int?>(value: null, child: Text('— Select —')),
                                      ...products.map((p) {
                                        final id = p['id'] is int ? p['id'] as int : (p['id'] as num).toInt();
                                        return DropdownMenuItem<int?>(
                                          value: id,
                                          child: Text(
                                            _productName(p),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }),
                                    ],
                                    onChanged: (v) => setState(() => line.productId = v),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 70,
                                  child: TextFormField(
                                    initialValue: line.quantity.toString(),
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      labelText: 'Qty',
                                      isDense: true,
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                                    onChanged: (v) {
                                      setState(() {
                                        line.quantity = double.tryParse(v) ?? 0;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 90,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '£${unitPrice.toStringAsFixed(2)}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '£${subtotal.toStringAsFixed(2)}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 120,
                                  child: OutlinedButton(
                                    onPressed: product == null ? null : () => _editLineDiscount(line, product),
                                    child: Text(
                                      discountLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: _lines.length > 1
                                      ? () => setState(() => _lines.removeAt(index))
                                      : null,
                                  tooltip: 'Remove line',
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Line total'),
                                  Text('£${subtotal.toStringAsFixed(2)}'),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Order discount'),
                                  OutlinedButton(
                                    onPressed: subtotal <= 0
                                        ? null
                                        : () => _editOrderDiscount(subtotal),
                                    child: Text(
                                      orderDiscountAmount > 0
                                          ? _orderDiscountIsRate
                                              ? '£${orderDiscountAmount.toStringAsFixed(2)} (${orderDiscountRateDisplay.toStringAsFixed(0)}%)'
                                              : '£${orderDiscountAmount.toStringAsFixed(2)}'
                                          : 'Add discount',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total after discount',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '£${totalAfterOrderDiscount.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.grey[200]),
                  child: SafeArea(
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      child: _submitting
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Submit for approval'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
