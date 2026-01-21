import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/language_provider.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final currentLocale = languageProvider.locale;

    return PopupMenuButton<Locale>(
      icon: const Icon(Icons.language),
      tooltip: 'Change Language',
      onSelected: (Locale locale) {
        languageProvider.setLanguage(locale);
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem<Locale>(
          value: const Locale('en'),
          child: Row(
            children: [
              const Text('English'),
              if (currentLocale.languageCode == 'en')
                const Icon(Icons.check, size: 20, color: Colors.blue),
            ],
          ),
        ),
        PopupMenuItem<Locale>(
          value: const Locale('zh', 'TW'),
          child: Row(
            children: [
              const Text('繁體中文'),
              if (currentLocale.languageCode == 'zh' && currentLocale.countryCode == 'TW')
                const Icon(Icons.check, size: 20, color: Colors.blue),
            ],
          ),
        ),
        PopupMenuItem<Locale>(
          value: const Locale('zh', 'CN'),
          child: Row(
            children: [
              const Text('简体中文'),
              if (currentLocale.languageCode == 'zh' && currentLocale.countryCode == 'CN')
                const Icon(Icons.check, size: 20, color: Colors.blue),
            ],
          ),
        ),
      ],
    );
  }
}

