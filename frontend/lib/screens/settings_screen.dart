import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_bar_provider.dart';
import '../providers/order_provider.dart';
import '../providers/stocktake_status_provider.dart';
import '../providers/sync_status_provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/stocktake_prompt_service.dart';
import 'stocktake_flow_screen.dart';
import 'stocktake_skip_reason_screen.dart';
import 'login_screen.dart';
import 'user_profile_screen.dart';
import 'printer_settings_screen.dart';
import 'sync_screen.dart';
import 'device_config_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showLogoutDialog(BuildContext context, AppLocalizations l10n, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l10n.logout),
          content: Text(l10n.areYouSureLogout),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final should = await StocktakePromptService.shouldPromptDayEnd();
                if (!context.mounted) return;
                if (should) {
                  _showDayEndStocktakeDialogThenLogout(context, l10n, authProvider);
                } else {
                  _performLogout(context, authProvider);
                }
              },
              child: Text(l10n.logout),
            ),
          ],
        );
      },
    );
  }

  void _performLogout(BuildContext context, AuthProvider authProvider) async {
    final notificationProvider = Provider.of<NotificationBarProvider>(context, listen: false);
    int? storeId;
    try {
      storeId = Provider.of<OrderProvider>(context, listen: false).storeId;
      if (storeId == null) {
        final deviceInfo = await DatabaseService.instance.getDeviceInfo();
        storeId = deviceInfo?['store_id'] as int?;
      }
    } catch (_) {}
    await authProvider.logout(storeId: storeId);
    notificationProvider.clear();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _showDayEndStocktakeDialogThenLogout(
    BuildContext context,
    AppLocalizations l10n,
    AuthProvider authProvider,
  ) {
    final notificationProvider = Provider.of<NotificationBarProvider>(context, listen: false);
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.stocktakeDayEndTitle),
        content: Text(l10n.stocktakeDayEndMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('skip'),
            child: Text(l10n.stocktakeSkip),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop('do');
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StocktakeFlowScreen(type: 'day_end')),
              );
            },
            child: Text(l10n.stocktakeDoIt),
          ),
        ],
      ),
    ).then((result) async {
      if (result != 'skip') return;
      if (!context.mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      final reason = await StocktakeSkipReasonScreen.push(context, l10n.stocktakeSkipReasonHint);
      if (!context.mounted) return;
      if (reason == null) {
        _showDayEndStocktakeDialogThenLogout(context, l10n, authProvider);
        return;
      }
      if (reason.isEmpty) return;
      int? storeId;
      try {
        final deviceInfo = await DatabaseService.instance.getDeviceInfo();
        storeId = deviceInfo?['store_id'] as int?;
      } catch (_) {}
      await ApiService.instance.recordStocktakeDayEndSkip(skipReason: reason, storeId: storeId);
      if (!context.mounted) return;
      final fullMessage = '${l10n.stocktakeDayEndTitle}: ${l10n.stocktakeSkippedNotificationShort}. Reason: $reason';
      notificationProvider.showPersistent(
        l10n.stocktakeSkippedNotificationShort,
        fullMessage: fullMessage,
        isError: true,
      );
      _performLogout(context, authProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile Section
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person, size: 32),
                    title: Text(
                      l10n.profile ?? 'Profile',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      'View and edit your profile information',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Clear any existing focus (e.g. hidden barcode input)
                      // so the profile/change-PIN fields can receive input.
                      FocusScope.of(context).unfocus();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const UserProfileScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                // Sync Section
                Consumer<SyncStatusProvider>(
                  builder: (context, syncStatus, _) {
                    final pending = syncStatus.pendingOrdersCount + syncStatus.pendingStocktakesCount + syncStatus.pendingUserActivityEventsCount;
                    return Card(
                      child: ListTile(
                        leading: Stack(
                          children: [
                            const Icon(Icons.sync, size: 32),
                            if (pending > 0)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    pending > 99 ? '99+' : '$pending',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          l10n.sync,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          pending > 0
                              ? '$pending pending'
                              : 'Sync orders and stocktakes with server',
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          FocusScope.of(context).unfocus();
                          final sync = Provider.of<SyncStatusProvider>(context, listen: false);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SyncScreen()),
                          );
                          if (context.mounted) await sync.refreshPendingCount();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Configure Device (admin only)
                if (authProvider.currentUser?['role'] == 'management') ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.phone_android, size: 32),
                      title: Text(
                        l10n.configureDevice,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        'Copy device ID, add or update device to a store',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const DeviceConfigScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Printer Settings Section
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.print, size: 32),
                    title: Text(
                      l10n.settings,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      'Configure printer settings',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrinterSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                // Reset stocktake reminder (e.g. after truncating backend stocktake/activity tables)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.refresh, size: 32),
                    title: const Text(
                      'Reset stocktake reminder',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      'Show day-start reminder again (e.g. after clearing server data)',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      Provider.of<StocktakeStatusProvider>(context, listen: false).setPendingFromLastStocktakeAt(null);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Stocktake reminder reset. You will be prompted for day-start stocktake again.')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                // Logout Section
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.logout,
                      size: 32,
                      color: Colors.red[600],
                    ),
                    title: Text(
                      l10n.logout,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.red[600],
                      ),
                    ),
                    subtitle: Text(
                      'Sign out of your account',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Colors.red[600],
                    ),
                    onTap: () {
                      _showLogoutDialog(context, l10n, authProvider);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

