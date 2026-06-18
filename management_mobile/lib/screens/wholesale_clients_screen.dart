import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/wholesale_client.dart';
import '../services/api_service.dart';
import '../widgets/async_body.dart';
import 'wholesale_client_form_screen.dart';

class WholesaleClientsScreen extends StatefulWidget {
  const WholesaleClientsScreen({super.key, this.onCreate});

  final VoidCallback? onCreate;

  @override
  State<WholesaleClientsScreen> createState() => _WholesaleClientsScreenState();
}

class _WholesaleClientsScreenState extends State<WholesaleClientsScreen> {
  var _loading = true;
  var _error = '';
  List<WholesaleClient> _clients = [];

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
      final clients = await ApiService.instance.listWholesaleClients();
      if (!mounted) return;
      setState(() {
        _clients = clients;
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
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: widget.onCreate ??
            () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WholesaleClientFormScreen()),
              );
              _load();
            },
        child: const Icon(Icons.add),
      ),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _clients.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final client = _clients[index];
              return Card(
                child: ListTile(
                  title: Text(client.name),
                  subtitle: Text('${client.email ?? '—'} · ${l10n.locationsCount(client.stores.length)}'),
                  trailing: Chip(
                    label: Text(client.isActive ? l10n.active : l10n.inactive, style: const TextStyle(fontSize: 11)),
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => WholesaleClientFormScreen(clientId: client.id)),
                    );
                    _load();
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
