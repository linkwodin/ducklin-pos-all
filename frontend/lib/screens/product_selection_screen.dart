import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/product_provider.dart';
import '../providers/order_provider.dart';
import '../providers/language_provider.dart';
import 'barcode_scanner_screen.dart';
import 'weight_input_dialog.dart';

class ProductSelectionScreen extends StatefulWidget {
  const ProductSelectionScreen({super.key});

  @override
  State<ProductSelectionScreen> createState() => _ProductSelectionScreenState();
}

class _ProductSelectionScreenState extends State<ProductSelectionScreen> {
  String? _selectedCategory;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String? _notificationMessage;

  @override
  void initState() {
    super.initState();
    // Load products when screen is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      productProvider.loadProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final productProvider = Provider.of<ProductProvider>(context);
    final orderProvider = Provider.of<OrderProvider>(context);

    List<Map<String, dynamic>> products;
    if (_searchQuery.isNotEmpty) {
      products = productProvider.searchProducts(_searchQuery);
    } else if (_selectedCategory != null) {
      products = productProvider.getProductsByCategory(_selectedCategory);
    } else {
      products = productProvider.products;
    }

    return Stack(
      children: [
        Column(
          children: [
            // Search and filter bar
            Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.searchProducts,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: () => _scanBarcode(context, orderProvider),
                        tooltip: l10n.scanBarcode,
                      ),
                    ],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                onSubmitted: (value) async {
                  // When Enter is pressed, check if it's an exact barcode match
                  if (value.isNotEmpty) {
                    await _handleBarcodeEnter(value, orderProvider);
                  } else {
                    setState(() => _searchQuery = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              // Category filter
              if (productProvider.categories.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildCategoryChip(null, l10n.all),
                      ...productProvider.categories.map(
                        (cat) => _buildCategoryChip(cat, cat),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Product grid
        Expanded(
          child: productProvider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty
                                ? l10n.noProductsFound(_searchQuery)
                                : _selectedCategory != null
                                    ? l10n.noProductsInCategory(_selectedCategory!)
                                    : l10n.noProductsAvailable,
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          if (_searchQuery.isNotEmpty || _selectedCategory != null) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _selectedCategory = null;
                                });
                              },
                              child: Text(l10n.clearFilters),
                            ),
                          ],
                        ],
                      ),
                    )
                  : _searchQuery.isNotEmpty
                      ? ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final product = products[index];
                            return _buildProductListItem(product, orderProvider);
                          },
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.2,
                          ),
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final product = products[index];
                            return _buildProductCard(product, orderProvider);
                          },
                        ),
        ),
          ],
        ),
        if (_notificationMessage != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              elevation: 6,
              color: _notificationMessage!.toLowerCase().contains('error') || 
                     _notificationMessage!.toLowerCase().contains('not found') ||
                     _notificationMessage!.toLowerCase().contains('failed')
                  ? Colors.red 
                  : Colors.green,
              child: SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        _notificationMessage!.toLowerCase().contains('error') || 
                        _notificationMessage!.toLowerCase().contains('not found') ||
                        _notificationMessage!.toLowerCase().contains('failed')
                            ? Icons.error
                            : Icons.check_circle,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _notificationMessage!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () {
                          setState(() {
                            _notificationMessage = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showTopNotification(String message, {bool isSuccess = true}) {
    setState(() {
      _notificationMessage = message;
    });
    // Auto-hide after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _notificationMessage = null;
        });
      }
    });
  }

  Widget _buildCategoryChip(String? category, String label) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _selectedCategory = selected ? category : null);
        },
      ),
    );
  }

  Widget _buildProductCard(
    Map<String, dynamic> product,
    OrderProvider orderProvider,
  ) {
    final unitType = product['unit_type'] ?? 'quantity';
    final isWeight = unitType == 'weight';

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _addProductToCart(product, orderProvider, isWeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                color: Colors.grey[100],
                child: product['image_url'] != null
                    ? Image.network(
                        product['image_url'],
                        fit: BoxFit.contain, // Show full image maintaining aspect ratio
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.image, size: 32),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.image, size: 32, color: Colors.grey),
                      ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _getProductName(product, context),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getProductPrice(product),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductListItem(
    Map<String, dynamic> product,
    OrderProvider orderProvider,
  ) {
    final unitType = product['unit_type'] ?? 'quantity';
    final isWeight = unitType == 'weight';

    return ListTile(
      leading: product['image_url'] != null
          ? Image.network(
              product['image_url'],
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 40,
                height: 40,
                color: Colors.grey[200],
                child: const Icon(Icons.image, size: 24),
              ),
            )
          : Container(
              width: 40,
              height: 40,
              color: Colors.grey[200],
              child: const Icon(Icons.image, size: 24),
            ),
      title: Text(
        _getProductName(product, context),
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '${_getProductPrice(product)}${isWeight ? '/kg' : ''}',
        style: const TextStyle(fontSize: 12),
      ),
      onTap: () => _addProductToCart(product, orderProvider, isWeight),
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

  String _getProductPrice(Map<String, dynamic> product) {
    // Use pos_price if available (calculated by backend with sector discount)
    final posPrice = (product['pos_price'] as num?)?.toDouble();
    if (posPrice != null && posPrice > 0) {
      return '£${posPrice.toStringAsFixed(2)}';
    }
    
    // Fallback to current_cost if pos_price not available
    final cost = product['current_cost'];
    if (cost != null && cost is Map) {
      // Try direct_retail_online_store_price_gbp first
      final directRetailPrice = (cost['direct_retail_online_store_price_gbp'] as num?)?.toDouble();
      if (directRetailPrice != null && directRetailPrice > 0) {
        return '£${directRetailPrice.toStringAsFixed(2)}';
      }
      // Fallback to wholesale_cost_gbp
      final price = (cost['wholesale_cost_gbp'] as num?)?.toDouble() ?? 0.0;
      return '£${price.toStringAsFixed(2)}';
    }
    return '£0.00';
  }

  Future<void> _addProductToCart(
    Map<String, dynamic> product,
    OrderProvider orderProvider,
    bool isWeight,
  ) async {
    if (isWeight) {
      // Show weight input dialog
      final weight = await showDialog<double>(
        context: context,
        builder: (_) => WeightInputDialog(),
      );
      if (weight != null && weight > 0) {
        final l10n = AppLocalizations.of(context)!;
        orderProvider.addToCart(product, weight: weight, message: l10n.addedWeightToCart(weight));
      }
    } else {
      final l10n = AppLocalizations.of(context)!;
      orderProvider.addToCart(product, quantity: 1, message: l10n.addedToCart);
    }
  }

  Future<void> _handleBarcodeEnter(
    String barcode,
    OrderProvider orderProvider,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    
    // Try to find product by exact barcode match
    Map<String, dynamic>? product;
    final allProducts = productProvider.products;
    try {
      product = allProducts.firstWhere(
        (p) => (p['barcode'] ?? '').toString().trim() == barcode.trim(),
      );
    } catch (e) {
      // Product not found in memory, try database lookup
      product = await productProvider.getProductByBarcode(barcode.trim());
    }
    
    if (product != null && product.isNotEmpty && mounted) {
      final unitType = product['unit_type'] ?? 'quantity';
      final isWeight = unitType == 'weight';
      // Clear search
      _searchController.clear();
      setState(() => _searchQuery = '');
      
      // Add to cart with message
      final productName = _getProductName(product, context);
      if (isWeight) {
        final weight = await showDialog<double>(
          context: context,
          builder: (_) => WeightInputDialog(),
        );
        if (weight != null && weight > 0) {
          orderProvider.addToCart(product, weight: weight, message: l10n.productAddedToCart(productName));
        }
      } else {
        orderProvider.addToCart(product, quantity: 1, message: l10n.productAddedToCart(productName));
      }
    } else {
      // Not an exact barcode match, treat as search query
      setState(() => _searchQuery = barcode);
      
      if (mounted) {
        _showTopNotification(l10n.noProductsFound(barcode), isSuccess: false);
      }
    }
  }

  Future<void> _scanBarcode(
    BuildContext context,
    OrderProvider orderProvider,
  ) async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
      );

      if (result != null && result is String && result.isNotEmpty) {
        await _handleBarcodeEnter(result, orderProvider);
      }
    } catch (e) {
      if (mounted) {
        _showTopNotification('Error scanning barcode: $e', isSuccess: false);
      }
    }
  }
}

