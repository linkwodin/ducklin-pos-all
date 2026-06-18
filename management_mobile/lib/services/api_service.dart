import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/admin.dart';
import '../models/endorse_allocation_preview.dart';
import '../models/pos_order.dart';
import '../models/product.dart';
import '../models/sector.dart';
import '../models/shipment.dart';
import '../models/stock.dart';
import '../models/store.dart';
import '../models/user.dart';
import '../models/wholesale_client.dart';
import '../models/wholesale_order.dart';
import '../utils/jwt_utils.dart';

class ApiService {
  ApiService._() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.data is FormData) {
            options.headers.remove('Content-Type');
          }
          var token = _token;
          if (token != null &&
              !options.path.contains('/auth/login') &&
              JwtUtils.expiresWithin(token, const Duration(minutes: 30))) {
            token = await refreshTokenIfNeeded(token);
          }
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final opts = error.requestOptions;
          if (error.response?.statusCode == 401 &&
              _token != null &&
              !opts.path.contains('/auth/login') &&
              !opts.path.contains('/auth/refresh') &&
              opts.extra['_retried'] != true) {
            final refreshed = await refreshTokenIfNeeded(_token!);
            if (refreshed != null) {
              _token = refreshed;
              opts.headers['Authorization'] = 'Bearer $refreshed';
              opts.extra['_retried'] = true;
              try {
                handler.resolve(await _dio.fetch(opts));
                return;
              } catch (e) {
                if (e is DioException) {
                  handler.next(e);
                  return;
                }
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  static final ApiService instance = ApiService._();

  String? _token;
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  void setToken(String? token) => _token = token;
  String get apiBaseUrl => AppConfig.apiBaseUrl;

  // --- Auth ---
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'username': username, 'password': password},
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> refresh(String token) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/refresh',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data ?? {};
  }

  Future<String?> refreshTokenIfNeeded(String token) async {
    if (!JwtUtils.isExpired(token) &&
        !JwtUtils.expiresWithin(token, const Duration(minutes: 30))) {
      return token;
    }
    try {
      final data = await refresh(token);
      final newToken = data['token']?.toString();
      if (newToken == null || newToken.isEmpty) return null;
      _token = newToken;
      return newToken;
    } catch (_) {
      return null;
    }
  }

  Future<AppUser> fetchUserProfile(int userId) async {
    final user = await getUser(userId);
    return user;
  }

  Future<List<int>> downloadUrl(String url) async {
    final parsed = Uri.tryParse(url);
    final apiHost = Uri.tryParse(AppConfig.apiBaseUrl)?.host;
    final isOwnApi = parsed != null &&
        apiHost != null &&
        parsed.host == apiHost &&
        !url.contains('storage.googleapis.com');

    if (!isOwnApi) {
      final external = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );
      final response = await external.get<List<int>>(url);
      return response.data ?? [];
    }

    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) => status != null && status >= 200 && status < 400,
      ),
    );
    return response.data ?? [];
  }

  Future<AppUser?> refreshSessionUser(String token) async {
    try {
      final data = await refresh(token);
      final user = data['user'];
      if (user is Map<String, dynamic>) {
        return AppUser.fromJson(user);
      }
    } catch (_) {}
    return null;
  }

  AppUser parseUser(Map<String, dynamic> response) {
    final user = response['user'];
    if (user is! Map<String, dynamic>) {
      throw DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        message: 'Invalid login response',
      );
    }
    return AppUser.fromJson(user);
  }

  String encodeUser(AppUser user) => jsonEncode(user.toJson());
  AppUser decodeUser(String userJson) =>
      AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);

  String errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
      return error.message ?? 'Network error';
    }
    return error.toString();
  }

  // --- Stores ---
  Future<List<Store>> listStores({bool excludeWarehouseOnly = false}) async {
    final response = await _dio.get<List<dynamic>>(
      '/stores',
      queryParameters: excludeWarehouseOnly ? {'exclude_warehouse_only': 'true'} : null,
    );
    return (response.data ?? []).map((e) => Store.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Store> createStore({required String name, String? address}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/stores',
      data: {'name': name, if (address != null) 'address': address},
    );
    return Store.fromJson(response.data ?? {});
  }

  // --- Users ---
  Future<List<AdminUser>> listUsers() async {
    final response = await _dio.get<List<dynamic>>('/users');
    return (response.data ?? []).map((e) => AdminUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AdminUser> getUser(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('/users/$id');
    return AdminUser.fromJson(response.data ?? {});
  }

  Future<AdminUser> createUser(Map<String, dynamic> body) async {
    final response = await _dio.post<Map<String, dynamic>>('/users', data: body);
    return AdminUser.fromJson(response.data ?? {});
  }

  Future<AdminUser> updateUser(int id, Map<String, dynamic> body) async {
    final response = await _dio.put<Map<String, dynamic>>('/users/$id', data: body);
    return AdminUser.fromJson(response.data ?? {});
  }

  Future<void> updateUserPin(int id, {required String currentPin, required String newPin}) async {
    await _dio.put('/users/$id/pin', data: {'current_pin': currentPin, 'pin': newPin});
  }

  Future<AdminUser> updateUserStores(int id, List<int> storeIds) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/users/$id/stores',
      data: {'store_ids': storeIds},
    );
    return AdminUser.fromJson(response.data ?? {});
  }

  // --- Products ---
  Future<List<Product>> listProducts({String? effectiveFrom, String? effectiveTo}) async {
    final response = await _dio.get<List<dynamic>>(
      '/products',
      queryParameters: {
        if (effectiveFrom != null) 'effective_from': effectiveFrom,
        if (effectiveTo != null) 'effective_to': effectiveTo,
      },
    );
    return (response.data ?? []).map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Product> getProduct(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('/products/$id');
    return Product.fromJson(response.data ?? {});
  }

  // --- Sectors & categories ---
  Future<List<Sector>> listSectors() async {
    final response = await _dio.get<List<dynamic>>('/sectors');
    return (response.data ?? []).map((e) => Sector.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Sector> createSector(String name, {String? description}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/sectors',
      data: {'name': name, if (description != null) 'description': description},
    );
    return Sector.fromJson(response.data ?? {});
  }

  Future<Sector> updateSector(int id, Map<String, dynamic> body) async {
    final response = await _dio.put<Map<String, dynamic>>('/sectors/$id', data: body);
    return Sector.fromJson(response.data ?? {});
  }

  Future<void> deleteSector(int id) async => _dio.delete('/sectors/$id');

  Future<List<String>> listCategories() async {
    final response = await _dio.get<Map<String, dynamic>>('/categories');
    final cats = response.data?['categories'];
    if (cats is List) return cats.map((e) => e.toString()).toList();
    return [];
  }

  Future<void> createCategory(String name) async {
    await _dio.post('/categories', data: {'name': name});
  }

  Future<void> deleteCategory(String name) async {
    await _dio.delete('/categories/${Uri.encodeComponent(name)}');
  }

  // --- Stock ---
  Future<List<StockRow>> listStock({int? storeId}) async {
    final response = await _dio.get<List<dynamic>>(
      '/stock',
      queryParameters: storeId != null ? {'store_id': storeId} : null,
    );
    return (response.data ?? []).map((e) => StockRow.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<StockRow>> getLowStock() async {
    final response = await _dio.get<List<dynamic>>('/stock/low-stock');
    return (response.data ?? []).map((e) => StockRow.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StockRow> updateStock(
    int productId,
    int storeId, {
    required double quantity,
    String? reason,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/stock/$productId/$storeId',
      data: {'quantity': quantity, if (reason != null) 'reason': reason},
    );
    return StockRow.fromJson(response.data ?? {});
  }

  // --- Restock ---
  Future<List<RestockOrder>> listRestockOrders({int? storeId, String? status}) async {
    final response = await _dio.get<List<dynamic>>(
      '/restock-orders',
      queryParameters: {
        if (storeId != null) 'store_id': storeId,
        if (status != null) 'status': status,
      },
    );
    return (response.data ?? []).map((e) => RestockOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RestockOrder> createRestockOrder({
    required int storeId,
    required List<Map<String, dynamic>> items,
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/restock-orders',
      data: {'store_id': storeId, 'items': items, if (notes != null) 'notes': notes},
    );
    return RestockOrder.fromJson(response.data ?? {});
  }

  Future<RestockOrder> receiveRestockOrder(int id) async {
    final response = await _dio.put<Map<String, dynamic>>('/restock-orders/$id/receive');
    return RestockOrder.fromJson(response.data ?? {});
  }

  // --- POS orders ---
  Future<List<PosOrder>> listPosOrders({
    int? storeId,
    String? status,
    int? userId,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/orders',
      queryParameters: {
        if (storeId != null) 'store_id': storeId,
        if (status != null) 'status': status,
        if (userId != null) 'user_id': userId,
      },
    );
    return (response.data ?? []).map((e) => PosOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PosOrder> getPosOrder(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('/orders/$id');
    return PosOrder.fromJson(response.data ?? {});
  }

  Future<PosOrder> markPosOrderPaid(int id) async {
    final response = await _dio.put<Map<String, dynamic>>('/orders/$id/pay');
    return PosOrder.fromJson(response.data ?? {});
  }

  Future<PosOrder> markPosOrderComplete(int id) async {
    final response = await _dio.put<Map<String, dynamic>>('/orders/$id/complete');
    return PosOrder.fromJson(response.data ?? {});
  }

  Future<PosOrder> cancelPosOrder(int id) async {
    final response = await _dio.put<Map<String, dynamic>>('/orders/$id/cancel');
    return PosOrder.fromJson(response.data ?? {});
  }

  Future<double> getTodayPosRevenue() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await getDailyRevenueStats(startDate: today, endDate: today);
    if (rows.isEmpty) return 0;
    return rows.fold<double>(0.0, (sum, row) => sum + row.revenue);
  }

  Future<List<({String date, double revenue, int orderCount})>> getDailyRevenueStats({
    String? startDate,
    String? endDate,
    int? storeId,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/orders/stats/revenue',
      queryParameters: {
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        if (storeId != null) 'store_id': storeId,
      },
    );
    return (response.data ?? []).map((e) {
      final row = e as Map<String, dynamic>;
      return (
        date: '${row['date'] ?? ''}',
        revenue: (row['revenue'] as num?)?.toDouble() ?? 0,
        orderCount: (row['order_count'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  // --- Wholesale clients ---
  Future<List<WholesaleClient>> listWholesaleClients({bool activeOnly = false}) async {
    final response = await _dio.get<List<dynamic>>(
      '/wholesale-clients',
      queryParameters: activeOnly ? {'active_only': 1} : null,
    );
    return (response.data ?? []).map((e) => WholesaleClient.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<WholesaleClient> getWholesaleClient(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('/wholesale-clients/$id');
    return WholesaleClient.fromJson(response.data ?? {});
  }

  Future<WholesaleClient> createWholesaleClient(Map<String, dynamic> body) async {
    final response = await _dio.post<Map<String, dynamic>>('/wholesale-clients', data: body);
    return WholesaleClient.fromJson(response.data ?? {});
  }

  Future<WholesaleClient> updateWholesaleClient(int id, Map<String, dynamic> body) async {
    final response = await _dio.put<Map<String, dynamic>>('/wholesale-clients/$id', data: body);
    return WholesaleClient.fromJson(response.data ?? {});
  }

  Future<void> deleteWholesaleClient(int id) async => _dio.delete('/wholesale-clients/$id');

  Future<WholesaleClientStore> createWholesaleClientStore(int clientId, Map<String, dynamic> body) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/wholesale-clients/$clientId/stores',
      data: body,
    );
    return WholesaleClientStore.fromJson(response.data ?? {});
  }

  // --- Wholesale orders ---
  Future<List<WholesaleOrder>> listWholesaleOrders({Map<String, String>? filters}) async {
    final response = await _dio.get<List<dynamic>>(
      '/wholesale-orders',
      queryParameters: filters,
    );
    return (response.data ?? []).map((e) => WholesaleOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<WholesaleOrder> getWholesaleOrder(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('/wholesale-orders/$id');
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> createWholesaleOrder(Map<String, dynamic> body) async {
    final response = await _dio.post<Map<String, dynamic>>('/wholesale-orders', data: body);
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> updateWholesaleOrder(int id, Map<String, dynamic> body) async {
    final response = await _dio.put<Map<String, dynamic>>('/wholesale-orders/$id', data: body);
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> approveWholesaleOrder(int id) async {
    final response = await _dio.put<Map<String, dynamic>>('/wholesale-orders/$id/approve');
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> rejectWholesaleOrder(int id, {String reason = ''}) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/wholesale-orders/$id/reject',
      data: {'reason': reason},
    );
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> resubmitWholesaleOrder(int id) async {
    final response = await _dio.put<Map<String, dynamic>>('/wholesale-orders/$id/resubmit');
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> assignWholesaleOrder(
    int id,
    List<Map<String, dynamic>> assignments,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/wholesale-orders/$id/assign',
      data: {'assignments': assignments},
    );
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> unassignWholesaleOrder(
    int id,
    List<Map<String, dynamic>> assignments,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/wholesale-orders/$id/unassign',
      data: {'assignments': assignments},
    );
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> regenerateOrderConfirmation(int id) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/wholesale-orders/$id/regenerate-order-confirmation',
    );
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> generateInvoice(int id) async {
    final response = await _dio.post<Map<String, dynamic>>('/wholesale-orders/$id/generate-invoice');
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> sendWholesaleEmail(
    int id, {
    required String emailType,
    required List<String> attachments,
    List<String>? to,
    String? recipient,
    String? cc,
    List<String>? ccList,
    String? bcc,
    List<String>? bccList,
    String? subject,
    String? message,
    List<int>? shipmentIds,
    int? signedDeliveryShipmentId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/wholesale-orders/$id/email',
      data: {
        'email_type': emailType,
        'attachments': attachments,
        if (to != null && to.isNotEmpty) 'to': to,
        if (recipient != null && recipient.isNotEmpty) 'recipient': recipient,
        if (cc != null && cc.isNotEmpty) 'cc': cc,
        if (ccList != null && ccList.isNotEmpty) 'cc_list': ccList,
        if (bcc != null && bcc.isNotEmpty) 'bcc': bcc,
        if (bccList != null && bccList.isNotEmpty) 'bcc_list': bccList,
        if (subject != null && subject.isNotEmpty) 'subject': subject,
        if (message != null && message.isNotEmpty) 'message': message,
        if (shipmentIds != null && shipmentIds.isNotEmpty) 'shipment_ids': shipmentIds,
        if (signedDeliveryShipmentId != null) 'signed_delivery_shipment_id': signedDeliveryShipmentId,
      },
      options: Options(receiveTimeout: const Duration(seconds: 120)),
    );
    final order = response.data?['order'];
    if (order is Map<String, dynamic>) return WholesaleOrder.fromJson(order);
    return getWholesaleOrder(id);
  }

  Future<void> skipWholesaleEmail(
    int id, {
    required String emailType,
    required String remark,
  }) async {
    await _dio.post('/wholesale-orders/$id/skip-email', data: {
      'email_type': emailType,
      'remark': remark,
    });
  }

  Future<void> deletePaymentProof(int orderId, int docId) async {
    await _dio.delete('/wholesale-orders/$orderId/documents/$docId');
  }

  Future<WholesaleOrder> assignWholesaleByDefaults(int id) async {
    final response = await _dio.put<Map<String, dynamic>>('/wholesale-orders/$id/assign-by-defaults');
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<EndorseAllocationPreview> getEndorseAllocationPreview(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/wholesale-orders/$id/endorse-allocation-preview',
    );
    return EndorseAllocationPreview.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> completeWholesaleAssignment(int id) async {
    final response = await _dio.put<Map<String, dynamic>>('/wholesale-orders/$id/complete-assignment');
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<WholesaleOrder> confirmWholesalePayment(
    int id, {
    double? amount,
    String? transferDate,
    String? transferredTo,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/wholesale-orders/$id/confirm-payment',
      data: {
        if (amount != null) 'amount': amount,
        if (transferDate != null) 'transfer_date': transferDate,
        if (transferredTo != null) 'transferred_to': transferredTo,
      },
    );
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<List<AuditLogEntry>> getWholesaleAuditLogs(int orderId) async {
    final response = await _dio.get<List<dynamic>>('/wholesale-orders/$orderId/audit-logs');
    return (response.data ?? []).map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> uploadPoAttachments(int orderId, List<String> filePaths) async {
    final form = FormData();
    for (final path in filePaths) {
      form.files.add(MapEntry('po_attachments', await MultipartFile.fromFile(path)));
    }
    await _dio.post('/wholesale-orders/$orderId/po-attachments', data: form);
  }

  Future<Uint8List> downloadWholesaleDocument(int orderId, int docId) async {
    final response = await _dio.get<List<int>>(
      '/wholesale-orders/$orderId/documents/$docId/download',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? []);
  }

  // --- Shipments ---
  Future<List<Shipment>> listShipments({
    int? storeId,
    String? status,
    bool includeOldCompleted = false,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/shipments',
      queryParameters: {
        if (storeId != null) 'store_id': storeId,
        if (status != null) 'status': status,
        if (includeOldCompleted) 'include_old_completed': 'true',
      },
    );
    return (response.data ?? []).map((e) => Shipment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Shipment> getShipment(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('/shipments/$id');
    return Shipment.fromJson(response.data ?? {});
  }

  Future<Shipment> updateShipment(
    int id, {
    String? courier,
    String? trackingNumber,
    String? deliveryDate,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/shipments/$id',
      data: {
        if (courier != null) 'courier': courier,
        if (trackingNumber != null) 'tracking_number': trackingNumber,
        if (deliveryDate != null) 'delivery_date': deliveryDate,
      },
    );
    return Shipment.fromJson(response.data ?? {});
  }

  Future<Shipment> startShipment(
    int id, {
    required List<Map<String, dynamic>> caseQty,
    String? deliveryDate,
    String? courier,
    String? trackingNumber,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/shipments/$id/start-shipment',
      data: {
        'case_qty': caseQty,
        if (deliveryDate != null && deliveryDate.isNotEmpty) 'delivery_date': deliveryDate,
        if (courier != null && courier.isNotEmpty) 'courier': courier,
        if (trackingNumber != null && trackingNumber.isNotEmpty) 'tracking_number': trackingNumber,
      },
    );
    return Shipment.fromJson(response.data ?? {});
  }

  Future<List<StockRow>> getStoreStock(int storeId) async {
    final response = await _dio.get<List<dynamic>>('/stock/$storeId');
    return (response.data ?? []).map((e) => StockRow.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<WholesaleOrder> uploadPaymentProofs(
    int orderId,
    List<String> filePaths, {
    double? amount,
    String? transferDate,
    String? transferredTo,
  }) async {
    final form = FormData();
    for (final path in filePaths) {
      form.files.add(MapEntry('payment_proofs', await MultipartFile.fromFile(path)));
    }
    if (amount != null) form.fields.add(MapEntry('amount', '$amount'));
    if (transferDate != null) form.fields.add(MapEntry('transfer_date', transferDate));
    if (transferredTo != null) form.fields.add(MapEntry('transferred_to', transferredTo));
    final response = await _dio.post<Map<String, dynamic>>(
      '/wholesale-orders/$orderId/upload-payment-proof',
      data: form,
    );
    return WholesaleOrder.fromJson(response.data ?? {});
  }

  Future<Shipment> completeShipmentPacking(int id) async {
    final response = await _dio.post<Map<String, dynamic>>('/shipments/$id/complete-packing');
    return Shipment.fromJson(response.data ?? {});
  }

  Future<Shipment> updateShipmentStatus(int id, String status) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/shipments/$id/status',
      data: {'status': status},
    );
    return Shipment.fromJson(response.data ?? {});
  }

  Future<void> uploadSignedDeliveryNote(int shipmentId, String filePath) async {
    final form = FormData.fromMap({
      'signed_delivery_note': await MultipartFile.fromFile(filePath),
    });
    await _dio.post('/shipments/$shipmentId/upload-signed-delivery-note', data: form);
  }

  // --- Devices ---
  Future<List<PosDevice>> listDevices() async {
    final response = await _dio.get<List<dynamic>>('/devices');
    return (response.data ?? []).map((e) => PosDevice.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PosDevice> registerDevice({
    required String deviceCode,
    required int storeId,
    String? deviceName,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/device/register',
      data: {
        'device_code': deviceCode,
        'store_id': storeId,
        if (deviceName != null) 'device_name': deviceName,
      },
    );
    return PosDevice.fromJson(response.data ?? {});
  }

  // --- Currency & settings ---
  Future<List<CurrencyRate>> listCurrencyRates() async {
    final response = await _dio.get<List<dynamic>>('/currency-rates');
    return (response.data ?? []).map((e) => CurrencyRate.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CurrencyRate> createCurrencyRate(String code, double rate) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/currency-rates',
      data: {'currency_code': code, 'rate_to_gbp': rate},
    );
    return CurrencyRate.fromJson(response.data ?? {});
  }

  Future<void> deleteCurrencyRate(String code) async => _dio.delete('/currency-rates/$code');

  Future<CompanySettings> getCompanySettings() async {
    final response = await _dio.get<Map<String, dynamic>>('/settings/company');
    return CompanySettings.fromJson(response.data ?? {});
  }

  Future<CompanySettings> updateCompanySettings(Map<String, dynamic> body) async {
    final response = await _dio.put<Map<String, dynamic>>('/settings/company', data: body);
    return CompanySettings.fromJson(response.data ?? {});
  }

  // --- Preferences ---
  static const _biometricEnabledKey = 'biometric_enabled';
  static const _savedUsernameKey = 'saved_username';

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, enabled);
  }

  Future<String?> savedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedUsernameKey);
  }

  Future<void> saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedUsernameKey, username);
  }

  Future<void> clearPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_biometricEnabledKey);
    await prefs.remove(_savedUsernameKey);
  }
}
