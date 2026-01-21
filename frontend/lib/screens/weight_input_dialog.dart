import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_system/l10n/app_localizations.dart';

class WeightInputDialog extends StatefulWidget {
  const WeightInputDialog({super.key});

  @override
  State<WeightInputDialog> createState() => _WeightInputDialogState();
}

class _WeightInputDialogState extends State<WeightInputDialog> {
  final TextEditingController _weightController = TextEditingController();

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.enterWeight),
      content: TextField(
        controller: _weightController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          // Allow numbers and one decimal point
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],
        decoration: InputDecoration(
          labelText: l10n.weightG,
          hintText: '0.00',
        ),
        autofocus: true,
        onSubmitted: (value) {
          final weight = double.tryParse(value);
          if (weight != null && weight > 0) {
            Navigator.pop(context, weight);
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
            final weight = double.tryParse(_weightController.text);
            if (weight != null && weight > 0) {
              Navigator.pop(context, weight);
            }
          },
          child: Text(l10n.add),
        ),
      ],
    );
  }
}

