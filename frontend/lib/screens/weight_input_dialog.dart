import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/language_provider.dart';
import '../widgets/cached_product_image.dart';

class WeightInputDialog extends StatefulWidget {
  const WeightInputDialog({
    super.key,
    this.product,
    this.initialWeightG,
  });

  final Map<String, dynamic>? product;

  /// Pre-fill weight (grams) from scale barcode scan.
  final double? initialWeightG;

  @override
  State<WeightInputDialog> createState() => _WeightInputDialogState();
}

class _WeightInputDialogState extends State<WeightInputDialog> {
  late final TextEditingController _weightController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialWeightG;
    _weightController = TextEditingController(
      text: initial != null && initial > 0 ? initial.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  String _productName(BuildContext context) {
    final product = widget.product;
    if (product == null) return '';
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    if (languageProvider.locale.languageCode == 'zh') {
      final nameChinese = product['name_chinese']?.toString();
      if (nameChinese != null && nameChinese.isNotEmpty) return nameChinese;
    }
    return product['name']?.toString() ?? '';
  }

  void _submit() {
    final weight = double.tryParse(_weightController.text);
    if (weight != null && weight > 0) {
      Navigator.pop(context, weight);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final product = widget.product;
    final productName = _productName(context);

    return AlertDialog(
      title: Text(l10n.enterWeight),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (product != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CachedProductImage(
                  imageUrl: product['image_url']?.toString(),
                  width: 56,
                  height: 56,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    productName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: l10n.weightG,
              hintText: '0.00',
            ),
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(l10n.add),
        ),
      ],
    );
  }
}
