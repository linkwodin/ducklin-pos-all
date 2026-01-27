import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/product_provider.dart';
import 'providers/stock_provider.dart';
import 'providers/order_provider.dart';
import 'providers/language_provider.dart';
import 'screens/login_screen.dart';
import 'screens/pos_screen.dart';
import 'services/database_service.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('Main: Initializing database...');
  // Initialize database
  await DatabaseService.instance.initDatabase();
  print('Main: Database initialized');
  
  print('Main: Initializing API service...');
  // Initialize API service
  try {
    await ApiService.instance.initialize();
    print('Main: API service initialized successfully');
    
    // Sync users from backend
    print('Main: Syncing users from backend...');
    await _syncUsers();
    print('Main: User sync completed');
    
    // Sync products from backend
    print('Main: Syncing products from backend...');
    await _syncProducts();
    print('Main: Product sync completed');
  } catch (e) {
    print('Main: Error initializing API service: $e');
  }
  
  runApp(const POSApp());
}

Future<void> _syncUsers() async {
  try {
    final deviceCode = ApiService.instance.deviceCode;
    if (deviceCode == null) {
      print('Main: Device code not available, skipping user sync');
      return;
    }
    
    print('Main: Fetching users for device: $deviceCode');
    // Fetch users from API
    final users = await ApiService.instance.getUsersForDevice(deviceCode);
    print('Main: Received ${users.length} users from API');
    
    // Save to local database
    if (users.isNotEmpty) {
      await DatabaseService.instance.saveUsers(
        users.cast<Map<String, dynamic>>(),
      );
      print('Main: Users saved to local database');
    } else {
      print('Main: No users received from API');
    }
  } catch (e) {
    // Log error but don't fail app initialization
    print('Main: Error syncing users (non-fatal): $e');
    print('Main: App will continue with locally stored users');
  }
}

Future<void> _syncProducts() async {
  try {
    final deviceCode = ApiService.instance.deviceCode;
    if (deviceCode == null) {
      print('Main: Device code not available, skipping product sync');
      return;
    }
    
    print('Main: Fetching products for device: $deviceCode');
    // Fetch products from API
    final products = await ApiService.instance.getProductsForDevice(deviceCode);
    print('Main: Received ${products.length} products from API');
    
    // Save to local database
    if (products.isNotEmpty) {
      await DatabaseService.instance.saveProducts(
        products.cast<Map<String, dynamic>>(),
      );
      print('Main: Products saved to local database');
    } else {
      print('Main: No products received from API');
    }
  } catch (e) {
    // Log error but don't fail app initialization
    print('Main: Error syncing products (non-fatal): $e');
    print('Main: App will continue with locally stored products');
  }
}

class POSApp extends StatelessWidget {
  const POSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => StockProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, child) {
          return MaterialApp(
            title: 'POS System',
            theme: ThemeData(
              primarySwatch: Colors.blue,
              useMaterial3: true,
            ),
            locale: languageProvider.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: languageProvider.supportedLocales,
            home: const AuthWrapper(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    setState(() {
      _isAuthenticated = token != null && token.isNotEmpty;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Restore auth state in AuthProvider when building
    if (_isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.checkAuth();
        
        // Listen for logout events
        authProvider.addListener(() {
          if (!authProvider.isAuthenticated && mounted) {
            setState(() {
              _isAuthenticated = false;
            });
          }
        });
      });
    }

    return _isAuthenticated ? const POSScreen() : const LoginScreen();
  }
  
  @override
  void dispose() {
    // Clean up any timers if needed
    super.dispose();
  }
}

