import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_labels.dart';
import '../models/admin.dart';
import '../models/wholesale_order.dart';
import '../utils/wholesale_order_workflow.dart';

class WholesaleOrderStepperCard extends StatelessWidget {
  const WholesaleOrderStepperCard({
    super.key,
    required this.order,
    required this.auditLogs,
  });

  final WholesaleOrder order;
  final List<AuditLogEntry> auditLogs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = buildWholesaleWorkflowContext(order, auditLogs);
    final steps = computeWholesaleOrderProcessSteps(order, ctx);
    final current = currentWholesaleProcessStepKey(steps);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: steps.map((step) {
            final isCurrent = step.key == current;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                step.done ? Icons.check_circle : (isCurrent ? Icons.radio_button_checked : Icons.radio_button_off),
                color: step.done
                    ? Colors.green
                    : (isCurrent ? Theme.of(context).colorScheme.primary : Colors.grey),
                size: 20,
              ),
              title: Text(
                l10n.wholesaleProcessStepLabel(step.key),
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
