import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/order_provider.dart';
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
        _filteredOrders = allOrders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading orders: $e')),
        );
      }
    }
  }

  void _searchOrders() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _filteredOrders = _orders;
      });
      return;
    }

    final queryLower = query.toLowerCase();
    final localMatches = _orders.where((order) {
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
            _filteredOrders = [localOrder];
            // Also add to main orders list
            if (!_orders.any((o) => o['order_number'] == localOrder['order_number'])) {
              _orders.insert(0, localOrder);
            }
          });
          return;
        }
      } catch (e) {
        debugPrint('Error fetching order from backend: $e');
      }
    }

    setState(() {
      _filteredOrders = localMatches;
    });
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

