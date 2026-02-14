import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';

class ReportScreen extends StatefulWidget {
  /// When the user taps the "pending completion" count, call this to go to order search with pending filter.
  final VoidCallback? onTapPendingOrders;

  const ReportScreen({super.key, this.onTapPendingOrders});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  bool _loading = true;
  String? _error;
  bool _isLocalData = false;
  int _offlineOrdersCount = 0; // unsynced orders included in report
  int _pendingCompletionCount = 0; // orders with status pending
  double _todayRevenue = 0;
  int _todayOrderCount = 0;
  List<Map<String, dynamic>> _todayProductSales = [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
      _isLocalData = false;
    });

    final deviceInfo = await DatabaseService.instance.getDeviceInfo();
    final storeId = deviceInfo?['store_id'] as int?;

    try {
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final revenueList = await ApiService.instance.getDailyRevenueStats(
        startDate: today,
        endDate: today,
        storeId: storeId,
      );

      final productSalesList = await ApiService.instance.getDailyProductSalesStats(
        startDate: today,
        endDate: today,
        storeId: storeId,
      );

      double totalRevenue = 0;
      int orderCount = 0;
      for (final e in revenueList) {
        if (e is Map<String, dynamic>) {
          totalRevenue += (e['revenue'] as num?)?.toDouble() ?? 0;
          orderCount += (e['order_count'] as int?) ?? 0;
        }
      }

      final productSalesMap = <int, Map<String, dynamic>>{}; // product_id -> { name, name_chinese, quantity, revenue }
      for (final e in productSalesList) {
        if (e is Map<String, dynamic> && e['date'] == today) {
          final pid = e['product_id'] as int?;
          if (pid == null) continue;
          final qty = (e['quantity'] as num?)?.toDouble() ?? 0;
          final rev = (e['revenue'] as num?)?.toDouble() ?? 0;
          if (productSalesMap.containsKey(pid)) {
            productSalesMap[pid]!['quantity'] = (productSalesMap[pid]!['quantity'] as num) + qty;
            productSalesMap[pid]!['revenue'] = (productSalesMap[pid]!['revenue'] as num) + rev;
          } else {
            productSalesMap[pid] = {
              'product_name': e['product_name'] ?? '',
              'product_name_chinese': e['product_name_chinese'],
              'quantity': qty,
              'revenue': rev,
            };
          }
        }
      }

      // Merge in today's offline (unsynced) orders so report includes them
      int offlineCount = 0;
      try {
        final localRev = await DatabaseService.instance.getTodayRevenueFromLocal(storeId, onlyUnsynced: true);
        final localSales = await DatabaseService.instance.getTodayProductSalesFromLocal(storeId, onlyUnsynced: true);
        offlineCount = (localRev['order_count'] as int?) ?? 0;
        if (offlineCount > 0) {
          totalRevenue += (localRev['revenue'] as num?)?.toDouble() ?? 0;
          orderCount += offlineCount;
          for (final item in localSales) {
            final pid = item['product_id'] as int?;
            if (pid == null) continue;
            final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
            final rev = (item['revenue'] as num?)?.toDouble() ?? 0;
            if (productSalesMap.containsKey(pid)) {
              productSalesMap[pid]!['quantity'] = (productSalesMap[pid]!['quantity'] as num) + qty;
              productSalesMap[pid]!['revenue'] = (productSalesMap[pid]!['revenue'] as num) + rev;
            } else {
              productSalesMap[pid] = {
                'product_name': item['product_name'] ?? '',
                'product_name_chinese': item['product_name_chinese'],
                'quantity': qty,
                'revenue': rev,
              };
            }
          }
        }
      } catch (_) {}

      final productSales = productSalesMap.values.toList();

      final pendingCount = await DatabaseService.instance.getOrdersCountByStatus('pending');

      if (mounted) {
        setState(() {
          _todayRevenue = totalRevenue;
          _todayOrderCount = orderCount;
          _todayProductSales = productSales;
          _offlineOrdersCount = offlineCount;
          _pendingCompletionCount = pendingCount;
          _loading = false;
          _isLocalData = false;
        });
      }
    } catch (e) {
      // Connection lost: use local data
      try {
        final revenueMap = await DatabaseService.instance.getTodayRevenueFromLocal(storeId);
        final productSales = await DatabaseService.instance.getTodayProductSalesFromLocal(storeId);
        final pendingCount = await DatabaseService.instance.getOrdersCountByStatus('pending');
        if (mounted) {
          setState(() {
            _todayRevenue = (revenueMap['revenue'] as num?)?.toDouble() ?? 0.0;
            _todayOrderCount = (revenueMap['order_count'] as int?) ?? 0;
            _todayProductSales = productSales;
            _pendingCompletionCount = pendingCount;
            _loading = false;
            _error = null;
            _isLocalData = true;
          });
        }
      } catch (localErr) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _loading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageProvider = Provider.of<LanguageProvider>(context);
    final useChinese = languageProvider.locale.languageCode.startsWith('zh');

    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.reportLoading, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                l10n.reportError,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadReport,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReport,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.reportToday,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (_isLocalData) ...[
              const SizedBox(height: 12),
              Material(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off, size: 20, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Showing local data (offline)',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.reportTotalSales,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.grey[700],
                              ),
                        ),
                        Text(
                          '${l10n.reportTodayCommission}: £${(_todayRevenue * 0.02).toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '£${_todayRevenue.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    if (_todayOrderCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '$_todayOrderCount orders'
                              + (_offlineOrdersCount > 0 ? ' (${_offlineOrdersCount} offline)' : ''),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Pending completion count – tappable to go to order search with filter
            Card(
              child: InkWell(
                onTap: _pendingCompletionCount > 0 && widget.onTapPendingOrders != null
                    ? widget.onTapPendingOrders
                    : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.pending_actions,
                        size: 28,
                        color: _pendingCompletionCount > 0 ? Colors.orange : Colors.grey,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Orders pending completion',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.grey[700],
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_pendingCompletionCount',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: _pendingCompletionCount > 0 ? Colors.orange : Colors.grey,
                                  ),
                            ),
                            if (_pendingCompletionCount > 0 && widget.onTapPendingOrders != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Tap to view in order search',
                                  style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_pendingCompletionCount > 0 && widget.onTapPendingOrders != null)
                        const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.reportSoldProducts,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            if (_todayProductSales.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      l10n.reportNoSalesToday,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ),
              )
            else
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _todayProductSales.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _todayProductSales[index];
                    final name = useChinese &&
                            (item['product_name_chinese'] ?? '').toString().isNotEmpty
                        ? (item['product_name_chinese'] ?? '')
                        : (item['product_name'] ?? '');
                    final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
                    final rev = (item['revenue'] as num?)?.toDouble() ?? 0;
                    return ListTile(
                      title: Text(name.toString()),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            qty.toStringAsFixed(qty == qty.round() ? 0 : 1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 72,
                            child: Text(
                              '£${rev.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (_todayProductSales.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${l10n.reportQuantity} / ${l10n.reportRevenue}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
