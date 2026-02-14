import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/order_provider.dart';
import '../providers/notification_bar_provider.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import 'order_details_screen.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => OrderHistoryScreenState();
}

class OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  bool _isLoading = true;
  String? _statusFilter; // null = all
  DateTime? _dateFrom;
  DateTime? _dateTo;
  /// Which quick range the user chose ('today' | 'week' | 'month'), so the correct chip stays selected even when range is one day (e.g. Monday = this week).
  String? _selectedQuickRange;
  static const List<String> _statusOptions = ['pending', 'paid', 'completed', 'picked_up', 'cancelled'];

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _searchController.addListener(_searchOrders);
  }

  // Method to refresh orders (can be called externally)
  void refreshOrders() {
    _loadOrders();
  }

  /// Apply a status filter (e.g. 'pending'). Call from report "pending" tap to show only those orders.
  void applyStatusFilter(String? status) {
    setState(() {
      _statusFilter = status;
    });
    _applyFilters();
  }

  void _applyFilters() {
    var list = _orders;
    if (_statusFilter != null && _statusFilter!.isNotEmpty) {
      list = list.where((o) => (o['status'] ?? '').toString().toLowerCase() == _statusFilter!.toLowerCase()).toList();
    }
    if (_dateFrom != null || _dateTo != null) {
      final fromMs = _dateFrom != null ? DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day).millisecondsSinceEpoch : 0;
      final toEndMs = _dateTo != null ? DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day).add(const Duration(days: 1)).millisecondsSinceEpoch : 0x7FFFFFFFFFFFFFFF;
      list = list.where((o) {
        final created = o['created_at'];
        if (created == null) return false;
        final ms = created is int ? created : (created is String ? int.tryParse(created) : null);
        if (ms == null) return false;
        if (_dateFrom != null && ms < fromMs) return false;
        if (_dateTo != null && ms >= toEndMs) return false;
        return true;
      }).toList();
    }
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      final queryLower = query.toLowerCase();
      list = list.where((order) {
        final orderNumber = (order['order_number'] ?? '').toString().toLowerCase();
        final total = (order['total_amount'] ?? 0).toString().toLowerCase();
        final createdAt = (order['created_at'] ?? '').toString().toLowerCase();
        return orderNumber.contains(queryLower) ||
            total.contains(queryLower) ||
            createdAt.contains(queryLower);
      }).toList();
    }
    if (mounted) {
      setState(() {
        _filteredOrders = list;
      });
    }
  }

  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedQuickRange = null;
        _dateFrom = picked;
        if (_dateTo != null && _dateTo!.isBefore(picked)) _dateTo = picked;
      });
      _applyFilters();
    }
  }

  Future<void> _pickDateTo() async {
    final initial = _dateTo ?? _dateFrom ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _dateFrom ?? DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedQuickRange = null;
        _dateTo = picked;
        if (_dateFrom != null && _dateFrom!.isAfter(picked)) _dateFrom = picked;
      });
      _applyFilters();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedQuickRange = null;
      _dateFrom = null;
      _dateTo = null;
    });
    _applyFilters();
  }

  bool _isQuickRangeSelected(String range) {
    return _selectedQuickRange == range;
  }

  void _setQuickDateRange(String range) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedQuickRange = range;
      switch (range) {
        case 'today':
          _dateFrom = today;
          _dateTo = today;
          break;
        case 'week':
          _dateFrom = today.subtract(const Duration(days: 6));
          _dateTo = today;
          break;
        case 'month':
          _dateFrom = DateTime(now.year, now.month, 1);
          _dateTo = today;
          break;
        default:
          _selectedQuickRange = null;
          _dateFrom = null;
          _dateTo = null;
      }
    });
    _applyFilters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load all orders from local database
      final db = await DatabaseService.instance.database;
      final allOrders = await db.query(
        'orders',
        orderBy: 'created_at DESC',
        limit: 100,
      );

      setState(() {
        _orders = allOrders;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showNotification('Error loading orders: $e', isError: true);
      }
    }
  }

  void _searchOrders() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _applyFilters();
      return;
    }

    final queryLower = query.toLowerCase();
    final localMatches = _orders.where((order) {
      if (_statusFilter != null && (order['status'] ?? '').toString().toLowerCase() != _statusFilter!.toLowerCase()) {
        return false;
      }
      final orderNumber = (order['order_number'] ?? '').toString().toLowerCase();
      final total = (order['total_amount'] ?? 0).toString().toLowerCase();
      final createdAt = (order['created_at'] ?? '').toString().toLowerCase();
      return orderNumber.contains(queryLower) ||
          total.contains(queryLower) ||
          createdAt.contains(queryLower);
    }).toList();

    // If no local matches and query looks like an order number, try backend
    if (localMatches.isEmpty && query.toUpperCase().startsWith('ORD-')) {
      try {
        final orderData = await ApiService.instance.getOrder(query);
        if (orderData != null) {
          // Save to local database
          try {
            final db = await DatabaseService.instance.database;
            final createdAt = orderData['created_at'] != null
                ? DateTime.parse(orderData['created_at']).millisecondsSinceEpoch
                : DateTime.now().millisecondsSinceEpoch;
            final pickedUpAt = orderData['picked_up_at'] != null
                ? DateTime.parse(orderData['picked_up_at']).millisecondsSinceEpoch
                : null;

            await db.insert(
              'orders',
              {
                'order_number': orderData['order_number'],
                'store_id': orderData['store_id'] ?? 1,
                'user_id': orderData['user_id'] ?? 0,
                'sector_id': orderData['sector_id'],
                'subtotal': orderData['subtotal'] ?? 0.0,
                'discount_amount': orderData['discount_amount'] ?? 0.0,
                'total_amount': orderData['total_amount'] ?? 0.0,
                'status': orderData['status'] ?? 'pending',
                'qr_code_data': orderData['qr_code_data'],
                'created_at': createdAt,
                'picked_up_at': pickedUpAt,
                'synced': 1,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (e) {
            debugPrint('Error saving order to local database: $e');
          }

          // Convert to local format and add to results
          final localOrder = {
            'order_number': orderData['order_number'],
            'store_id': orderData['store_id'],
            'user_id': orderData['user_id'],
            'sector_id': orderData['sector_id'],
            'subtotal': orderData['subtotal'],
            'discount_amount': orderData['discount_amount'],
            'total_amount': orderData['total_amount'],
            'status': orderData['status'],
            'created_at': orderData['created_at'] != null
                ? DateTime.parse(orderData['created_at']).millisecondsSinceEpoch
                : null,
            'picked_up_at': orderData['picked_up_at'] != null
                ? DateTime.parse(orderData['picked_up_at']).millisecondsSinceEpoch
                : null,
          };

          setState(() {
            if (!_orders.any((o) => o['order_number'] == localOrder['order_number'])) {
              _orders.insert(0, localOrder);
            }
          });
          _applyFilters();
          return;
        }
      } catch (e) {
        debugPrint('Error fetching order from backend: $e');
      }
    }

    _applyFilters();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'paid':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'picked_up':
        return Colors.purple;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.searchOrder),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
            tooltip: l10n.refresh ?? 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: l10n.searchByOrderTotalDate,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
              ),
              onSubmitted: (_) => _searchOrders(),
            ),
          ),
          // Filters: status + date range
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filters', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Status:', style: TextStyle(fontSize: 14, color: Colors.grey[700])),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: _statusFilter,
                          hint: const Text('All'),
                          isDense: true,
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('All')),
                            ..._statusOptions.map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s.toUpperCase()),
                                )),
                          ],
                          onChanged: (v) {
                            setState(() => _statusFilter = v);
                            _applyFilters();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Date:', style: TextStyle(fontSize: 14, color: Colors.grey[700])),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                icon: const Icon(Icons.calendar_today, size: 18),
                                label: Text(_dateFrom != null ? '${_dateFrom!.year}-${_dateFrom!.month.toString().padLeft(2, '0')}-${_dateFrom!.day.toString().padLeft(2, '0')}' : 'From'),
                                onPressed: _pickDateFrom,
                              ),
                              const Text('–'),
                              TextButton.icon(
                                icon: const Icon(Icons.calendar_today, size: 18),
                                label: Text(_dateTo != null ? '${_dateTo!.year}-${_dateTo!.month.toString().padLeft(2, '0')}-${_dateTo!.day.toString().padLeft(2, '0')}' : 'To'),
                                onPressed: _pickDateTo,
                              ),
                              if (_dateFrom != null || _dateTo != null)
                                TextButton(
                                  onPressed: _clearDateFilter,
                                  child: const Text('Clear date'),
                                ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          children: [
                            FilterChip(
                              label: const Text('Today'),
                              selected: _isQuickRangeSelected('today'),
                              onSelected: (_) => _setQuickDateRange('today'),
                            ),
                            FilterChip(
                              label: const Text('Last 7 days'),
                              selected: _isQuickRangeSelected('week'),
                              onSelected: (_) => _setQuickDateRange('week'),
                            ),
                            FilterChip(
                              label: const Text('This month'),
                              selected: _isQuickRangeSelected('month'),
                              onSelected: (_) => _setQuickDateRange('month'),
                            ),
                            FilterChip(
                              label: const Text('All dates'),
                              selected: _dateFrom == null && _dateTo == null,
                              onSelected: (_) => _clearDateFilter(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredOrders.isEmpty
                    ? Center(child: Text(l10n.noOrdersFound))
                    : ListView.builder(
                        itemCount: _filteredOrders.length,
                        itemBuilder: (context, index) {
                          final order = _filteredOrders[index];
                          final orderNumber = order['order_number'] ?? 'N/A';
                          final total = (order['total_amount'] ?? 0.0) as num;
                          final createdAt = order['created_at'];
                          final status = order['status'] ?? 'pending';

                          final notSynced = (order['synced'] ?? 1) != 1;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: InkWell(
                              onTap: () async {
                                final updatedOrder = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => OrderDetailsScreen(order: order),
                                  ),
                                );
                                // If order was updated, refresh the list
                                if (updatedOrder != null) {
                                  _loadOrders();
                                }
                              },
                              child: ListTile(
                                leading: notSynced
                                    ? const CircleAvatar(
                                        radius: 6,
                                        backgroundColor: Colors.red,
                                      )
                                    : null,
                                title: Text('${l10n.orderNumberHash(orderNumber)} - £${total.toStringAsFixed(2)}'),
                                subtitle: createdAt != null
                                    ? Text(
                                        l10n.date(_formatDate(createdAt)),
                                        style: TextStyle(color: Colors.grey[600]),
                                      )
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(
                                      label: Text(
                                        status.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      backgroundColor: _getStatusColor(status),
                                      padding: EdgeInsets.zero,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date is int) {
      return DateTime.fromMillisecondsSinceEpoch(date).toString().split('.')[0];
    } else if (date is String) {
      return date;
    }
    return 'Unknown';
  }
}

