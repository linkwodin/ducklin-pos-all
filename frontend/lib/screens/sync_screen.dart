import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/sync_status_provider.dart';
import '../providers/stocktake_status_provider.dart';
import '../providers/product_provider.dart';
import '../services/offline_sync_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool _isSyncing = false;
  String? _message; // success or error
  bool _success = false;

  Future<void> _runSync() async {
    if (_isSyncing) return;
    final l10n = AppLocalizations.of(context)!;
    final syncStatus = Provider.of<SyncStatusProvider>(context, listen: false);
    final productProvider = Provider.of<ProductProvider>(context, listen: false);

    setState(() {
      _isSyncing = true;
      _message = null;
    });

    try {
      final success = await productProvider.syncProducts();
      await OfflineSyncService.runSyncNow();
      if (mounted) await syncStatus.refreshPendingCount();
      if (mounted) await Provider.of<StocktakeStatusProvider>(context, listen: false).refreshFromServer();
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _success = success;
          _message = success ? l10n.dataSyncedSuccessfully : l10n.syncFailed('Failed to sync products');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _success = false;
          _message = l10n.syncFailed(e.toString());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.syncScreenTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Consumer<SyncStatusProvider>(
                builder: (context, syncStatus, _) {
                  final orders = syncStatus.pendingOrdersCount;
                  final stocktakes = syncStatus.pendingStocktakesCount;
                  final events = syncStatus.pendingUserActivityEventsCount;
                  final total = orders + stocktakes + events;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (total == 0)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green[700], size: 40),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    l10n.syncNoPendingItems,
                                    style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: orders > 0 ? Colors.orange.shade100 : Colors.grey.shade200,
                              child: Text(
                                '$orders',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: orders > 0 ? Colors.orange.shade800 : Colors.grey,
                                ),
                              ),
                            ),
                            title: Text(l10n.syncPendingOrders),
                            subtitle: Text(orders > 0 ? 'Will be uploaded when you sync' : 'None'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: stocktakes > 0 ? Colors.orange.shade100 : Colors.grey.shade200,
                              child: Text(
                                '$stocktakes',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: stocktakes > 0 ? Colors.orange.shade800 : Colors.grey,
                                ),
                              ),
                            ),
                            title: Text(l10n.syncPendingStocktakes),
                            subtitle: Text(stocktakes > 0 ? 'Will be uploaded when you sync' : 'None'),
                          ),
                        ),
                        if (events > 0) ...[
                          const SizedBox(height: 12),
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange.shade100,
                                child: Text(
                                  '$events',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                              title: const Text('User activity events'),
                              subtitle: const Text('Login/logout and stocktake events will be uploaded when you sync'),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSyncing ? null : _runSync,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_isSyncing ? l10n.syncing : l10n.sync),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Material(
                  color: _success ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          _success ? Icons.check_circle : Icons.error,
                          color: _success ? Colors.green.shade700 : Colors.red.shade700,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _success ? Colors.green.shade900 : Colors.red.shade900,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
