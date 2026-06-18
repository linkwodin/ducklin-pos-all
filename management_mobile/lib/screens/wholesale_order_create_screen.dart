import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/product.dart';
import '../models/store.dart';
import '../models/wholesale_client.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import 'wholesale_order_detail_screen.dart';

class _LineRow {
  int productId;
  double quantity;
  _LineRow({required this.productId, this.quantity = 1});
}

class WholesaleOrderCreateScreen extends StatefulWidget {
  const WholesaleOrderCreateScreen({super.key});

  @override
  State<WholesaleOrderCreateScreen> createState() => _WholesaleOrderCreateScreenState();
}

class _WholesaleOrderCreateScreenState extends State<WholesaleOrderCreateScreen> {
  var _loading = true;
  var _saving = false;
  List<Store> _stores = [];
  List<Product> _products = [];
  List<WholesaleClient> _clients = [];
  int? _clientId;
  int? _shippingStoreId;
  String _orderChannel = 'po';
  final _poNumber = TextEditingController();
  final _poDate = TextEditingController();
  final _paymentTerms = TextEditingController();
  final _shippingFee = TextEditingController();
  final _notes = TextEditingController();
  final _rows = <_LineRow>[_LineRow(productId: 0)];
  final _attachmentPaths = <String>[];

  WholesaleClient? get _selectedClient =>
      _clientId == null ? null : _clients.where((c) => c.id == _clientId).cast<WholesaleClient?>().firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poNumber.dispose();
    _poDate.dispose();
    _paymentTerms.dispose();
    _shippingFee.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.instance.listStores(),
        ApiService.instance.listProducts(),
        ApiService.instance.listWholesaleClients(),
      ]);
      if (!mounted) return;
      setState(() {
        _stores = results[0] as List<Store>;
        _products = results[1] as List<Product>;
        _clients = results[2] as List<WholesaleClient>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null) {
      setState(() => _attachmentPaths.addAll(result.paths.whereType<String>()));
    }
  }

  Future<void> _submit() async {
    if (_clientId == null || _stores.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final validRows = _rows.where((r) => r.productId > 0 && r.quantity > 0).toList();
    if (validRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.addAtLeastOneProduct)));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'wholesale_client_id': _clientId,
        if (_shippingStoreId != null) 'wholesale_client_store_id': _shippingStoreId,
        'store_id': _stores.first.id,
        if (_orderChannel == 'po' && _poNumber.text.trim().isNotEmpty) 'po_number': _poNumber.text.trim(),
        'order_channel': _orderChannel,
        'po_date': _poDate.text.trim(),
        if (_paymentTerms.text.trim().isNotEmpty) 'payment_terms': _paymentTerms.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'items': validRows.map((r) {
          return {
            'product_id': r.productId,
            'quantity': r.quantity,
            'line_discount_type': 'order_entry',
            'line_discount_amount': 0,
            'line_discount_unit': 0,
          };
        }).toList(),
      };
      final fee = double.tryParse(_shippingFee.text.trim());
      if (fee != null && fee >= 0) body['shipping_fee'] = fee;

      var order = await ApiService.instance.createWholesaleOrder(body);
      if (_orderChannel == 'po' && _poNumber.text.trim().isEmpty) {
        try {
          order = await ApiService.instance.updateWholesaleOrder(order.id, {'po_number': order.orderNumber});
        } catch (_) {}
      }
      if (_attachmentPaths.isNotEmpty) {
        await ApiService.instance.uploadPoAttachments(order.id, _attachmentPaths);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WholesaleOrderDetailScreen(orderId: order.id)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.createWholesaleOrder)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final client = _selectedClient;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.createWholesaleOrder)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int>(
            isExpanded: true,
            value: _clientId,
            decoration: InputDecoration(labelText: l10n.client),
            items: _clients
                .map(
                  (c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis, maxLines: 1),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() {
              _clientId = v;
              _shippingStoreId = null;
              final c = _clients.firstWhere((x) => x.id == v);
              _paymentTerms.text = c.terms ?? '';
            }),
          ),
          if (client != null && client.stores.isNotEmpty)
            DropdownButtonFormField<int?>(
              isExpanded: true,
              value: _shippingStoreId,
              decoration: InputDecoration(labelText: l10n.deliveryLocation),
              items: [
                DropdownMenuItem(value: null, child: Text(l10n.companyAddress)),
                ...client.stores.map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.name, overflow: TextOverflow.ellipsis, maxLines: 1),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _shippingStoreId = v),
            ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: _orderChannel,
            decoration: InputDecoration(labelText: l10n.orderChannel),
            items: [
              DropdownMenuItem(value: 'po', child: Text(l10n.sourceClientPo)),
              DropdownMenuItem(value: 'whatsapp', child: Text(l10n.sourceWhatsapp)),
              DropdownMenuItem(value: 'email', child: Text(l10n.sourceEmail)),
              DropdownMenuItem(value: 'na', child: Text(l10n.sourceNa)),
            ],
            onChanged: (v) => setState(() => _orderChannel = v ?? 'po'),
          ),
          TextField(controller: _poNumber, decoration: InputDecoration(labelText: l10n.poNumber)),
          TextField(controller: _poDate, decoration: InputDecoration(labelText: l10n.poDate)),
          TextField(controller: _paymentTerms, decoration: InputDecoration(labelText: l10n.paymentTerms)),
          TextField(
            controller: _shippingFee,
            decoration: InputDecoration(labelText: l10n.shippingFee),
            keyboardType: TextInputType.number,
          ),
          TextField(controller: _notes, decoration: InputDecoration(labelText: l10n.notes), maxLines: 3),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.lineItems, style: Theme.of(context).textTheme.titleMedium),
              IconButton(onPressed: () => setState(() => _rows.add(_LineRow(productId: 0))), icon: const Icon(Icons.add)),
            ],
          ),
          ...List.generate(_rows.length, (index) {
            final row = _rows[index];
            final product = _products.where((p) => p.id == row.productId).cast<Product?>().firstOrNull;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: row.productId == 0 ? null : row.productId,
                      decoration: InputDecoration(labelText: l10n.product),
                      items: _products
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                p.displayName(),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => row.productId = v ?? 0),
                    ),
                    TextField(
                      decoration: InputDecoration(labelText: l10n.quantity),
                      keyboardType: TextInputType.number,
                      controller: TextEditingController(text: '${row.quantity}'),
                      onChanged: (v) => row.quantity = double.tryParse(v) ?? 0,
                    ),
                    if (product != null)
                      Text(l10n.unitPrice(formatMoney(product.unitPriceForSector(client?.sectorId)))),
                    if (_rows.length > 1)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          onPressed: () => setState(() => _rows.removeAt(index)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: _pickAttachments,
            icon: const Icon(Icons.attach_file),
            label: Text(l10n.poAttachments(_attachmentPaths.length)),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.createOrder),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
