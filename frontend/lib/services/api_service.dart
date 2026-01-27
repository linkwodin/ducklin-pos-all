import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';

class ApiService {
  static final ApiService instance = ApiService._init();
  late Dio _dio;
  String? _baseUrl;
  String? _deviceCode;

  ApiService._init();

  Future<void> initialize() async {
    _baseUrl = 'http://127.0.0.1:8868/api/v1'; // Replace with actual API URL
    
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
        print('API Service: Request - ${options.method} ${options.uri}');
        print('API Service: Request headers: ${options.headers}');
        print('API Service: Request data: ${options.data}');
        
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onResponse: (response, handler) async {
        print('API Service: Response - ${response.statusCode} ${response.requestOptions.uri}');
        print('API Service: Response data: ${response.data}');
        
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
        print('API Service: Error in interceptor - ${error.type}');
        print('API Service: Error message: ${error.message}');
        print('API Service: Error response: ${error.response?.data}');
        print('API Service: Error status code: ${error.response?.statusCode}');
        
        if (error.response?.statusCode == 401) {
          // Token expired or unauthorized, clear token and activity
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('jwt_token');
          await prefs.remove('last_activity_time');
          await prefs.remove('user_role');
          await prefs.remove('user_id');
          
          // Notify AuthProvider to logout
          // This will be handled by the AuthProvider's session monitoring
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

  // Device endpoints
  Future<void> registerDevice(String deviceCode, int storeId, {String? deviceName}) async {
    await _dio.post('/device/register', data: {
      'device_code': deviceCode,
      'store_id': storeId,
      'device_name': deviceName,
    });
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

