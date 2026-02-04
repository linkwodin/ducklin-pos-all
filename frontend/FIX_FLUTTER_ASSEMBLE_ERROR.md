# Fixing flutter_assemble.rule Error

If you're getting:
```
C:\...\frontend\CmakeFile\..\flutter_assemble.rule' exited with code 1.
```

This means the Flutter native asset compilation is failing. Here's how to fix it:

## Solution 1: Clean and Rebuild (Most Common Fix)

```cmd
cd frontend
flutter clean
flutter pub get
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

## Solution 2: Get Detailed Error Information

Run with verbose output to see the actual error:

```cmd
flutter build windows --release --verbose --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

This will show the exact command that failed and why.

## Solution 3: Check for Native Dependencies Issues

The error might be caused by packages that require native compilation. Check your `pubspec.yaml` for packages like:
- `sqflite_common_ffi` - requires native SQLite
- `mobile_scanner` - may have native dependencies
- Other FFI packages

Try building without native assets first to isolate the issue:

```cmd
flutter build windows --release --no-tree-shake-icons --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

## Solution 4: Update Flutter and Dependencies

```cmd
flutter upgrade
cd frontend
flutter pub upgrade
flutter pub get
flutter clean
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

## Solution 5: Check Windows Build Requirements

Make sure you have:
1. **Visual Studio 2022** with C++ tools installed
2. **Windows 10/11 SDK** installed
3. **CMake** available (even if only in Developer Command Prompt)

Verify with:
```cmd
flutter doctor -v
```

## Solution 6: Check for Path Issues

Long paths or spaces in paths can cause issues. Make sure:
- Your project path doesn't have spaces (or use short paths)
- Path length is reasonable (Windows has 260 char limit)

## Solution 7: Check Build Logs

Look for more detailed error messages in:
- `frontend\build\windows\CMakeFiles\CMakeError.log`
- `frontend\build\windows\CMakeFiles\CMakeOutput.log`

These files contain detailed error information.

## Solution 8: Try Debug Build First

Sometimes release builds have different issues. Try debug first:

```cmd
flutter build windows --debug --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

If debug works, the issue is specific to release configuration.

## Solution 9: Check for Package-Specific Issues

If you're using `sqflite_common_ffi`, make sure it's properly configured for Windows:

```yaml
# In pubspec.yaml, you might need:
dependency_overrides:
  sqflite_common_ffi: ^2.3.0
```

## Solution 10: Recreate Windows Platform Files

If the Windows platform was recently added, try recreating it:

```cmd
cd frontend
# Backup any customizations first
# Then recreate:
flutter create --platforms=windows .
flutter pub get
flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
```

## Common Causes

1. **Missing build tools** - Visual Studio C++ tools not fully installed
2. **Outdated Flutter** - Flutter version too old for Windows desktop
3. **Package incompatibility** - Some packages don't support Windows
4. **Path issues** - Long paths or special characters
5. **Corrupted build cache** - Old build artifacts causing conflicts

## Get Help

If none of these work, share:
1. Full error output from `flutter build windows --verbose`
2. Output of `flutter doctor -v`
3. Your `pubspec.yaml` file
4. The specific package that's failing (if visible in verbose output)

