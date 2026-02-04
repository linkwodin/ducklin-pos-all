import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class PrinterLogger {
  static final PrinterLogger instance = PrinterLogger._init();
  File? _logFile;
  bool _initialized = false;

  PrinterLogger._init();

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
      final logFileName = 'printer_log_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.txt';
      _logFile = File(path.join(logDir.path, logFileName));
      
      // Write initial log entry
      await _writeLog('=== Printer Logger Initialized ===');
      await _writeLog('Log file: ${_logFile!.path}');
      await _writeLog('Timestamp: ${now.toIso8601String()}');
      await _writeLog('');
      
      _initialized = true;
    } catch (e) {
      // Silently fail - don't break the app if logging fails
    }
  }

  Future<void> _writeLog(String message) async {
    if (_logFile == null) {
      await initialize();
      if (_logFile == null) return;
    }
    
    try {
      final timestamp = DateTime.now().toIso8601String();
      final logEntry = '[$timestamp] $message\n';
      await _logFile!.writeAsString(logEntry, mode: FileMode.append);
    } catch (e) {
      // Silently fail - don't break the app if logging fails
    }
  }

  Future<void> log(String message) async {
    await initialize();
    await _writeLog(message);
  }

  Future<void> logError(String message, [Object? error, StackTrace? stackTrace]) async {
    await initialize();
    await _writeLog('ERROR: $message');
    if (error != null) {
      await _writeLog('Exception: $error');
    }
    if (stackTrace != null) {
      await _writeLog('Stack trace: $stackTrace');
    }
  }

  Future<void> logDebug(String message) async {
    await initialize();
    await _writeLog('DEBUG: $message');
  }

  Future<void> logInfo(String message) async {
    await initialize();
    await _writeLog('INFO: $message');
  }

  Future<void> logSuccess(String message) async {
    await initialize();
    await _writeLog('SUCCESS: $message');
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

