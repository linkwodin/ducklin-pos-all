import 'package:flutter/material.dart';

enum StatusChipColor {
  success,
  warning,
  primary,
  error,
  defaultColor,
  secondary,
  info,
}

class StatusChipStyle {
  const StatusChipStyle({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

StatusChipStyle resolveStatusChipStyle(BuildContext context, StatusChipColor color) {
  final scheme = Theme.of(context).colorScheme;
  return switch (color) {
    StatusChipColor.success => StatusChipStyle(
        background: const Color(0xFFE8F5E9),
        foreground: const Color(0xFF2E7D32),
      ),
    StatusChipColor.error => StatusChipStyle(
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      ),
    StatusChipColor.primary => StatusChipStyle(
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      ),
    StatusChipColor.warning => StatusChipStyle(
        background: const Color(0xFFFFF3E0),
        foreground: const Color(0xFFE65100),
      ),
    StatusChipColor.info => StatusChipStyle(
        background: const Color(0xFFE3F2FD),
        foreground: const Color(0xFF1565C0),
      ),
    StatusChipColor.secondary => StatusChipStyle(
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
      ),
    StatusChipColor.defaultColor => StatusChipStyle(
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      ),
  };
}
