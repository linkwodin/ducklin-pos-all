import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

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
      onResponse: (response, handler) {
        print('API Service: Response - ${response.statusCode} ${response.requestOptions.uri}');
        print('API Service: Response data: ${response.data}');
        handler.next(response);
      },
      onError: (error, handler) async {
        print('API Service: Error in interceptor - ${error.type}');
        print('API Service: Error message: ${error.message}');
        print('API Service: Error response: ${error.response?.data}');
        print('API Service: Error status code: ${error.response?.statusCode}');
        
        if (error.response?.statusCode == 401) {
          // Token expired, clear and redirect to login
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('jwt_token');
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
}

