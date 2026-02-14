import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider with ChangeNotifier {
  static const String _languageKey = 'selected_language';
  static const String _countryKey = 'selected_country';
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  LanguageProvider() {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString(_languageKey);
    if (languageCode != null) {
      final countryCode = prefs.getString(_countryKey);
      _locale = countryCode != null && countryCode.isNotEmpty
          ? Locale(languageCode, countryCode)
          : Locale(languageCode);
      notifyListeners();
    }
  }

  Future<void> setLanguage(Locale locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, locale.languageCode);
    await prefs.setString(_countryKey, locale.countryCode ?? '');
    notifyListeners();
  }

  List<Locale> get supportedLocales => const [
        Locale('en'),
        Locale('zh'), // Base Chinese locale (fallback)
        Locale('zh', 'TW'),
        Locale('zh', 'CN'),
      ];
}

