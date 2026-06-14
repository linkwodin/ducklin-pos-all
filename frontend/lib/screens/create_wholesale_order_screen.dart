import 'package:file_picker/file_picker.dart';
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

class _PoAttachmentFile {
  final String path;
  final String name;

  const _PoAttachmentFile({required this.path, required this.name});
}

class CreateWholesaleOrderScreen extends StatefulWidget {
  const CreateWholesaleOrderScreen({super.key});

  @override
  State<CreateWholesaleOrderScreen> createState() => _CreateWholesaleOrderScreenState();
}

class _CreateWholesaleOrderScreenState extends State<CreateWholesaleOrderScreen> {
  static const _orderChannelOptions = <Map<String, String>>[
    {'value': 'po', 'label': 'Client PO'},
    {'value': 'whatsapp', 'label': 'WhatsApp'},
    {'value': 'wechat', 'label': 'WeChat'},
    {'value': 'email', 'label': 'Email'},
    {'value': 'na', 'label': 'N/A'},
  ];

  List<dynamic> _stores = [];
  List<dynamic> _clients = [];
  int? _selectedStoreId;
  int? _selectedClientId;
  int? _deliveryStoreId;
  DateTime _poDate = DateTime.now();
  String _orderChannel = 'whatsapp';
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _poNumberController = TextEditingController();
  final TextEditingController _paymentTermsController = TextEditingController();
  final TextEditingController _shippingFeeController = TextEditingController();
  final List<_LineItem> _lines = [_LineItem()];
  final List<_PoAttachmentFile> _poAttachments = [];
  bool _orderDiscountIsRate = false; // false = amount in £, true = rate %
  double _orderDiscountValue = 0; // amount or rate, depending on _orderDiscountIsRate
  Map<int, Map<String, dynamic>> _pricingByProductId = {};
  bool _loadingStores = true;
  bool _loadingPricing = false;
  bool _submitting = false;
  bool _submitSucceeded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPricingProducts();
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
          _applyClientDefaults(clientList.first);
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

  Map<String, dynamic>? get _selectedClient {
    if (_selectedClientId == null) return null;
    for (final c in _clients) {
      if (c is Map && _clientId(c) == _selectedClientId) return c.cast<String, dynamic>();
    }
    return null;
  }

  List<Map<String, dynamic>> get _clientDeliveryStores {
    final stores = _selectedClient?['stores'];
    if (stores is! List) return [];
    return stores
        .whereType<Map>()
        .map((s) => s.cast<String, dynamic>())
        .where((s) => s['is_active'] != false)
        .toList();
  }

  void _applyClientDefaults(dynamic client) {
    if (client is! Map) return;
    _paymentTermsController.text = (client['terms'] ?? '').toString();
    _deliveryStoreId = null;
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _deliveryStoreLabel(Map<String, dynamic> s) {
    final name = (s['name'] ?? '').toString();
    final line1 = (s['address_line1'] ?? '').toString();
    final postcode = (s['postcode'] ?? '').toString();
    final parts = <String>[name];
    if (line1.isNotEmpty) parts.add(line1);
    if (postcode.isNotEmpty) parts.add(postcode);
    return parts.join(' — ');
  }

  Future<void> _loadPricingProducts() async {
    setState(() => _loadingPricing = true);
    try {
      final date = _formatDate(_poDate);
      final list = await ApiService.instance.listProducts(
        effectiveFrom: date,
        effectiveTo: date,
      );
      final map = <int, Map<String, dynamic>>{};
      for (final p in list) {
        if (p is! Map) continue;
        final rawId = p['id'];
        final id = rawId is int ? rawId : (rawId as num?)?.toInt();
        if (id != null) map[id] = p.cast<String, dynamic>();
      }
      if (mounted) {
        setState(() {
          _pricingByProductId = map;
          _loadingPricing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPricing = false);
    }
  }

  Future<void> _pickPoDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _poDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _poDate = picked);
      await _loadPricingProducts();
    }
  }

  Map<String, dynamic>? _productForPricing(int? productId, [Map<String, dynamic>? fallback]) {
    if (productId == null) return fallback;
    return _pricingByProductId[productId] ?? fallback;
  }

  bool _isPoAttachmentFile(PlatformFile file) {
    final ext = file.extension?.toLowerCase() ?? '';
    if (ext == 'pdf') return true;
    return const {'jpg', 'jpeg', 'png', 'webp', 'heic', 'gif', 'bmp'}.contains(ext);
  }

  Future<void> _pickPoAttachments() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic', 'gif', 'bmp'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = <_PoAttachmentFile>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null || path.isEmpty || !_isPoAttachmentFile(file)) continue;
      picked.add(_PoAttachmentFile(
        path: path,
        name: file.name.isNotEmpty ? file.name : path.split('/').last,
      ));
    }
    if (picked.isEmpty) return;
    setState(() => _poAttachments.addAll(picked));
  }

  @override
  void dispose() {
    _notesController.dispose();
    _poNumberController.dispose();
    _paymentTermsController.dispose();
    _shippingFeeController.dispose();
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
      // Match management create + server pricing: retail first, then wholesale.
      final directRetail = (cost['direct_retail_online_store_price_gbp'] as num?)?.toDouble() ?? 0.0;
      final wholesale = (cost['wholesale_cost_gbp'] as num?)?.toDouble() ?? 0.0;
      price = directRetail > 0 ? directRetail : wholesale;
    }
    if (price <= 0) {
      price = (product['pos_price'] as num?)?.toDouble() ?? 0.0;
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
    final priced = _productForPricing(line.productId, product) ?? product;
    final unit = _unitPrice(priced);
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
    String discountMode = 'amount'; // amount | rate | per_unit

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        String input = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final effectiveAmount = () {
              final parsed = double.tryParse(input);
              if (parsed == null || parsed <= 0) return tempAmount;
              if (discountMode == 'rate') {
                if (before <= 0) return 0.0;
                final rate = parsed.clamp(0, 100);
                return before * rate / 100;
              }
              if (discountMode == 'per_unit') {
                if (line.quantity <= 0) return 0.0;
                return (parsed * line.quantity).clamp(0, before);
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        label: const Text('Amount £'),
                        selected: discountMode == 'amount',
                        onSelected: (sel) {
                          if (!sel) return;
                          setStateDialog(() {
                            discountMode = 'amount';
                            input = '';
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Rate %'),
                        selected: discountMode == 'rate',
                        onSelected: (sel) {
                          if (!sel) return;
                          setStateDialog(() {
                            discountMode = 'rate';
                            input = '';
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Per unit £'),
                        selected: discountMode == 'per_unit',
                        onSelected: (sel) {
                          if (!sel) return;
                          setStateDialog(() {
                            discountMode = 'per_unit';
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
                      labelText: discountMode == 'rate'
                          ? 'Discount rate (%)'
                          : discountMode == 'per_unit'
                              ? 'Discount per unit (£)'
                              : 'Discount amount (£)',
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
                    } else if (discountMode == 'rate') {
                      if (before <= 0) {
                        newAmount = 0;
                      } else {
                        final rate = parsed.clamp(0, 100);
                        newAmount = before * rate / 100;
                      }
                    } else if (discountMode == 'per_unit') {
                      if (line.quantity <= 0) {
                        newAmount = 0;
                      } else {
                        newAmount = (parsed * line.quantity).clamp(0, before);
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
    if (_submitSucceeded || _submitting) return;
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

      final shippingFee = double.tryParse(_shippingFeeController.text.trim());
      final poNumber = _poNumberController.text.trim();
      final result = await ApiService.instance.createWholesaleOrder(
        wholesaleClientId: _selectedClientId!,
        storeId: _selectedStoreId!,
        sectorId: _clientSectorId,
        wholesaleClientStoreId: _deliveryStoreId,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        poNumber: poNumber.isNotEmpty ? poNumber : null,
        orderChannel: _orderChannel,
        poDate: _formatDate(_poDate),
        paymentTerms: _paymentTermsController.text.trim().isEmpty
            ? null
            : _paymentTermsController.text.trim(),
        shippingFee: shippingFee != null && shippingFee >= 0 ? shippingFee : null,
        items: items,
        totalDiscount: orderDiscountAmount > 0 ? orderDiscountAmount : null,
      );
      if (!mounted) return;
      _submitSucceeded = true;
      final orderId = result['id'] is int
          ? result['id'] as int
          : (result['id'] as num?)?.toInt();
      if (orderId != null && _poAttachments.isNotEmpty) {
        await ApiService.instance.uploadWholesaleOrderPoAttachments(
          orderId,
          _poAttachments.map((f) => f.path).toList(),
        );
      }
      if (!mounted) return;
      final orderNumber = result['order_number']?.toString() ?? '—';
      setState(() => _submitting = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Submitted'),
          content: Text('Your wholesale order has been submitted for approval.\n\nOrder: $orderNumber'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
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
    final shippingFeeAmount =
        double.tryParse(_shippingFeeController.text.trim()) ?? 0.0;
    final grandTotal = totalAfterOrderDiscount +
        (shippingFeeAmount > 0 ? shippingFeeAmount : 0);

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
                          onChanged: (v) {
                            setState(() {
                              _selectedClientId = v;
                              final client = _clients.cast<Map?>().firstWhere(
                                    (c) => c != null && _clientId(c) == v,
                                    orElse: () => null,
                                  );
                              if (client != null) _applyClientDefaults(client);
                            });
                          },
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
                        const Text('Delivery location', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                          value: _deliveryStoreId,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Company address'),
                            ),
                            ..._clientDeliveryStores.map((s) {
                              final id = s['id'] is int ? s['id'] as int : (s['id'] as num).toInt();
                              return DropdownMenuItem<int?>(
                                value: id,
                                child: Text(
                                  _deliveryStoreLabel(s),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: (v) => setState(() => _deliveryStoreId = v),
                        ),
                        const SizedBox(height: 16),
                        const Text('Order channel', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _orderChannel,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: _orderChannelOptions
                              .map(
                                (o) => DropdownMenuItem(
                                  value: o['value'],
                                  child: Text(o['label']!),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _orderChannel = v ?? 'whatsapp'),
                        ),
                        const SizedBox(height: 16),
                        const Text('PO number', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _poNumberController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Client PO number (optional)',
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('PO date', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _pickPoDate,
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(_formatDate(_poDate)),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _loadingPricing
                                ? 'Loading prices for PO date…'
                                : 'Prices reflect PO date and client sector discount.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Payment terms', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _paymentTermsController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'From client terms',
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        const Text('Shipping fee (£)', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _shippingFeeController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: '0.00 (optional)',
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('PO attachment', style: TextStyle(fontWeight: FontWeight.bold)),
                            TextButton.icon(
                              onPressed: _pickPoAttachments,
                              icon: const Icon(Icons.attach_file, size: 20),
                              label: const Text('Add files'),
                            ),
                          ],
                        ),
                        if (_poAttachments.isEmpty)
                          Text(
                            'Optional PDF or images of the client PO',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _poAttachments.asMap().entries.map((e) {
                              final file = e.value;
                              final isPdf = file.name.toLowerCase().endsWith('.pdf');
                              return InputChip(
                                avatar: Icon(isPdf ? Icons.picture_as_pdf : Icons.image_outlined, size: 18),
                                label: Text(file.name, overflow: TextOverflow.ellipsis),
                                onDeleted: () => setState(() => _poAttachments.removeAt(e.key)),
                              );
                            }).toList(),
                          ),
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
                          final pricedProduct =
                              product != null ? _productForPricing(line.productId, product) : null;
                          final imageUrl = product?['image_url']?.toString();
                          final productName = product != null ? _productName(product) : '';

                          final unitPrice =
                              pricedProduct != null ? _unitPrice(pricedProduct) : 0.0;
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
                                    onPressed: pricedProduct == null
                                        ? null
                                        : () => _editLineDiscount(line, pricedProduct),
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
                              if (shippingFeeAmount > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Shipping fee'),
                                    Text('£${shippingFeeAmount.toStringAsFixed(2)}'),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '£${grandTotal.toStringAsFixed(2)}',
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
                      onPressed: (_submitting || _submitSucceeded) ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      child: _submitting
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_submitSucceeded ? 'Submitted' : 'Submit for approval'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
