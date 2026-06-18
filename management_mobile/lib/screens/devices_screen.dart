import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/admin.dart';
import '../models/store.dart';
import '../services/api_service.dart';
import '../widgets/async_body.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  var _loading = true;
  var _error = '';
  List<PosDevice> _devices = [];

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
      final devices = await ApiService.instance.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
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

  Future<void> _register() async {
    final code = TextEditingController();
    final name = TextEditingController();
    List<Store> stores = [];
    int? storeId;
    try {
      stores = await ApiService.instance.listStores();
      storeId = stores.isNotEmpty ? stores.first.id : null;
    } catch (_) {}
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l10n.registerDevice),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: code, decoration: InputDecoration(labelText: l10n.deviceCode)),
              TextField(controller: name, decoration: InputDecoration(labelText: l10n.deviceName)),
              DropdownButtonFormField<int>(
                value: storeId,
                decoration: InputDecoration(labelText: l10n.store),
                items: stores.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                onChanged: (v) => setLocal(() => storeId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.register)),
          ],
        ),
      ),
    );
    if (ok == true && code.text.trim().isNotEmpty && storeId != null) {
      try {
        await ApiService.instance.registerDevice(
          deviceCode: code.text.trim(),
          storeId: storeId!,
          deviceName: name.text.trim().isEmpty ? null : name.text.trim(),
        );
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.instance.errorMessage(e))),
          );
        }
      }
    }
    code.dispose();
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _register, child: const Icon(Icons.add)),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _devices.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final device = _devices[index];
              return Card(
                child: ListTile(
                  title: Text(device.deviceName ?? device.deviceCode),
                  subtitle: Text('${device.deviceCode} · ${device.store?.name ?? l10n.storeNumber(device.storeId)}'),
                  trailing: Chip(
                    label: Text(
                      device.isActive ? l10n.active : l10n.inactive,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
