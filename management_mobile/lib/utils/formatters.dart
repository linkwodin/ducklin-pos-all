import 'package:intl/intl.dart';

import 'status_chip_style.dart';

final _gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');
final _date = DateFormat('dd MMM yyyy');
final _dateTime = DateFormat('dd MMM yyyy HH:mm');

String formatMoney(num? value) => _gbp.format(value ?? 0);

String formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    return _date.format(DateTime.parse(iso));
  } catch (_) {
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }
}

String formatDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    return _dateTime.format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}

String shipmentStatusLabel(String status) {
  switch (status) {
    case 'assigned':
      return 'Assigned';
    case 'packing':
      return 'Packing';
    case 'packed':
      return 'Packed';
    case 'shipped':
      return 'Shipped';
    case 'completed':
      return 'Completed';
    default:
      return status.replaceAll('_', ' ');
  }
}

StatusChipColor shipmentStatusChipColor(String status) {
  switch (status) {
    case 'completed':
      return StatusChipColor.success;
    case 'shipped':
      return StatusChipColor.warning;
    case 'packed':
      return StatusChipColor.info;
    default:
      return StatusChipColor.defaultColor;
  }
}
