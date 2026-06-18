import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';

Future<void> showLanguagePicker(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final localeProvider = context.read<LocaleProvider>();
  final current = localeProvider.localeOverride;

  String selected;
  if (current == null) {
    selected = 'system';
  } else if (current.languageCode == 'zh' && current.countryCode == 'TW') {
    selected = 'zh_TW';
  } else if (current.languageCode == 'zh') {
    selected = 'zh';
  } else {
    selected = 'en';
  }

  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.language, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          ListTile(
            leading: Icon(selected == 'system' ? Icons.check : Icons.phone_android),
            title: Text(l10n.languageSystem),
            onTap: () => Navigator.pop(ctx, 'system'),
          ),
          ListTile(
            leading: Icon(selected == 'en' ? Icons.check : Icons.language),
            title: Text(l10n.languageEnglish),
            onTap: () => Navigator.pop(ctx, 'en'),
          ),
          ListTile(
            leading: Icon(selected == 'zh_TW' ? Icons.check : Icons.language),
            title: Text(l10n.languageChineseTraditional),
            onTap: () => Navigator.pop(ctx, 'zh_TW'),
          ),
          ListTile(
            leading: Icon(selected == 'zh' ? Icons.check : Icons.language),
            title: Text(l10n.languageChineseSimplified),
            onTap: () => Navigator.pop(ctx, 'zh'),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || choice == null || choice == selected) return;
  switch (choice) {
    case 'system':
      await localeProvider.setLocale(null);
    case 'en':
      await localeProvider.setLocale(const Locale('en'));
    case 'zh_TW':
      await localeProvider.setLocale(const Locale('zh', 'TW'));
    case 'zh':
      await localeProvider.setLocale(const Locale('zh'));
  }
}

class LanguageIconButton extends StatelessWidget {
  const LanguageIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppLocalizations.of(context)!.language,
      icon: const Icon(Icons.language),
      onPressed: () => showLanguagePicker(context),
    );
  }
}
