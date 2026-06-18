import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/admin.dart';
import '../services/api_service.dart';
import '../widgets/async_body.dart';

class WholesaleAuditLogScreen extends StatefulWidget {
  const WholesaleAuditLogScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<WholesaleAuditLogScreen> createState() => _WholesaleAuditLogScreenState();
}

class _WholesaleAuditLogScreenState extends State<WholesaleAuditLogScreen> {
  var _loading = true;
  var _error = '';
  List<AuditLogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final logs = await ApiService.instance.getWholesaleAuditLogs(widget.orderId);
      if (!mounted) return;
      setState(() {
        _logs = logs;
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
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.auditLog)),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _logs.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final log = _logs[index];
            return ListTile(
              title: Text(log.action),
              subtitle: Text('${log.createdAt ?? ''}\n${log.changes ?? ''}'),
              isThreeLine: true,
            );
          },
        ),
      ),
    );
  }
}
