import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import '../utils/role_labels.dart';
import '../utils/user_avatar.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  var _biometricAvailable = false;
  var _biometricEnabled = false;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final available = await BiometricService.instance.isBiometricAvailable();
    final enabled = await ApiService.instance.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final l10n = AppLocalizations.of(context)!;
      final verified = await BiometricService.instance.authenticate(
        reason: l10n.biometricEnableReason,
      );
      if (!verified) return;
    }
    await ApiService.instance.setBiometricEnabled(value);
    if (!mounted) return;
    setState(() => _biometricEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.more)),
      body: ListView(
        children: [
          if (user != null)
            ListTile(
              leading: UserAvatar.fromUser(user, radius: 22),
              title: Text(user.displayName),
              subtitle: Text('${roleLabel(AppLocalizations.of(context)!, user.role)} · ${user.username}'),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(l10n.apiServer),
            subtitle: Text(ApiService.instance.apiBaseUrl),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(l10n.environment),
            subtitle: Text(AppConfig.environment),
          ),
          if (!_loading && _biometricAvailable)
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: Text(l10n.biometricUnlock),
              subtitle: Text(l10n.biometricUnlockSubtitle),
              value: _biometricEnabled,
              onChanged: _toggleBiometric,
            ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text(l10n.logout, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.logoutConfirm),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.logout)),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await auth.logout(disableBiometric: false);
              }
            },
          ),
        ],
      ),
    );
  }
}
