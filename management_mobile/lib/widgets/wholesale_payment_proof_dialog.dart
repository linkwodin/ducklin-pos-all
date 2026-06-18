import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/payment_transfer_accounts.dart';
import 'date_picker_field.dart';

class WholesalePaymentProofResult {
  const WholesalePaymentProofResult({
    required this.amount,
    required this.transferDate,
    required this.transferredTo,
  });

  final double amount;
  final DateTime transferDate;
  final String transferredTo;
}

class WholesalePaymentProofDialog extends StatefulWidget {
  const WholesalePaymentProofDialog({
    super.key,
    required this.filePaths,
    required this.defaultAmount,
    required this.accountOptions,
  });

  final List<String> filePaths;
  final double defaultAmount;
  final List<String> accountOptions;

  @override
  State<WholesalePaymentProofDialog> createState() => _WholesalePaymentProofDialogState();
}

class _WholesalePaymentProofDialogState extends State<WholesalePaymentProofDialog> {
  late final TextEditingController _amount;
  DateTime? _transferDate;
  String? _transferredTo;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.defaultAmount.toStringAsFixed(2));
    _transferDate = DateTime.now();
    _transferredTo = widget.accountOptions.isNotEmpty ? widget.accountOptions.first : null;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      _showError(l10n.enterValidAmount);
      return;
    }
    if (_transferDate == null) {
      _showError(l10n.selectTransferDate);
      return;
    }
    final account = _transferredTo?.trim() ?? '';
    if (account.isEmpty) {
      _showError(l10n.selectDestinationAccount);
      return;
    }
    Navigator.pop(
      context,
      WholesalePaymentProofResult(
        amount: amount,
        transferDate: _transferDate!,
        transferredTo: account,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accounts = widget.accountOptions.isNotEmpty
        ? widget.accountOptions
        : [defaultPaymentTransferAccount];

    return AlertDialog(
      title: Text(l10n.paymentProofDetails),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.filesSelected(widget.filePaths.length),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.amount,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DatePickerFormField(
              value: _transferDate,
              labelText: l10n.transferDate,
              onChanged: (date) => setState(() => _transferDate = date),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _transferredTo,
              decoration: InputDecoration(
                labelText: l10n.transferredToAccount,
                border: const OutlineInputBorder(),
              ),
              items: accounts
                  .map(
                    (account) => DropdownMenuItem(
                      value: account,
                      child: Text(account),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _transferredTo = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: _submit, child: Text(l10n.saveAndUploadProof)),
      ],
    );
  }
}
