import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/stock_provider.dart';
import '../providers/notification_bar_provider.dart';
import '../providers/product_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import 'stocktake_flow_screen.dart';
import 'package:intl/intl.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _isLoading = false;
  bool _isLoadingIncoming = false;
  String? _errorMessage;
  int? _selectedStoreId;
  List<dynamic> _incomingStock = [];
  String _searchQuery = '';
  String _sortBy = 'name'; // name, qty_desc, qty_asc
  String _stockFilter = 'all'; // all, in_stock, out_of_stock

  @override
  void initState() {
    super.initState();
    _loadInventory();
    _loadIncomingStock();
  }

  Future<void> _loadInventory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get store ID from device info or use default
      final deviceInfo = await DatabaseService.instance.getDeviceInfo();
      final storeId = deviceInfo?['store_id'] as int? ?? 1;

      setState(() {
        _selectedStoreId = storeId;
      });

      final stockProvider = Provider.of<StockProvider>(context, listen: false);
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      
      // Load products first if not loaded
      if (productProvider.products.isEmpty) {
        await productProvider.loadProducts();
      }
      
      // Sync stock
      await stockProvider.syncStock(storeId);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadIncomingStock() async {
    setState(() {
      _isLoadingIncoming = true;
    });

    try {
      final deviceInfo = await DatabaseService.instance.getDeviceInfo();
      final storeId = deviceInfo?['store_id'] as int? ?? 1;

      final incoming = await ApiService.instance.getIncomingStock(storeId: storeId);
      setState(() {
        _incomingStock = incoming;
        _isLoadingIncoming = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingIncoming = false;
      });
      if (mounted) {
        context.showNotification('Failed to load incoming stock: $e', isError: true);
      }
    }
  }

  void _openStocktakeMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Day start'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StocktakeFlowScreen(type: 'day_start')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.nightlight_round_outlined),
              title: const Text('Day end'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StocktakeFlowScreen(type: 'day_end')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getProductName(Map<String, dynamic> product, BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final currentLocale = languageProvider.locale;
    
    // If locale is Chinese (zh_CN or zh_TW), use name_chinese if available
    if (currentLocale.languageCode == 'zh') {
      final nameChinese = product['name_chinese']?.toString();
      if (nameChinese != null && nameChinese.isNotEmpty) {
        return nameChinese;
      }
    }
    
    // Otherwise, use the English name
    return product['name']?.toString() ?? '';
  }

  Future<void> _updateStock(
    int productId,
    int storeId,
    double currentQuantity,
    String productName,
  ) async {
    final quantityController = TextEditingController(
      text: currentQuantity.toStringAsFixed(2),
    );
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Stock: $productName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: quantityController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  hintText: '0.00',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g., manual adjustment, received stock',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final quantity = double.tryParse(quantityController.text);
              if (quantity != null && quantity >= 0) {
                Navigator.pop(context, true);
              } else {
                context.showNotification('Please enter a valid quantity', isError: true);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final quantity = double.parse(quantityController.text);
        final reason = reasonController.text.trim();

        await ApiService.instance.updateStock(
          productId,
          storeId,
          quantity: quantity,
          reason: reason.isNotEmpty ? reason : 'manual_update',
        );

        // Reload inventory
        await _loadInventory();

        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          context.showNotification(l10n.stockUpdatedSuccessfully, isSuccess: true);
        }
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          context.showNotification(l10n.failedToUpdateStock(e.toString()), isError: true);
        }
      }
    }
  }

  Future<void> _confirmReceipt(int orderId) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmReceipt),
        content: Text(l10n.confirmReceiptMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.instance.receiveRestockOrder(orderId);

        // Reload both inventory and incoming stock
        await _loadInventory();
        await _loadIncomingStock();

        if (mounted) {
          context.showNotification(l10n.stockReceiptConfirmed, isSuccess: true);
        }
      } catch (e) {
        if (mounted) {
          context.showNotification(l10n.failedToConfirmReceipt(e.toString()), isError: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final stockProvider = Provider.of<StockProvider>(context);
    final productProvider = Provider.of<ProductProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inventoryManagement),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadInventory();
              _loadIncomingStock();
            },
            tooltip: l10n.refresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text('Error: $_errorMessage'))
              : DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      if (_selectedStoreId != null)
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.store),
                                  const SizedBox(width: 8),
                                  Text(l10n.storeID(_selectedStoreId!)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      TabBar(
                        tabs: [
                          Tab(text: l10n.currentStock, icon: const Icon(Icons.inventory)),
                          Tab(text: l10n.incomingStock, icon: const Icon(Icons.local_shipping)),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // Current Stock Tab - Show all products including those with 0 stock,
                            // with search, sort, and filter controls.
                            productProvider.products.isEmpty
                                ? Center(
                                    child: Text(l10n.noProductsAvailable),
                                  )
                                : Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                                        child: Row(
                                          children: [
                                            // Search by product name
                                            Expanded(
                                              child: TextField(
                                                decoration: InputDecoration(
                                                  isDense: true,
                                                  prefixIcon: const Icon(Icons.search),
                                                  border: const OutlineInputBorder(),
                                                  hintText: l10n.searchProducts,
                                                ),
                                                onChanged: (value) {
                                                  setState(() {
                                                    _searchQuery = value.trim();
                                                  });
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Sort menu
                                            PopupMenuButton<String>(
                                              tooltip: 'Sort',
                                              icon: const Icon(Icons.sort),
                                              onSelected: (value) {
                                                setState(() {
                                                  _sortBy = value;
                                                });
                                              },
                                              itemBuilder: (context) => [
                                                const PopupMenuItem(
                                                  value: 'name',
                                                  child: Text('Name (A–Z)'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'qty_desc',
                                                  child: Text('Quantity (High → Low)'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'qty_asc',
                                                  child: Text('Quantity (Low → High)'),
                                                ),
                                              ],
                                            ),
                                            // Filter menu
                                            PopupMenuButton<String>(
                                              tooltip: 'Filter',
                                              icon: const Icon(Icons.filter_alt),
                                              onSelected: (value) {
                                                setState(() {
                                                  _stockFilter = value;
                                                });
                                              },
                                              itemBuilder: (context) => const [
                                                PopupMenuItem(
                                                  value: 'all',
                                                  child: Text('All'),
                                                ),
                                                PopupMenuItem(
                                                  value: 'in_stock',
                                                  child: Text('In stock (> 0)'),
                                                ),
                                                PopupMenuItem(
                                                  value: 'out_of_stock',
                                                  child: Text('Out of stock (0 only)'),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 1),
                                      Expanded(
                                        child: Builder(
                                          builder: (context) {
                                            final storeId = _selectedStoreId ?? 1;

                                            // Build list with quantities
                                            final List<Map<String, dynamic>> productsWithStock = [];
                                            for (final product in productProvider.products) {
                                              final productId = product['id'] as int;
                                              final stockKey = '${productId}_$storeId';
                                              double quantity = 0.0;
                                              if (stockProvider.stock.containsKey(stockKey)) {
                                                quantity = (stockProvider.stock[stockKey]!['quantity'] as num).toDouble();
                                              }
                                              final name = _getProductName(product, context);
                                              productsWithStock.add({
                                                'product': product,
                                                'name': name,
                                                'quantity': quantity,
                                              });
                                            }

                                            // Apply search filter
                                            var visible = productsWithStock.where((item) {
                                              final name = (item['name'] as String).toLowerCase();
                                              final q = _searchQuery.toLowerCase();
                                              if (q.isNotEmpty && !name.contains(q)) {
                                                return false;
                                              }
                                              final qty = (item['quantity'] as double);
                                              if (_stockFilter == 'in_stock' && qty <= 0) return false;
                                              if (_stockFilter == 'out_of_stock' && qty != 0) return false;
                                              return true;
                                            }).toList();

                                            // Sort
                                            visible.sort((a, b) {
                                              if (_sortBy == 'qty_desc' || _sortBy == 'qty_asc') {
                                                final qa = (a['quantity'] as double);
                                                final qb = (b['quantity'] as double);
                                                final cmp = qa.compareTo(qb);
                                                return _sortBy == 'qty_desc' ? -cmp : cmp;
                                              }
                                              final na = (a['name'] as String).toLowerCase();
                                              final nb = (b['name'] as String).toLowerCase();
                                              return na.compareTo(nb);
                                            });

                                            if (visible.isEmpty) {
                                              return Center(
                                                child: Text(l10n.noProductsAvailable),
                                              );
                                            }

                                            return ListView.builder(
                                              itemCount: visible.length,
                                              itemBuilder: (context, index) {
                                                final item = visible[index];
                                                final product = item['product'] as Map<String, dynamic>;
                                                final productId = product['id'] as int;
                                                final productName = item['name'] as String;
                                                final quantity = item['quantity'] as double;
                                                final isZeroStock = quantity == 0.0;

                                                return ListTile(
                                                  title: Text(productName),
                                                  subtitle: Text(l10n.storeID(storeId)),
                                                  trailing: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        l10n.qty(quantity.toStringAsFixed(2)),
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.bold,
                                                          color: isZeroStock ? Colors.red : Colors.black,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      IconButton(
                                                        icon: const Icon(Icons.edit),
                                                        onPressed: () => _updateStock(
                                                          productId,
                                                          storeId,
                                                          quantity,
                                                          productName,
                                                        ),
                                                        tooltip: 'Update Stock',
                                                      ),
                                                    ],
                                                  ),
                                                  tileColor: isZeroStock ? Colors.red[50] : null,
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                            // Incoming Stock Tab
                            _isLoadingIncoming
                                ? const Center(child: CircularProgressIndicator())
                                : _incomingStock.isEmpty
                                    ? const Center(
                                        child: Text('No incoming stock orders'),
                                      )
                                    : ListView.builder(
                                        itemCount: _incomingStock.length,
                                        itemBuilder: (context, index) {
                                          final order = _incomingStock[index];
                                          final orderId = order['id'] as int;
                                          final status = order['status'] as String;
                                          final trackingNumber = order['tracking_number'] as String?;
                                          final initiatedAt = order['initiated_at'] as String?;
                                          final items = order['items'] as List<dynamic>? ?? [];

                                          String formattedDate = 'N/A';
                                          if (initiatedAt != null) {
                                            try {
                                              final date = DateTime.parse(initiatedAt);
                                              formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(date);
                                            } catch (e) {
                                              formattedDate = initiatedAt;
                                            }
                                          }

                                          return Card(
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            child: ExpansionTile(
                                              title: Text(l10n.orderNumber(orderId.toString())),
                                              subtitle: Text(
                                                '${l10n.status}: ${status.toUpperCase()} | ${l10n.date}: $formattedDate',
                                              ),
                                              trailing: status == 'in_transit' || status == 'initiated'
                                                  ? ElevatedButton.icon(
                                                      icon: const Icon(Icons.check),
                                                      label: Text(l10n.confirm),
                                                      onPressed: () => _confirmReceipt(orderId),
                                                    )
                                                  : null,
                                              children: [
                                                if (trackingNumber != null && trackingNumber.isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 8,
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.local_shipping, size: 16),
                                                        const SizedBox(width: 8),
                                                        Text('${l10n.tracking}: $trackingNumber'),
                                                      ],
                                                    ),
                                                  ),
                                                const Divider(),
                                                ...items.map((item) {
                                                  final product = item['product'] as Map<String, dynamic>?;
                                                  final productName = product != null 
                                                      ? _getProductName(product, context)
                                                      : l10n.unknownProduct;
                                                  final quantity = (item['quantity'] as num).toDouble();

                                                  return ListTile(
                                                    dense: true,
                                                    title: Text(productName),
                                                    trailing: Text(
                                                      l10n.qty(quantity.toStringAsFixed(2)),
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openStocktakeMenu,
        tooltip: 'Stocktake',
        child: const Icon(Icons.checklist),
      ),
    );
  }
}

