// API Configuration for different environments
class ApiConfig {
  // Environment detection
  static const String environment = String.fromEnvironment(
    'ENV',
    defaultValue: 'development',
  );

  // Base URLs for different environments
  static const String _devUrl = 'http://127.0.0.1:8868/api/v1';
  static const String _uatUrl = 'https://pos-backend-28040503481.europe-west1.run.app/api/v1';
  static const String _prodUrl = 'https://YOUR-PROD-BACKEND-URL.run.app/api/v1';

  // Get base URL based on environment
  static String get baseUrl {
    switch (environment.toLowerCase()) {
      case 'uat':
        return _uatUrl;
      case 'production':
      case 'prod':
        return _prodUrl;
      case 'development':
      case 'dev':
      default:
        return _devUrl;
    }
  }

  // Helper method to check current environment
  static bool get isDevelopment => environment == 'development';
  static bool get isUAT => environment == 'uat';
  static bool get isProduction => environment == 'production' || environment == 'prod';
}

