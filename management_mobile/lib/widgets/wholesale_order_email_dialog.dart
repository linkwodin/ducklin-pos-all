import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/wholesale_order.dart';
import '../utils/formatters.dart';
import '../utils/wholesale_order_email.dart';

class WholesaleOrderEmailDialog extends StatefulWidget {
  const WholesaleOrderEmailDialog({
    super.key,
    required this.order,
    required this.data,
  });

  final WholesaleOrder order;
  final WholesaleEmailDialogData data;

  @override
  State<WholesaleOrderEmailDialog> createState() => _WholesaleOrderEmailDialogState();
}

class _WholesaleOrderEmailDialogState extends State<WholesaleOrderEmailDialog> {
  late final TextEditingController _toController;
  late final TextEditingController _ccController;
  late final TextEditingController _bccController;
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  late Map<String, bool> _attachments;
  String? _error;

  WholesaleOrder get order => widget.order;
  WholesaleOrderEmailType get emailType => widget.data.emailType;
  WholesaleEmailResendSummary? get resendSummary => widget.data.resendSummary;

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController(text: widget.data.to);
    _ccController = TextEditingController(text: widget.data.cc);
    _bccController = TextEditingController(text: widget.data.bcc);
    _subjectController = TextEditingController(text: widget.data.subject);
    _messageController = TextEditingController(text: widget.data.message);
    _attachments = Map<String, bool>.from(widget.data.attachments);
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _dialogTitle(AppLocalizations l10n) {
    if (resendSummary != null && !resendSummary!.skipped) return l10n.resendEmail;
    return switch (emailType) {
      WholesaleOrderEmailType.orderConfirm => l10n.sendOrderConfirmationEmail,
      WholesaleOrderEmailType.shipmentsDelivered => l10n.sendDeliveryCompleteEmail,
      WholesaleOrderEmailType.invoice => l10n.sendInvoiceEmail,
    };
  }

  String _emailDescription(AppLocalizations l10n) {
    return switch (emailType) {
      WholesaleOrderEmailType.orderConfirm => l10n.sendOrderConfirmationEmailDescription,
      WholesaleOrderEmailType.shipmentsDelivered => l10n.sendDeliveryCompleteEmailDescription,
      WholesaleOrderEmailType.invoice => l10n.sendInvoiceEmailDescription,
    };
  }

  List<WholesaleEmailAttachmentOption> get _attachmentOptions {
    final all = buildWholesaleEmailAttachmentOptions(order);
    final allowed = wholesaleOrderEmailAttachmentKinds[emailType] ?? const [];
    return all.where((opt) => allowed.contains(opt.key)).toList();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    final toList = dedupeEmailList([_toController.text]);
    if (toList.isEmpty) {
      setState(() => _error = l10n.emailRecipientsRequired);
      return;
    }
    for (final email in toList) {
      if (!isValidEmailAddress(email)) {
        setState(() => _error = l10n.invalidEmailAddress(email));
        return;
      }
    }
    for (final email in dedupeEmailList([_ccController.text, _bccController.text])) {
      if (!isValidEmailAddress(email)) {
        setState(() => _error = l10n.invalidEmailAddress(email));
        return;
      }
    }
    final selectedAttachments = _attachments.entries.where((e) => e.value).map((e) => e.key).toList();
    if (selectedAttachments.isEmpty) {
      setState(() => _error = l10n.selectAtLeastOneAttachment);
      return;
    }

    final shipmentIds = emailType == WholesaleOrderEmailType.shipmentsDelivered
        ? order.shipments.map((s) => s.id).toList()
        : null;

    Navigator.pop(
      context,
      WholesaleEmailSendRequest(
        emailType: emailType,
        to: toList,
        cc: dedupeEmailList([_ccController.text]),
        bcc: dedupeEmailList([_bccController.text]),
        subject: _subjectController.text.trim(),
        message: _messageController.text.trim(),
        attachments: selectedAttachments,
        shipmentIds: shipmentIds,
      ),
    );
  }

  Widget _buildResendBanner() {
    final summary = resendSummary;
    if (summary == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isSkipped = summary.skipped;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSkipped ? Colors.orange.withValues(alpha: 0.12) : theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSkipped ? Colors.orange.withValues(alpha: 0.4) : theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary.typeLabel, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (isSkipped && summary.skippedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.skippedAt(formatDateTime(summary.skippedAt)), style: theme.textTheme.bodySmall),
            ),
          if (isSkipped && summary.skippedBy.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.skippedBy(summary.skippedBy), style: theme.textTheme.bodySmall),
            ),
          if (isSkipped && summary.skipRemark.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.reasonPrefix(summary.skipRemark),
                style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          if (!isSkipped && summary.sentAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.previouslySentAt(formatDateTime(summary.sentAt)), style: theme.textTheme.bodySmall),
            ),
          if (isSkipped)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.sendSkippedEmailNow,
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (!isSkipped && summary.attachmentTypeLabels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.attachmentsList(summary.attachmentTypeLabels.join(', ')),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (!isSkipped && summary.filenames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.filesList(summary.filenames.join(', ')),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isResend = resendSummary != null && !(resendSummary!.skipped);
    return AlertDialog(
      title: Text(_dialogTitle(l10n)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildResendBanner(),
              if (resendSummary == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _emailDescription(l10n),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              TextField(
                controller: _toController,
                decoration: InputDecoration(
                  labelText: l10n.toField,
                  hintText: l10n.emailRecipientsHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ccController,
                decoration: InputDecoration(
                  labelText: l10n.ccField,
                  hintText: l10n.none,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bccController,
                decoration: InputDecoration(
                  labelText: l10n.bccField,
                  hintText: l10n.none,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subjectController,
                decoration: InputDecoration(
                  labelText: l10n.subjectField,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  labelText: l10n.messageField,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                minLines: 6,
                maxLines: 10,
              ),
              const SizedBox(height: 12),
              Text(l10n.attachments, style: Theme.of(context).textTheme.titleSmall),
              if (emailType == WholesaleOrderEmailType.invoice)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    l10n.invoiceDeliveryDocsOptional,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ..._attachmentOptions.map((opt) {
                final required = isWholesaleOrderEmailAttachmentRequired(emailType, opt.key);
                final label = opt.hint != null ? '${opt.label} ${opt.hint}' : opt.label;
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _attachments[opt.key] ?? false,
                  onChanged: !opt.available || required
                      ? null
                      : (checked) => setState(() => _attachments[opt.key] = checked ?? false),
                  title: Text(
                    label,
                    style: opt.available
                        ? null
                        : TextStyle(
                            color: Theme.of(context).disabledColor,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: Theme.of(context).disabledColor,
                          ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.email_outlined, size: 18),
          label: Text(isResend ? l10n.resend : l10n.send),
        ),
      ],
    );
  }
}
