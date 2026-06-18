import 'package:flutter/material.dart';

class DetailInfoTable extends StatelessWidget {
  const DetailInfoTable({super.key, required this.rows});

  final List<DetailInfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(96),
            1: FlexColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows.map((row) {
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 10),
                  child: Text(row.label, style: labelStyle),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: row.value,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class DetailInfoRow {
  const DetailInfoRow(this.label, this.value);

  final String label;
  final Widget value;
}
