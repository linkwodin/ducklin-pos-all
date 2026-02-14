import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/order_provider.dart';
import '../providers/language_provider.dart';
import '../widgets/cached_product_image.dart';

class CartScreen extends StatelessWidget {
  /// Called when the update-quantity dialog opens (e.g. to disable barcode autofocus).
  final VoidCallback? onQuantityDialogOpen;
  /// Called when the update-quantity dialog closes (e.g. to re-enable barcode autofocus).
  final VoidCallback? onQuantityDialogClose;

  const CartScreen({super.key, this.onQuantityDialogOpen, this.onQuantityDialogClose});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final orderProvider = Provider.of<OrderProvider>(context);

    if (orderProvider.cartItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(l10n.noData),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: orderProvider.cartItems.length,
            itemBuilder: (context, index) {
              final item = orderProvider.cartItems[index];
              final product = item['product'] as Map<String, dynamic>;
              final quantity = (item['quantity'] as num).toDouble();
              final unitType = product['unit_type'] ?? 'quantity';

              final imageUrl = (product['image_url'] ?? '').toString().trim();
              return ListTile(
                leading: imageUrl.isNotEmpty
                    ? CachedProductImage(
                        imageUrl: imageUrl,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey[200],
                        child: const Center(
                          child: Text(
                            '?',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                title: Text(_getProductName(product, context)),
                subtitle: Text(
                  unitType == 'weight'
                      ? l10n.weightDisplay(quantity.toStringAsFixed(2))
                      : l10n.qty(quantity.toStringAsFixed(0)),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('£${(item['line_total'] as num).toStringAsFixed(2)}'),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => orderProvider.removeFromCart(product['id']),
                    ),
                  ],
                ),
                onTap: () => _showQuantityDialog(context, orderProvider, item, onQuantityDialogOpen: onQuantityDialogOpen, onQuantityDialogClose: onQuantityDialogClose),
              );
            },
          ),
        ),
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Notification message
              if (orderProvider.lastAddedMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          orderProvider.lastAddedMessage!,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              _buildSummaryRow(l10n.subtotal, orderProvider.subtotal),
              if (orderProvider.discountAmount > 0)
                _buildSummaryRow(l10n.discount, -orderProvider.discountAmount, isDiscount: true),
              const Divider(),
              _buildSummaryRow(l10n.total, orderProvider.total, isTotal: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isDiscount = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '£${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isDiscount ? Colors.green : null,
            ),
          ),
        ],
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

  void _showQuantityDialog(
    BuildContext context,
    OrderProvider orderProvider,
    Map<String, dynamic> item, {
    VoidCallback? onQuantityDialogOpen,
    VoidCallback? onQuantityDialogClose,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final product = item['product'] as Map<String, dynamic>;
    final currentQuantity = (item['quantity'] as num).toDouble();
    final unitType = product['unit_type'] ?? 'quantity';
    final isWeight = unitType == 'weight';

    final TextEditingController quantityController = TextEditingController(
      text: currentQuantity.toStringAsFixed(isWeight ? 2 : 0),
    );

    onQuantityDialogOpen?.call();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_getProductName(product, context)),
        content: TextField(
          controller: quantityController,
          keyboardType: TextInputType.numberWithOptions(decimal: isWeight),
          inputFormatters: [
            if (isWeight)
              // For weight: allow numbers and one decimal point (up to 2 decimal places)
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
            else
              // For quantity: only allow integers (no decimal point)
              FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: isWeight ? l10n.weightG : l10n.quantity,
            hintText: currentQuantity.toStringAsFixed(isWeight ? 2 : 0),
          ),
          autofocus: true,
          onSubmitted: (value) {
            final newQuantity = double.tryParse(value);
            if (newQuantity != null && newQuantity > 0) {
              orderProvider.updateCartItemQuantity(product['id'], newQuantity);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final newQuantity = double.tryParse(quantityController.text);
              if (newQuantity != null && newQuantity > 0) {
                orderProvider.updateCartItemQuantity(product['id'], newQuantity);
                Navigator.pop(context);
              }
            },
            child: Text(l10n.update),
          ),
        ],
      ),
    ).then((_) => onQuantityDialogClose?.call());
  }
}

