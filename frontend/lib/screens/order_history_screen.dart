import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/order_provider.dart';
import '../services/database_service.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
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

  void _searchOrders() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredOrders = _orders;
      });
      return;
    }

    setState(() {
      _filteredOrders = _orders.where((order) {
        final orderNumber = (order['order_number'] ?? '').toString().toLowerCase();
        final total = (order['total_amount'] ?? 0).toString().toLowerCase();
        final createdAt = (order['created_at'] ?? '').toString().toLowerCase();
        return orderNumber.contains(query) ||
            total.contains(query) ||
            createdAt.contains(query);
      }).toList();
    });
  }

  Future<void> _reprintOrder(Map<String, dynamic> order) async {
    // TODO: Implement reprint functionality
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reprint functionality coming soon')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
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
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
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

                          final l10n = AppLocalizations.of(context)!;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: ListTile(
                              title: Text('${l10n.orderNumberHash(orderNumber)} - £${total.toStringAsFixed(2)}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (createdAt != null)
                                    Text(l10n.date(_formatDate(createdAt))),
                                  Text('${l10n.status}: $status'),
                                ],
                              ),
                              trailing: ElevatedButton(
                                onPressed: () => _reprintOrder(order),
                                child: Text(l10n.reprint),
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

