# Enabling Windows Desktop Support

If you get the error "No windows desktop project configured", you need to enable Windows desktop support in your Flutter project.

## Steps to Enable Windows Support

1. **Make sure you're on a Windows machine** (Windows desktop support can only be enabled on Windows)

2. **Navigate to the frontend directory:**
   ```cmd
   cd frontend
   ```

3. **Enable Windows desktop support:**
   ```cmd
   flutter create --platforms=windows .
   ```
   
   This command will:
   - Create the `windows/` folder with all necessary Windows platform files
   - Add Windows-specific configuration files
   - Set up the Windows build system

4. **Verify Windows support is enabled:**
   ```cmd
   flutter doctor
   ```
   
   You should see Windows listed under available platforms.

5. **Now you can build for Windows:**
   ```cmd
   flutter build windows --release --dart-define=ENV=uat --dart-define=API_BASE_URL="https://pos-backend-28040503481.europe-west1.run.app/api/v1"
   ```

## Alternative: Create Windows Support Manually

If the `flutter create` command doesn't work, you can also try:

```cmd
flutter config --enable-windows-desktop
flutter create --platforms=windows .
```

## Note

- Windows desktop support can only be enabled on a Windows machine
- You need Flutter SDK installed on Windows
- Make sure you have Visual Studio with C++ development tools installed (required for Windows builds)

