import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../widgets/async_body.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  var _loading = false;
  var _error = '';
  final _start = TextEditingController(
    text: DateTime.now().subtract(const Duration(days: 7)).toIso8601String().substring(0, 10),
  );
  final _end = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
  double _posRevenue = 0;
  var _posOrderCount = 0;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final rows = await ApiService.instance.getDailyRevenueStats(
        startDate: _start.text.trim(),
        endDate: _end.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _posRevenue = rows.fold(0.0, (sum, row) => sum + row.revenue);
        _posOrderCount = rows.fold(0, (sum, row) => sum + row.orderCount);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.instance.errorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: _start, decoration: InputDecoration(labelText: l10n.startDate)),
        TextField(controller: _end, decoration: InputDecoration(labelText: l10n.endDate)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _load, child: Text(l10n.loadReport)),
        const SizedBox(height: 16),
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.posRevenue, style: Theme.of(context).textTheme.titleMedium),
              Text(formatMoney(_posRevenue)),
              const SizedBox(height: 8),
              Text(l10n.posOrdersCount(_posOrderCount)),
            ],
          ),
        ),
      ],
    );
  }
}
