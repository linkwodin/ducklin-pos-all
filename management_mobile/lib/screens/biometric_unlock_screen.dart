import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../services/biometric_service.dart';
import '../utils/user_avatar.dart';

class BiometricUnlockScreen extends StatefulWidget {
  const BiometricUnlockScreen({super.key});

  @override
  State<BiometricUnlockScreen> createState() => _BiometricUnlockScreenState();
}

class _BiometricUnlockScreenState extends State<BiometricUnlockScreen> {
  var _label = 'Face ID / Touch ID';
  var _attempting = false;

  @override
  void initState() {
    super.initState();
    _loadLabel();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _loadLabel() async {
    final label = await BiometricService.instance.biometricLabel();
    if (mounted) setState(() => _label = label);
  }

  Future<void> _unlock() async {
    if (_attempting) return;
    setState(() => _attempting = true);
    final l10n = AppLocalizations.of(context)!;
    final ok = await context.read<AuthProvider>().unlockWithBiometric(reason: l10n.biometricUnlockReason);
    if (!mounted) return;
    setState(() => _attempting = false);
    if (!ok) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.biometricFailed(_label))),
      );
    }
  }

  Future<void> _usePassword() async {
    await context.read<AuthProvider>().logout(disableBiometric: false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final name = user?.displayName ?? '';
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: user != null
                        ? UserAvatar(
                            key: ValueKey('unlock-avatar-${user.id}'),
                            user: user,
                            radius: 36,
                          )
                        : const UserAvatar(
                            user: AppUser(id: 0, username: '', role: '', firstName: '', lastName: ''),
                            radius: 36,
                          ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.unlockWithBiometric(_label),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (name.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _attempting ? null : _unlock,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: _attempting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.lock_open),
                    label: Text(_attempting ? l10n.checking : l10n.unlock),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _usePassword,
                    child: Text(l10n.usePasswordInstead),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
