import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/order_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../widgets/cached_product_image.dart';
import 'shipment_packing_detail_screen.dart';
import 'create_wholesale_order_screen.dart';

class WholesalePackingScreen extends StatefulWidget {
  final VoidCallback? onShipmentsChanged;
  const WholesalePackingScreen({super.key, this.onShipmentsChanged});

  @override
  State<WholesalePackingScreen> createState() => _WholesalePackingScreenState();
}

class _WholesalePackingScreenState extends State<WholesalePackingScreen> {
  List<dynamic> _shipments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final storeId = orderProvider.storeId;
    if (storeId == null) {
      setState(() {
        _loading = false;
        _error = 'Store not set';
        _shipments = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.instance.listShipments(storeId: storeId);
      setState(() {
        _shipments = list;
        _loading = false;
      });
      widget.onShipmentsChanged?.call();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
        _shipments = [];
        _loading = false;
      });
    }
  }

  String _productName(dynamic item, bool useChinese) {
    final p = item is Map ? item['product'] : null;
    if (p is! Map) return 'Product #${item is Map ? item['product_id'] : '?'}';
    final name = p['name']?.toString() ?? '';
    final zh = p['name_chinese']?.toString();
    if (useChinese && zh != null && zh.isNotEmpty) return zh;
    return name.isNotEmpty ? name : (zh ?? 'Product #${item['product_id']}');
  }

  void _showImageEnlarge(BuildContext context, String? imageUrl, String productName) {
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

  void _openUrl(String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delivery note'),
        content: SelectableText(url),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = Provider.of<OrderProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final useChinese = languageProvider.locale.languageCode == 'zh';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wholesale packing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateWholesaleOrderScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Create wholesale order'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 16),
                        FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _shipments.isEmpty
                  ? const Center(child: Text('No shipments to pack for this store'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _shipments.length,
                        itemBuilder: (context, index) {
                          final shipment = _shipments[index] as Map<String, dynamic>;
                          final shipmentId = shipment['id'] is int ? shipment['id'] as int : (shipment['id'] as num).toInt();
                          final order = shipment['wholesale_order'] as Map<String, dynamic>?;
                          final orderNumber = order?['order_number']?.toString() ?? '—';
                          final client = order?['wholesale_client'] as Map<String, dynamic>?;
                          final clientName = client?['name']?.toString() ?? '—';
                          final status = shipment['status']?.toString() ?? 'packing';
                          final isCompleted = status == 'completed';
                          final deliveryNoteUrl = shipment['delivery_note_pdf_url']?.toString();
                          final items = shipment['items'] as List<dynamic>? ?? [];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          orderNumber,
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isCompleted ? Colors.green[100] : Colors.orange[100],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          isCompleted ? 'Completed' : 'Packing',
                                          style: Theme.of(context).textTheme.labelMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (clientName != '—')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(clientName, style: Theme.of(context).textTheme.bodySmall),
                                    ),
                                  const SizedBox(height: 12),
                                  ...items.map<Widget>((si) {
                                    final woItem = si is Map ? si['wholesale_order_item'] as Map<String, dynamic>? : null;
                                    if (woItem == null) return const SizedBox.shrink();
                                    final qty = woItem['quantity'] is num ? (woItem['quantity'] as num).toDouble() : 0.0;
                                    final qtyStr = qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
                                    final product = woItem['product'] as Map<String, dynamic>?;
                                    final imageUrl = product?['image_url']?.toString();
                                    final productName = _productName(woItem, useChinese);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () => _showImageEnlarge(context, imageUrl, productName),
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
                                          Expanded(child: Text('$productName × $qtyStr')),
                                        ],
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 12),
                                  if (isCompleted && deliveryNoteUrl != null && deliveryNoteUrl.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.picture_as_pdf),
                                        label: const Text('View delivery note'),
                                        onPressed: () => _openUrl(deliveryNoteUrl),
                                      ),
                                    )
                                  else if (!isCompleted)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: FilledButton.icon(
                                        icon: const Icon(Icons.qr_code_scanner),
                                        label: const Text('Pack (scan items)'),
                                        onPressed: () async {
                                          await Navigator.push<void>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ShipmentPackingDetailScreen(
                                                shipment: shipment,
                                                onCompleted: _load,
                                              ),
                                            ),
                                          );
                                          _load();
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
