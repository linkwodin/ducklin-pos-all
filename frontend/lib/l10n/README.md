# Translations (l10n)

## Why do my translations roll back when I run `flutter run`?

Flutter’s localization **code generator** reads the **`.arb` files** and (re)generates the Dart files (`app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart`, etc.) on every build.

With `generate: true` in `pubspec.yaml`, every `flutter run` **overwrites** those Dart files with whatever is in the `.arb` files. So **edits made only in the Dart files are lost** on the next run (“rollback”). The macOS (and other) builds also require `generate: true` to run.

## How to avoid rollback

**Edit only the `.arb` files** for translation text:

- `app_en.arb`
- `app_zh_CN.arb`
- `app_zh_TW.arb`

Then run the app or `flutter gen-l10n`. The generated Dart files will reflect your ARB content, and you won’t lose changes. Do not edit the generated `app_localizations_*.dart` files for translation strings—those are overwritten from the ARB files.
