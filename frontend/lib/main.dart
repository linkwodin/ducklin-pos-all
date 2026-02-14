import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/product_provider.dart';
import 'providers/order_provider.dart';
import 'providers/language_provider.dart';
import 'providers/stock_provider.dart';
import 'providers/sync_status_provider.dart';
import 'providers/notification_bar_provider.dart';
import 'providers/stocktake_flow_provider.dart';
import 'providers/stocktake_status_provider.dart';
import 'services/api_service.dart';
import 'services/database_service.dart';
import 'services/api_logger.dart';
import 'screens/login_screen.dart';
import 'widgets/notification_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  await ApiService.instance.initialize();
  await DatabaseService.instance.initDatabase();
  await ApiLogger.instance.initialize();

  runApp(const POSApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class POSApp extends StatelessWidget {
  const POSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => StockProvider()),
        ChangeNotifierProvider(create: (_) => SyncStatusProvider()),
        ChangeNotifierProvider(create: (_) => NotificationBarProvider()),
        ChangeNotifierProvider(create: (_) => StocktakeFlowProvider()),
        ChangeNotifierProvider(create: (_) => StocktakeStatusProvider()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, _) {
          return Column(
            children: [
              Expanded(
                child: MaterialApp(
                  navigatorKey: navigatorKey,
                  title: '德靈海味 POS',
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
                    useMaterial3: true,
                  ),
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  locale: languageProvider.locale,
                  home: const LoginScreen(),
                ),
              ),
              Theme(
                data: ThemeData(
                  colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
                  useMaterial3: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: NotificationBar(navigatorKey: navigatorKey),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
