import 'package:flutter/material.dart';

class WizardStepHeader extends StatelessWidget {
  const WizardStepHeader({
    super.key,
    required this.currentStep,
    required this.labels,
  });

  final int currentStep;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 16),
                color: i <= currentStep
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
              ),
            ),
          _WizardStepDot(
            index: i + 1,
            label: labels[i],
            active: i == currentStep,
            completed: i < currentStep,
          ),
        ],
      ],
    );
  }
}

class _WizardStepDot extends StatelessWidget {
  const _WizardStepDot({
    required this.index,
    required this.label,
    required this.active,
    required this.completed,
  });

  final int index;
  final String label;
  final bool active;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final circleColor = active || completed ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final textColor = active || completed ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: circleColor,
          child: completed && !active
              ? Icon(Icons.check, size: 18, color: colorScheme.onPrimary)
              : Text('$index', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
