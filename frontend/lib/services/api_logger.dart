import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ApiLogger {
  static final ApiLogger instance = ApiLogger._init();
  File? _logFile;
  bool _initialized = false;

  ApiLogger._init();

  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // Get application documents directory
      final directory = await getApplicationDocumentsDirectory();
      final logDir = Directory(path.join(directory.path, 'pos_system', 'logs'));
      
      // Create logs directory if it doesn't exist
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      
      // Create log file with current date
      final now = DateTime.now();
      final logFileName = 'api_log_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.txt';
      _logFile = File(path.join(logDir.path, logFileName));
      
      // Write initial log entry
      await _writeLog('=== API Logger Initialized ===');
      await _writeLog('Log file: ${_logFile!.path}');
      await _writeLog('Timestamp: ${now.toIso8601String()}');
      await _writeLog('');
      
      _initialized = true;
      print('API Logger: Log file initialized at ${_logFile!.path}');
    } catch (e) {
      print('API Logger: Failed to initialize file logging: $e');
      // Continue without file logging
    }
  }

  Future<void> _writeLog(String message) async {
    if (_logFile == null) return;
    
    try {
      final timestamp = DateTime.now().toIso8601String();
      final logEntry = '[$timestamp] $message\n';
      await _logFile!.writeAsString(logEntry, mode: FileMode.append);
    } catch (e) {
      // Silently fail - don't break the app if logging fails
      print('API Logger: Failed to write log: $e');
    }
  }

  Future<void> logRequest(String method, String uri, {Map<String, dynamic>? headers, dynamic data}) async {
    await initialize();
    
    final logMessage = StringBuffer();
    logMessage.writeln('>>> REQUEST');
    logMessage.writeln('Method: $method');
    logMessage.writeln('URI: $uri');
    
    if (headers != null && headers.isNotEmpty) {
      logMessage.writeln('Headers:');
      headers.forEach((key, value) {
        // Mask sensitive headers
        if (key.toLowerCase() == 'authorization') {
          logMessage.writeln('  $key: Bearer ***');
        } else {
          logMessage.writeln('  $key: $value');
        }
      });
    }
    
    if (data != null) {
      if (_isBinaryData(data)) {
        final len = _binaryLength(data) ?? 0;
        logMessage.writeln('Data: [binary, $len bytes]');
      } else {
        logMessage.writeln('Data: $data');
      }
    }
    logMessage.writeln('');
    
    await _writeLog(logMessage.toString());
    print(logMessage.toString());
  }

  /// True if [data] is binary (bytes). Log as summary to avoid freezing UI.
  static bool _isBinaryData(dynamic data) {
    if (data == null) return false;
    return data is List<int> ||
        data is Uint8List ||
        (data is List && data.isNotEmpty && data.first is int);
  }

  static int? _binaryLength(dynamic data) {
    if (data is List<int>) return data.length;
    if (data is Uint8List) return data.length;
    if (data is List) return data.length;
    return null;
  }

  Future<void> logResponse(int? statusCode, String uri, {dynamic data}) async {
    await initialize();
    
    final logMessage = StringBuffer();
    logMessage.writeln('<<< RESPONSE');
    logMessage.writeln('Status: $statusCode');
    logMessage.writeln('URI: $uri');
    
    if (data != null) {
      if (_isBinaryData(data)) {
        final len = _binaryLength(data) ?? 0;
        logMessage.writeln('Data: [binary, $len bytes]');
      } else {
        final dataStr = data.toString();
        if (dataStr.length > 1000) {
          logMessage.writeln('Data: ${dataStr.substring(0, 1000)}... (truncated)');
        } else {
          logMessage.writeln('Data: $data');
        }
      }
    }
    logMessage.writeln('');
    
    await _writeLog(logMessage.toString());
    print(logMessage.toString());
  }

  Future<void> logError(String type, String message, String uri, {int? statusCode, dynamic responseData}) async {
    await initialize();
    
    final logMessage = StringBuffer();
    logMessage.writeln('!!! ERROR');
    logMessage.writeln('Type: $type');
    logMessage.writeln('Message: $message');
    logMessage.writeln('URI: $uri');
    
    if (statusCode != null) {
      logMessage.writeln('Status: $statusCode');
    }
    
    if (responseData != null) {
      if (_isBinaryData(responseData)) {
        final len = _binaryLength(responseData) ?? 0;
        logMessage.writeln('Response: [binary, $len bytes]');
      } else {
        logMessage.writeln('Response: $responseData');
      }
    }
    logMessage.writeln('');
    
    await _writeLog(logMessage.toString());
    print(logMessage.toString());
  }

  String? getLogFilePath() {
    return _logFile?.path;
  }

  Future<String> getLogDirectory() async {
    await initialize();
    final directory = await getApplicationDocumentsDirectory();
    return path.join(directory.path, 'pos_system', 'logs');
  }
}

