import 'package:flutter/material.dart';

import '../utils/formatters.dart';

String formatApiDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime? parseApiDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    return DateTime.parse(raw.substring(0, 10));
  } catch (_) {
    return null;
  }
}

class DatePickerFormField extends StatefulWidget {
  const DatePickerFormField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.labelText = 'Delivery date',
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;
  final String labelText;

  @override
  State<DatePickerFormField> createState() => _DatePickerFormFieldState();
}

class _DatePickerFormFieldState extends State<DatePickerFormField> {
  late final TextEditingController _display;

  @override
  void initState() {
    super.initState();
    _display = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(DatePickerFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _display.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _display.dispose();
    super.dispose();
  }

  String _format(DateTime? value) {
    if (value == null) return '';
    return formatDate(formatApiDate(value));
  }

  Future<void> _pickDate() async {
    if (!widget.enabled) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = widget.value ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 2),
    );
    if (picked == null) return;
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      enabled: widget.enabled,
      controller: _display,
      onTap: widget.enabled ? _pickDate : null,
      decoration: InputDecoration(
        labelText: widget.labelText,
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: widget.enabled ? _pickDate : null,
        ),
      ),
    );
  }
}
