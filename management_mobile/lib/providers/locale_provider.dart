import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localeKey = 'management_mobile_locale';

class LocaleProvider with ChangeNotifier {
  Locale? _override;

  Locale? get localeOverride => _override;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    if (code == null || code.isEmpty || code == 'system') {
      _override = null;
    } else if (code == 'zh_TW') {
      _override = const Locale('zh', 'TW');
    } else if (code == 'zh') {
      _override = const Locale('zh');
    } else {
      _override = const Locale('en');
    }
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _override = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.setString(_localeKey, 'system');
    } else if (locale.languageCode == 'zh' && locale.countryCode == 'TW') {
      await prefs.setString(_localeKey, 'zh_TW');
    } else {
      await prefs.setString(_localeKey, locale.languageCode);
    }
  }
}
