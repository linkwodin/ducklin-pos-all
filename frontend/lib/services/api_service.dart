import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import 'api_logger.dart';
import 'database_service.dart';

bool _isBinaryResponse(dynamic data) {
  return data is List<int> ||
      data is Uint8List ||
      (data is List && data.isNotEmpty && data.first is int);
}

class ApiService {
  static final ApiService instance = ApiService._init();
  late Dio _dio;
  String? _baseUrl;
  String? _deviceCode;

  ApiService._init();

  Future<void> initialize() async {
    // Initialize API logger
    await ApiLogger.instance.initialize();
    final logPath = ApiLogger.instance.getLogFilePath();
    if (logPath != null) {
      print('API Service: Logging to file: $logPath');
    }
    
    // Use environment-based configuration
    // Can be overridden with --dart-define=API_BASE_URL=...
    const apiBaseUrlEnv = String.fromEnvironment('API_BASE_URL');
    _baseUrl = apiBaseUrlEnv.isNotEmpty ? apiBaseUrlEnv : ApiConfig.baseUrl;
    
    print('API Service: Initializing with base URL: $_baseUrl');
    
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl!,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
      },
    ));
    
    print('API Service: Dio instance created');

    // Add interceptor for JWT token and logging
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        
        // Log request to file
        await ApiLogger.instance.logRequest(
          options.method,
          options.uri.toString(),
          headers: options.headers,
          data: options.data,
        );
        
        print('API Service: Request - ${options.method} ${options.uri}');
        print('API Service: Request headers: ${options.headers}');
        print('API Service: Request data: ${options.data}');
        
        handler.next(options);
      },
      onResponse: (response, handler) async {
        // Log response to file (binary data is summarized to avoid freezing UI)
        await ApiLogger.instance.logResponse(
          response.statusCode,
          response.requestOptions.uri.toString(),
          data: response.data,
        );
        
        print('API Service: Response - ${response.statusCode} ${response.requestOptions.uri}');
        final rd = response.data;
        if (rd != null && _isBinaryResponse(rd)) {
          final len = rd is List ? rd.length : (rd is Uint8List ? rd.length : 0);
          print('API Service: Response data: [binary, $len bytes]');
        } else {
          print('API Service: Response data: $rd');
        }
        
        // Update last activity time on any successful API response
        if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('last_activity_time', DateTime.now().millisecondsSinceEpoch);
            
            // Check if response contains a new token (for token refresh scenarios)
            final responseData = response.data;
            if (responseData is Map<String, dynamic>) {
              if (responseData.containsKey('token')) {
                final newToken = responseData['token'] as String?;
                if (newToken != null && newToken.isNotEmpty) {
                  print('API Service: Received new token in response, updating...');
                  await prefs.setString('jwt_token', newToken);
                  
                  // Also update user info if provided
                  if (responseData.containsKey('user')) {
                    final user = responseData['user'] as Map<String, dynamic>?;
                    if (user != null) {
                      if (user['role'] != null) {
                        await prefs.setString('user_role', user['role'].toString());
                      }
                      if (user['id'] != null) {
                        final userId = user['id'];
                        if (userId is int) {
                          await prefs.setInt('user_id', userId);
                        } else if (userId is String) {
                          await prefs.setInt('user_id', int.parse(userId));
                        }
                      }
                    }
                  }
                }
              }
            }
          } catch (e) {
            print('API Service: Error updating activity time or token: $e');
          }
        }
        
        handler.next(response);
      },
      onError: (error, handler) async {
        // Log error to file
        await ApiLogger.instance.logError(
          error.type.toString(),
          error.message ?? 'Unknown error',
          error.requestOptions.uri.toString(),
          statusCode: error.response?.statusCode,
          responseData: error.response?.data,
        );
        
        print('API Service: Error in interceptor - ${error.type}');
        print('API Service: Error message: ${error.message}');
        final errData = error.response?.data;
        if (errData != null && _isBinaryResponse(errData)) {
          final len = errData is List ? errData.length : (errData is Uint8List ? errData.length : 0);
          print('API Service: Error response: [binary, $len bytes]');
        } else {
          print('API Service: Error response: $errData');
        }
        print('API Service: Error status code: ${error.response?.statusCode}');
        
        if (error.response?.statusCode == 401) {
          // Only clear token when the server rejected our token (invalid/expired).
          // Do not clear on "Authorization header required" (we didn't send one).
          final msg = errData is Map ? (errData['error'] ?? '').toString() : '';
          final tokenWasRejected = msg.contains('Invalid token') ||
              msg.contains('Invalid token claims') ||
              msg.contains('expired');
          if (tokenWasRejected) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('jwt_token');
            await prefs.remove('last_activity_time');
            await prefs.remove('user_role');
            await prefs.remove('user_id');
          }
        } else {
          // For non-401 errors, still update activity time (user is still active)
          // This helps distinguish between network errors and actual inactivity
          try {
            final prefs = await SharedPreferences.getInstance();
            final token = prefs.getString('jwt_token');
            if (token != null && token.isNotEmpty) {
              await prefs.setInt('last_activity_time', DateTime.now().millisecondsSinceEpoch);
            }
          } catch (e) {
            // Ignore errors
          }
        }
        handler.next(error);
      },
    ));

    // Get or generate device code
    await _initializeDeviceCode();
  }

  Future<void> _initializeDeviceCode() async {
    try {
      print('API Service: Initializing device code...');
      
      // Check if device ID is provided via dart-define
      const deviceIdOverride = String.fromEnvironment('DEVICE_ID');
      if (deviceIdOverride.isNotEmpty) {
        _deviceCode = deviceIdOverride;
        print('API Service: Using device ID from DEVICE_ID environment: $_deviceCode');
        return;
      }
      
      // Generate from device info
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceCode = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceCode = iosInfo.identifierForVendor ?? 'ios_${DateTime.now().millisecondsSinceEpoch}';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        _deviceCode = windowsInfo.deviceId;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        _deviceCode = macInfo.systemGUID;
        print('API Service: Device code (macOS): $_deviceCode');
      } else if (Platform.isLinux) {
        _deviceCode = 'linux_${DateTime.now().millisecondsSinceEpoch}';
      } else {
        _deviceCode = 'device_${DateTime.now().millisecondsSinceEpoch}';
      }
      print('API Service: Device code initialized: $_deviceCode');
    } catch (e) {
      print('API Service: Error initializing device code: $e');
      _deviceCode = 'device_${DateTime.now().millisecondsSinceEpoch}';
      print('API Service: Using fallback device code: $_deviceCode');
    }
  }

  String? get deviceCode => _deviceCode;

  // Auth endpoints
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      print('API Service: Attempting login to $_baseUrl/auth/login');
      print('API Service: Username: $username');
      final response = await _dio.post('/auth/login', data: {
        'username': username,
        'password': password,
        if (_deviceCode != null) 'device_code': _deviceCode,
      });
      print('API Service: Login successful, response: ${response.data}');
      return response.data;
    } catch (e) {
      print('API Service: Login error: $e');
      if (e is DioException) {
        print('API Service: DioException - ${e.type}');
        print('API Service: Response: ${e.response?.data}');
        print('API Service: Status code: ${e.response?.statusCode}');
        print('API Service: Request URL: ${e.requestOptions.uri}');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> pinLogin(String username, String pin) async {
    final response = await _dio.post('/auth/pin-login', data: {
      'username': username,
      'pin': pin,
      'device_code': _deviceCode,
    });
    return response.data;
  }

  /// Record day-start stocktake: first_login (on first login of day), done, or skipped with reason.
  /// [storeId] is the store where the user is working (required for correct timetable per store).
  /// On network failure, saves event locally for sync when back online (unless [skipLocalSaveOnFailure]).
  Future<void> recordStocktakeDayStart(
    String action, {
    String? skipReason,
    int? storeId,
    bool skipLocalSaveOnFailure = false,
  }) async {
    final data = <String, dynamic>{'action': action};
    if (skipReason != null && skipReason.isNotEmpty) data['skip_reason'] = skipReason;
    if (storeId != null) data['store_id'] = storeId;
    try {
      await _dio.post('/stocktake-day-start', data: data);
    } catch (e) {
      if (!skipLocalSaveOnFailure) {
        await _savePendingUserActivityEvent(
          eventType: action,
          storeId: storeId,
          skipReason: skipReason,
        );
      }
      rethrow;
    }
  }

  /// Record day-end stocktake skipped with reason (for activity history).
  /// On network failure, saves event locally for sync when back online (unless [skipLocalSaveOnFailure]).
  Future<void> recordStocktakeDayEndSkip({
    required String skipReason,
    int? storeId,
    bool skipLocalSaveOnFailure = false,
  }) async {
    final data = <String, dynamic>{'action': 'day_end_skipped', 'skip_reason': skipReason};
    if (storeId != null) data['store_id'] = storeId;
    try {
      await _dio.post('/stocktake-day-start', data: data);
    } catch (e) {
      if (!skipLocalSaveOnFailure) {
        await _savePendingUserActivityEvent(
          eventType: 'day_end_skipped',
          storeId: storeId,
          skipReason: skipReason,
        );
      }
      rethrow;
    }
  }

  /// Record logout for activity history (login/logout timeline).
  /// On network failure, saves event locally for sync when back online (unless [skipLocalSaveOnFailure]).
  Future<void> recordLogout({int? storeId, bool skipLocalSaveOnFailure = false}) async {
    final data = <String, dynamic>{'action': 'logout'};
    if (storeId != null) data['store_id'] = storeId;
    try {
      await _dio.post('/stocktake-day-start', data: data);
    } catch (e) {
      if (!skipLocalSaveOnFailure) {
        await _savePendingUserActivityEvent(eventType: 'logout', storeId: storeId);
      }
    }
  }

  Future<void> _savePendingUserActivityEvent({
    required String eventType,
    int? storeId,
    String? skipReason,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId == null) return;
      final now = DateTime.now().toUtc().toIso8601String();
      await DatabaseService.instance.savePendingUserActivityEvent(
        userId: userId,
        storeId: storeId,
        eventType: eventType,
        occurredAt: now,
        skipReason: skipReason,
      );
    } catch (_) {}
  }

  // Device endpoints
  Future<void> registerDevice(String deviceCode, int storeId, {String? deviceName}) async {
    await _dio.post('/device/register', data: {
      'device_code': deviceCode,
      'store_id': storeId,
      'device_name': deviceName,
    });
  }

  /// Add or update this device's store (management only). Creates device if not exists.
  Future<Map<String, dynamic>> configureDevice(String deviceCode, int storeId, {String? deviceName}) async {
    final response = await _dio.put('/device/configure', data: {
      'device_code': deviceCode,
      'store_id': storeId,
      if (deviceName != null && deviceName.isNotEmpty) 'device_name': deviceName,
    });
    return response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : Map<String, dynamic>.from(response.data as Map);
  }

  /// List stores (protected). Used by admin device config.
  Future<List<dynamic>> getStores() async {
    final response = await _dio.get('/stores');
    return response.data is List ? response.data as List<dynamic> : [];
  }

  Future<List<dynamic>> getUsersForDevice(String deviceCode) async {
    try {
      print('API Service: Fetching users for device: $deviceCode');
      final response = await _dio.get('/device/$deviceCode/users');
      print('API Service: Received ${response.data.length} users');
      return response.data;
    } catch (e) {
      print('API Service: Error fetching users: $e');
      if (e is DioException) {
        print('API Service: DioException - ${e.type}');
        print('API Service: Response: ${e.response?.data}');
        print('API Service: Status code: ${e.response?.statusCode}');
        print('API Service: Request URL: ${e.requestOptions.uri}');
      }
      rethrow;
    }
  }

  Future<List<dynamic>> getProductsForDevice(String deviceCode) async {
    final response = await _dio.get('/device/$deviceCode/products');
    return response.data;
  }

  /// Device info including last_stocktake_at for the device's store (from user_activity_events).
  /// Returns map with device_code, store_id, device_name, last_stocktake_at (String? RFC3339), or null if device not found.
  Future<Map<String, dynamic>?> getDeviceInfo(String deviceCode) async {
    try {
      final response = await _dio.get('/device/$deviceCode/info');
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Download image (or any file) from [url] and return bytes. Uses full URL as-is.
  Future<Uint8List?> downloadUrl(String url) async {
    try {
      final r = await _dio.get<dynamic>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = r.data;
      if (data == null) return null;
      if (data is Uint8List) return data;
      if (data is List<int>) return Uint8List.fromList(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Health check (GET /health at server root). Returns true if server is reachable.
  Future<bool> healthCheck() async {
    try {
      final root = _baseUrl!.replaceFirst(RegExp(r'/api/v1/?$'), '');
      final healthUrl = '$root/health';
      final response = await _dio.get(healthUrl);
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (_) {
      return false;
    }
  }

  // Order endpoints
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> orderData) async {
    try {
      print('API Service: Creating order...');
      print('API Service: Order data: $orderData');
      print('API Service: POST to $_baseUrl/orders');
      final response = await _dio.post('/orders', data: orderData);
      print('API Service: Order created successfully');
      print('API Service: Response status: ${response.statusCode}');
      print('API Service: Response data: ${response.data}');
      return response.data;
    } catch (e) {
      print('API Service: Error creating order: $e');
      if (e is DioException) {
        print('API Service: DioException type: ${e.type}');
        print('API Service: DioException message: ${e.message}');
        print('API Service: Request URL: ${e.requestOptions.uri}');
        print('API Service: Request data: ${e.requestOptions.data}');
        print('API Service: Request headers: ${e.requestOptions.headers}');
        print('API Service: Response status: ${e.response?.statusCode}');
        print('API Service: Response data: ${e.response?.data}');
        print('API Service: Error type: ${e.type}');
        if (e.type == DioExceptionType.connectionTimeout) {
          print('API Service: Connection timeout - server may not be reachable');
        } else if (e.type == DioExceptionType.receiveTimeout) {
          print('API Service: Receive timeout - server took too long to respond');
        } else if (e.type == DioExceptionType.connectionError) {
          print('API Service: Connection error - cannot connect to server');
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> markOrderPaid(int orderId) async {
    final response = await _dio.put('/orders/$orderId/pay');
    return response.data;
  }

  Future<Map<String, dynamic>> markOrderComplete(int orderId) async {
    final response = await _dio.put('/orders/$orderId/complete');
    return response.data;
  }

  Future<Map<String, dynamic>> confirmOrderPickup(
    String orderNumber, {
    String? checkCode,
    String? receiptType,
    String? invoiceCheckCode,
    String? receiptCheckCode,
  }) async {
    String url = '/orders/pickup/$orderNumber';
    final params = <String>[];
    
    // New format: send both check codes if provided
    if (invoiceCheckCode != null && invoiceCheckCode.isNotEmpty && 
        receiptCheckCode != null && receiptCheckCode.isNotEmpty) {
      params.add('invoice_check_code=$invoiceCheckCode');
      params.add('receipt_check_code=$receiptCheckCode');
    } else {
      // Old format: single check code (backward compatibility)
      if (checkCode != null && checkCode.isNotEmpty) {
        params.add('check_code=$checkCode');
      }
      if (receiptType != null && receiptType.isNotEmpty) {
        params.add('receipt_type=$receiptType');
      }
    }
    
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }
    final response = await _dio.put(url);
    return response.data;
  }

  Future<Map<String, dynamic>> cancelOrder(int orderId) async {
    final response = await _dio.put('/orders/$orderId/cancel');
    return response.data;
  }

  Future<Map<String, dynamic>> getOrder(String orderIdOrNumber) async {
    final response = await _dio.get('/orders/$orderIdOrNumber');
    return response.data;
  }

  /// GET /orders/stats/revenue. Query: start_date, end_date (YYYY-MM-DD), optional store_id.
  /// Returns list of { date, revenue, order_count }.
  Future<List<dynamic>> getDailyRevenueStats({
    String? startDate,
    String? endDate,
    int? storeId,
  }) async {
    final queryParams = <String, dynamic>{};
    if (startDate != null) queryParams['start_date'] = startDate;
    if (endDate != null) queryParams['end_date'] = endDate;
    if (storeId != null) queryParams['store_id'] = storeId;
    final response = await _dio.get(
      '/orders/stats/revenue',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return response.data is List ? response.data as List<dynamic> : [];
  }

  /// GET /orders/stats/product-sales. Query: start_date, end_date (YYYY-MM-DD), optional store_id.
  /// Returns list of { date, product_id, product_name, product_name_chinese, quantity, revenue }.
  Future<List<dynamic>> getDailyProductSalesStats({
    String? startDate,
    String? endDate,
    int? storeId,
  }) async {
    final queryParams = <String, dynamic>{};
    if (startDate != null) queryParams['start_date'] = startDate;
    if (endDate != null) queryParams['end_date'] = endDate;
    if (storeId != null) queryParams['store_id'] = storeId;
    final response = await _dio.get(
      '/orders/stats/product-sales',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return response.data is List ? response.data as List<dynamic> : [];
  }

  // Stock endpoints
  Future<List<dynamic>> getStoreStock(int storeId) async {
    final response = await _dio.get('/stock/$storeId');
    return response.data;
  }

  Future<List<dynamic>> getIncomingStock({int? storeId}) async {
    final queryParams = storeId != null ? {'store_id': storeId} : <String, dynamic>{};
    final response = await _dio.get('/stock/incoming', queryParameters: queryParams);
    return response.data;
  }

  Future<Map<String, dynamic>> updateStock(
    int productId,
    int storeId, {
    required double quantity,
    double? lowStockThreshold,
    String? reason,
  }) async {
    final response = await _dio.put(
      '/stock/$productId/$storeId',
      data: {
        'quantity': quantity,
        if (lowStockThreshold != null) 'low_stock_threshold': lowStockThreshold,
        if (reason != null) 'reason': reason,
      },
    );
    return response.data;
  }

  Future<List<dynamic>> getRestockOrders({int? storeId}) async {
    final queryParams = storeId != null ? {'store_id': storeId} : <String, dynamic>{};
    final response = await _dio.get('/restock-orders', queryParameters: queryParams);
    return response.data;
  }

  Future<Map<String, dynamic>> receiveRestockOrder(int orderId) async {
    final response = await _dio.put('/restock-orders/$orderId/receive');
    return response.data;
  }

  // User endpoints
  Future<Map<String, dynamic>> getUser(int userId) async {
    final response = await _dio.get('/users/$userId');
    return response.data;
  }

  Future<void> updateUserPIN(int userId, String currentPin, String newPin) async {
    await _dio.put('/users/$userId/pin', data: {
      'current_pin': currentPin,
      'pin': newPin,
    });
  }

  Future<Map<String, dynamic>> updateUserIconFile(int userId, XFile imageFile) async {
    final formData = FormData.fromMap({
      'icon': await MultipartFile.fromFile(imageFile.path, filename: imageFile.name),
    });
    final response = await _dio.put(
      '/users/$userId/icon',
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
      ),
    );
    return response.data;
  }

  Future<Map<String, dynamic>> updateUserIconColors(int userId, String bgColor, String textColor) async {
    final response = await _dio.put('/users/$userId/icon', data: {
      'bg_color': bgColor,
      'text_color': textColor,
    });
    return response.data;
  }
}

