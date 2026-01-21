import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import 'pos_screen.dart';

class UsernameLoginScreen extends StatefulWidget {
  const UsernameLoginScreen({super.key});

  @override
  State<UsernameLoginScreen> createState() => _UsernameLoginScreenState();
}

class _UsernameLoginScreenState extends State<UsernameLoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String _error = '';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final l10n = AppLocalizations.of(context)!;
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _error = '${l10n.username} ${l10n.password}');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      print('UsernameLoginScreen: Starting login process...');
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.login(
        _usernameController.text,
        _passwordController.text,
      );

      print('UsernameLoginScreen: Login result: $success');

      if (success && mounted) {
        print('UsernameLoginScreen: Login successful, navigating to POS screen');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const POSScreen()),
        );
      } else {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _error = l10n.invalidPIN;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('UsernameLoginScreen: Login exception: $e');
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _error = '${l10n.loginFailed}: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.signIn),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.blue),
              const SizedBox(height: 32),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: l10n.username,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: l10n.password,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _error,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : Text(l10n.signIn),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

