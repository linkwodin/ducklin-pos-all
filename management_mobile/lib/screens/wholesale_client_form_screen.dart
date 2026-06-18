import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/sector.dart';
import '../models/wholesale_client.dart';
import '../services/api_service.dart';

class WholesaleClientFormScreen extends StatefulWidget {
  const WholesaleClientFormScreen({super.key, this.clientId});

  final int? clientId;

  @override
  State<WholesaleClientFormScreen> createState() => _WholesaleClientFormScreenState();
}

class _WholesaleClientFormScreenState extends State<WholesaleClientFormScreen> {
  var _loading = true;
  var _saving = false;
  WholesaleClient? _client;
  List<Sector> _sectors = [];
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _terms = TextEditingController();
  int? _sectorId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _email.dispose();
    _phone.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sectors = await ApiService.instance.listSectors();
      WholesaleClient? client;
      if (widget.clientId != null) {
        client = await ApiService.instance.getWholesaleClient(widget.clientId!);
        _name.text = client.name;
        _contact.text = client.contactName ?? '';
        _email.text = client.email ?? '';
        _phone.text = client.phone ?? '';
        _terms.text = client.terms ?? '';
        _sectorId = client.sectorId;
      }
      if (!mounted) return;
      setState(() {
        _sectors = sectors;
        _client = client;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final body = {
        'name': _name.text.trim(),
        'contact_name': _contact.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'terms': _terms.text.trim(),
        if (_sectorId != null) 'sector_id': _sectorId,
      };
      if (widget.clientId == null) {
        await ApiService.instance.createWholesaleClient(body);
      } else {
        await ApiService.instance.updateWholesaleClient(widget.clientId!, body);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.clientId == null ? l10n.newClient : l10n.editClient)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.clientId == null ? l10n.newClient : l10n.editClient)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: InputDecoration(labelText: l10n.name)),
          TextField(controller: _contact, decoration: InputDecoration(labelText: l10n.contact)),
          TextField(controller: _email, decoration: InputDecoration(labelText: l10n.email)),
          TextField(controller: _phone, decoration: InputDecoration(labelText: l10n.phone)),
          TextField(controller: _terms, decoration: InputDecoration(labelText: l10n.paymentTerms)),
          DropdownButtonFormField<int?>(
            value: _sectorId,
            decoration: InputDecoration(labelText: l10n.sector),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.none)),
              ..._sectors.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
            ],
            onChanged: (v) => setState(() => _sectorId = v),
          ),
          if (_client != null && _client!.stores.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(l10n.deliveryLocations, style: Theme.of(context).textTheme.titleMedium),
            ..._client!.stores.map((s) => ListTile(title: Text(s.name), subtitle: Text(s.summary()))),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
