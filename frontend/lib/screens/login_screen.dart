import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import 'user_selection_screen.dart';
import 'pin_login_screen.dart';
import 'username_login_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  bool _isSyncing = false;
  List<Map<String, dynamic>> _users = [];
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _syncMessage = null;
    });
    try {
      final users = await DatabaseService.instance.getUsers();
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _syncUsers() async {
    setState(() {
      _isSyncing = true;
      _syncMessage = null;
    });

    try {
      final deviceCode = ApiService.instance.deviceCode;
      final l10n = AppLocalizations.of(context)!;
      if (deviceCode == null) {
        setState(() {
          _syncMessage = l10n.deviceCodeNotAvailable;
          _isSyncing = false;
        });
        return;
      }

      // Fetch users from API
      final users = await ApiService.instance.getUsersForDevice(deviceCode);

      // Save to local database
      if (users.isNotEmpty) {
        await DatabaseService.instance.saveUsers(
          users.cast<Map<String, dynamic>>(),
        );
        setState(() {
          _syncMessage = l10n.syncedUsers(users.length);
        });
      } else {
        setState(() {
          _syncMessage = l10n.noUsersFoundForDevice;
        });
      }

      // Reload users from database
      await _loadUsers();
      
      // Force refresh of user selection screen if it's displayed
      setState(() {
        // This will trigger a rebuild of UserSelectionScreen with updated users
      });
    } catch (e) {
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _syncMessage = l10n.syncFailed(e.toString());
      });
    } finally {
      setState(() {
        _isSyncing = false;
      });

      // Clear message after 3 seconds
      if (mounted && _syncMessage != null) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _syncMessage = null;
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.loginTitle),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Sync message
            if (_syncMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: _syncMessage!.contains('failed') || _syncMessage!.contains('not available')
                    ? Colors.red[100]
                    : Colors.green[100],
                child: Text(
                  _syncMessage!,
                  style: TextStyle(
                    color: _syncMessage!.contains('failed') || _syncMessage!.contains('not available')
                        ? Colors.red[900]
                        : Colors.green[900],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            // Main content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _users.isEmpty
                      ? _buildNoUsersView()
                      : UserSelectionScreen(
                          users: _users,
                          onSyncRequested: _syncUsers,
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoUsersView() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l10n.noUsersAvailable,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.pleaseSyncWithServerFirst,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _isSyncing ? null : _syncUsers,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(_isSyncing ? l10n.syncing : l10n.syncUsers),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UsernameLoginScreen()),
                );
              },
              child: Text(l10n.loginWithUsernamePassword),
            ),
          ],
        ),
      ),
    );
  }
}

