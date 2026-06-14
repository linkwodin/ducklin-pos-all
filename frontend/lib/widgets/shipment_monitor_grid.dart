import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../utils/shipment_monitor_lines.dart';
import '../utils/shipment_order_time.dart';
import '../utils/shipment_status.dart';
import '../utils/wholesale_order_assignment.dart';
import '../widgets/cached_product_image.dart';

class ShipmentMonitorGrid extends StatelessWidget {
  const ShipmentMonitorGrid({
    super.key,
    required this.shipments,
    required this.completedDaysLabel,
    required this.onOpenShipment,
    required this.onStartPackingQueue,
    required this.onStartCourierPickup,
  });

  final List<Map<String, dynamic>> shipments;
  final int completedDaysLabel;
  final void Function(Map<String, dynamic> shipment) onOpenShipment;
  final void Function(List<Map<String, dynamic>> queue) onStartPackingQueue;
  final void Function(List<Map<String, dynamic>> queue) onStartCourierPickup;

  static const _completedMaxRows = 12;

  static const _columns = [
    (
      id: 'packing',
      title: 'To pack',
      hint: 'Scan items and confirm boxes',
      statuses: ['assigned', 'packing'],
      color: Colors.orange,
      bg: Color(0xFFFFF8E1),
    ),
    (
      id: 'packed',
      title: 'Packed',
      hint: 'Ready for courier pickup',
      statuses: ['packed'],
      color: Colors.blue,
      bg: Color(0xFFE3F2FD),
    ),
    (
      id: 'shipped',
      title: 'Shipped',
      hint: 'Awaiting delivery proof',
      statuses: ['shipped'],
      color: Colors.green,
      bg: Color(0xFFE8F5E9),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context).locale.languageCode;
    final sorted = [...shipments]..sort(sortShipmentsByOrderTimeDesc);
    final activeByColumn = <String, List<Map<String, dynamic>>>{};
    for (final col in _columns) {
      activeByColumn[col.id] = [];
    }
    final completed = <Map<String, dynamic>>[];
    for (final s in sorted) {
      if (s['status'] == 'completed') {
        completed.add(s);
        continue;
      }
      for (final col in _columns) {
        if (col.statuses.contains(s['status'])) {
          activeByColumn[col.id]!.add(s);
          break;
        }
      }
    }
    for (final col in _columns) {
      activeByColumn[col.id]!.sort(sortShipmentsByOrderTimeDesc);
    }
    completed.sort(sortShipmentsByOrderTimeDesc);
    final completedRows = completed.take(_completedMaxRows).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _columns.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _MonitorColumn(
                    title: _columns[i].title,
                    hint: _columns[i].hint,
                    color: _columns[i].color,
                    bg: _columns[i].bg,
                    shipments: activeByColumn[_columns[i].id] ?? [],
                    lang: lang,
                    onOpenShipment: onOpenShipment,
                    onStartQueue: _columns[i].id == 'packing'
                        ? () => onStartPackingQueue(activeByColumn[_columns[i].id] ?? [])
                        : _columns[i].id == 'packed'
                            ? () => onStartCourierPickup(activeByColumn[_columns[i].id] ?? [])
                            : null,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: 1,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(width: 4, height: 24, color: Colors.grey),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Completed shipment', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                              'Recently completed deliveries',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Chip(label: Text('${completedRows.length}')),
                      Text(
                        'Last $completedDaysLabel days',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: completedRows.isEmpty
                      ? const Center(
                          child: Text('No completed shipments', style: TextStyle(color: Colors.grey)),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: completedRows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final s = completedRows[index];
                            return InkWell(
                              onTap: () => onOpenShipment(s),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: _CompactTicket(shipment: s, lang: lang),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Updated ${TimeOfDay.now().format(context)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

class _MonitorColumn extends StatelessWidget {
  const _MonitorColumn({
    required this.title,
    required this.hint,
    required this.color,
    required this.bg,
    required this.shipments,
    required this.lang,
    required this.onOpenShipment,
    this.onStartQueue,
  });

  final String title;
  final String hint;
  final Color color;
  final Color bg;
  final List<Map<String, dynamic>> shipments;
  final String lang;
  final void Function(Map<String, dynamic> shipment) onOpenShipment;
  final VoidCallback? onStartQueue;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: bg,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(width: 4, height: 24, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(hint, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                if (onStartQueue != null)
                  IconButton(
                    icon: const Icon(Icons.play_circle),
                    color: color,
                    onPressed: shipments.isEmpty ? null : onStartQueue,
                    tooltip: 'Start queue',
                  ),
                Chip(label: Text('${shipments.length}'), backgroundColor: Colors.white),
              ],
            ),
          ),
          Expanded(
            child: shipments.isEmpty
                ? const Center(child: Text('Empty', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: shipments.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ShipmentTicket(
                          shipment: shipments[index],
                          lang: lang,
                          accent: color,
                          onOpen: () => onOpenShipment(shipments[index]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ShipmentTicket extends StatelessWidget {
  const _ShipmentTicket({
    required this.shipment,
    required this.lang,
    required this.accent,
    required this.onOpen,
  });

  final Map<String, dynamic> shipment;
  final String lang;
  final Color accent;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final order = shipment['wholesale_order'] as Map<String, dynamic>?;
    final orderNumber = order?['order_number']?.toString() ?? '#${shipment['wholesale_order_id']}';
    final orderRef = order?['ref_no']?.toString().trim();
    final poNumber = order?['po_number']?.toString().trim();
    final clientName = order?['wholesale_client']?['name']?.toString().trim();
    final orderDate = formatShipmentOrderDate(shipment);
    final needsPacking = shipmentNeedsPacking(shipment['status']?.toString() ?? '');
    final lines = monitorLinesForShipment(shipment, lang, (id) => 'Item #$id');
    final summary = shipmentAssignedSummary(shipment);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: accent, width: 4)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(orderNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (orderRef != null && orderRef.isNotEmpty)
                          Text('Ref: $orderRef', style: const TextStyle(color: Colors.grey)),
                        if ((poNumber != null && poNumber.isNotEmpty) || (clientName != null && clientName.isNotEmpty))
                          Text(
                            [if (poNumber != null && poNumber.isNotEmpty) 'PO $poNumber', clientName]
                                .whereType<String>()
                                .join(' · '),
                            style: const TextStyle(color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  if (orderDate != null) Chip(label: Text(orderDate), visualDensity: VisualDensity.compact),
                ],
              ),
              const SizedBox(height: 8),
              if (lines.isNotEmpty)
                ...lines.take(5).map((line) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: line.imageUrl != null && line.imageUrl!.isNotEmpty
                              ? CachedProductImage(imageUrl: line.imageUrl!, width: 32, height: 32, fit: BoxFit.cover)
                              : Container(color: Colors.grey[300]),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            line.boxes != null
                                ? '${line.name} · ${formatQtyLabel(line.qty)} (${formatQtyLabel(line.boxes!)} boxes)'
                                : '${line.name} · ${formatQtyLabel(line.qty)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                })
              else if (summary.productCount > 0)
                Text('${summary.productCount} items · ${formatQtyLabel(summary.totalQty)} qty')
              else
                const Text('No items', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: needsPacking ? Colors.orange : null,
                ),
                child: Text(needsPacking ? 'Process' : 'View'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactTicket extends StatelessWidget {
  const _CompactTicket({required this.shipment, required this.lang});

  final Map<String, dynamic> shipment;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final order = shipment['wholesale_order'] as Map<String, dynamic>?;
    final orderNumber = order?['order_number']?.toString() ?? '#${shipment['wholesale_order_id']}';
    final clientName = order?['wholesale_client']?['name']?.toString().trim() ?? '—';
    final lines = monitorLinesForShipment(shipment, lang, (id) => 'Item #$id');
    final orderDate = formatShipmentOrderDate(shipment) ?? '—';
    return Row(
      children: [
        Expanded(flex: 2, child: Text(orderNumber, style: const TextStyle(fontWeight: FontWeight.bold))),
        Expanded(flex: 3, child: Text(clientName, overflow: TextOverflow.ellipsis)),
        Text('${lines.length} items'),
        const SizedBox(width: 8),
        Text(orderDate, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const Icon(Icons.chevron_right),
      ],
    );
  }
}
