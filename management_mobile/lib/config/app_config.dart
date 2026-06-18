/// Runtime configuration via --dart-define.
///
/// Example:
/// flutter run --dart-define=ENV=uat
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8868/api/v1
class AppConfig {
  static const String environment = String.fromEnvironment(
    'ENV',
    defaultValue: 'development',
  );

  static const String apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  static const String _devApiUrl = 'http://127.0.0.1:8868/api/v1';
  static const String _uatApiUrl =
      'https://pos-backend-28040503481.europe-west1.run.app/api/v1';
  static const String _prodApiUrl = 'https://YOUR-PROD-BACKEND-URL.run.app/api/v1';

  static String get apiBaseUrl {
    if (apiBaseUrlOverride.isNotEmpty) return apiBaseUrlOverride;
    switch (environment.toLowerCase()) {
      case 'uat':
        return _uatApiUrl;
      case 'production':
      case 'prod':
        return _prodApiUrl;
      default:
        return _devApiUrl;
    }
  }

  static String get apiOrigin {
    final base = apiBaseUrl;
    const suffix = '/api/v1';
    if (base.endsWith(suffix)) {
      return base.substring(0, base.length - suffix.length);
    }
    return base;
  }

  static bool get isDevelopment =>
      environment == 'development' || environment == 'dev';
}
