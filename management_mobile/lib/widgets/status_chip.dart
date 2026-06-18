import 'package:flutter/material.dart';

export '../utils/status_chip_style.dart';
import '../utils/status_chip_style.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.visualDensity = VisualDensity.compact,
  });

  final String label;
  final StatusChipColor color;
  final VisualDensity visualDensity;

  @override
  Widget build(BuildContext context) {
    final style = resolveStatusChipStyle(context, color);
    return Chip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: style.foreground,
        ),
      ),
      backgroundColor: style.background,
      side: BorderSide(color: style.foreground.withValues(alpha: 0.28)),
      visualDensity: visualDensity,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
