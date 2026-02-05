import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'user_profile_screen.dart';
import 'printer_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showLogoutDialog(BuildContext context, AppLocalizations l10n, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.logout),
          content: Text(l10n.areYouSureLogout),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () async {
                // Close the dialog first
                Navigator.of(context).pop();

                // Perform logout (clears token, user, prefs)
                await authProvider.logout();

                // Navigate back to login screen and clear navigation stack
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              child: Text(l10n.logout),
            ),
          ],
        );
      },
    );
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

