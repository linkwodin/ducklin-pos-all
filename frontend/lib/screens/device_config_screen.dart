import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';

/// Admin-only screen to configure this device: copy device ID, add/update device to a store.
class DeviceConfigScreen extends StatefulWidget {
  const DeviceConfigScreen({super.key});

  @override
  State<DeviceConfigScreen> createState() => _DeviceConfigScreenState();
}

class _DeviceConfigScreenState extends State<DeviceConfigScreen> {
  List<Map<String, dynamic>> _stores = [];
  int? _selectedStoreId;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadStores();
    _loadCurrentStore();
  }

  Future<void> _loadStores() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.instance.getStores();
      final stores = list
          .map((e) => e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _stores = stores;
        if (_selectedStoreId == null && stores.isNotEmpty) {
          _selectedStoreId = stores.first['id'] as int?;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadCurrentStore() async {
    final info = await DatabaseService.instance.getDeviceInfo();
    final storeId = info?['store_id'];
    if (storeId != null && storeId is int) {
      setState(() => _selectedStoreId = storeId);
    }
  }

  Future<void> _copyDeviceId() async {
    final code = ApiService.instance.deviceCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.deviceIdCopied)),
    );
  }

  Future<void> _saveDeviceStore() async {
    final code = ApiService.instance.deviceCode;
    if (code == null || code.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device ID not available')),
      );
      return;
    }
    final storeId = _selectedStoreId;
    if (storeId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a store')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.instance.configureDevice(code, storeId);
      await DatabaseService.instance.saveDeviceInfo(code, storeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.deviceConfiguredSuccessfully)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isManagement = authProvider.currentUser?['role'] == 'management';

    if (!isManagement) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.configureDevice)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              l10n.onlyManagementCanConfigure,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
          ),
        ),
      );
    }

    final deviceCode = ApiService.instance.deviceCode ?? '—';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.configureDevice)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Device ID + Copy
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.deviceId,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              deviceCode,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: deviceCode == '—' ? null : _copyDeviceId,
                            icon: const Icon(Icons.copy, size: 20),
                            label: Text(l10n.copyDeviceId),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Add device to store
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.addDeviceToStore,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      if (_loading)
                        const Center(child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(),
                        ))
                      else if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red[700], fontSize: 14),
                          ),
                        )
                      else ...[
                        DropdownButtonFormField<int>(
                          value: _selectedStoreId,
                          decoration: InputDecoration(
                            labelText: l10n.selectStore,
                            border: const OutlineInputBorder(),
                          ),
                          items: _stores
                              .map((s) {
                                final id = s['id'];
                                final name = s['name'] ?? 'Store $id';
                                return DropdownMenuItem<int>(
                                  value: id is int ? id : (id as num).toInt(),
                                  child: Text(name.toString()),
                                );
                              })
                              .toList(),
                          onChanged: (v) => setState(() => _selectedStoreId = v),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ? null : _saveDeviceStore,
                            child: _saving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(l10n.saveDeviceStore),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
