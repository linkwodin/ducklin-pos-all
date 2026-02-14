import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/stocktake_status_provider.dart';
import '../widgets/numeric_keypad.dart';
import '../widgets/pin_display.dart';
import 'pos_screen.dart';

class PINLoginScreen extends StatefulWidget {
  final int userId;
  final String username;
  final String userName;
  final Widget userAvatar;

  const PINLoginScreen({
    super.key,
    required this.userId,
    required this.username,
    required this.userName,
    required this.userAvatar,
  });

  @override
  State<PINLoginScreen> createState() => _PINLoginScreenState();
}

class _PINLoginScreenState extends State<PINLoginScreen> {
  String _pin = '';
  bool _isLoading = false;
  String _error = '';
  final int _maxPinLength = 6;
  final FocusNode _pinFocusNode = FocusNode();
  final TextEditingController _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pinController.addListener(_onPinChanged);
    // Auto-focus the hidden text field to enable keyboard input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.removeListener(_onPinChanged);
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _onPinChanged() {
    final newPin = _pinController.text;
    if (newPin != _pin) {
      setState(() {
        _pin = newPin;
        _error = '';
      });

      // Auto-submit when PIN reaches maximum length
      if (_pin.length == _maxPinLength) {
        // Small delay to show the last digit
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _login();
          }
        });
      }
    }
  }

  void _onNumberTap(String number) {
    if (_pin.length < _maxPinLength) {
      _pinController.text = _pin + number;
      // Focus will be maintained for keyboard input
      _pinFocusNode.requestFocus();
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) {
      _pinController.text = _pin.substring(0, _pin.length - 1);
      _pinFocusNode.requestFocus();
    }
  }

  void _onClear() {
    _pinController.clear();
    _pinFocusNode.requestFocus();
  }

  Future<void> _login() async {
    final l10n = AppLocalizations.of(context)!;
    if (_pin.length != _maxPinLength) {
      // Only submit when exactly 6 digits
      setState(() => _error = l10n.pinMustBeDigits(_maxPinLength));
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.pinLogin(widget.username, _pin);

      if (success && mounted) {
        Provider.of<StocktakeStatusProvider>(context, listen: false)
            .setPendingFromLastStocktakeAt(authProvider.lastLoginResponse?['last_stocktake_at']);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const POSScreen()),
        );
      } else {
        setState(() {
          _error = l10n.invalidPIN;
          _isLoading = false;
          _pin = ''; // Clear PIN on error
          _pinController.clear();
        });
      }
    } catch (e) {
      setState(() {
        _error = '${l10n.loginFailed}: $e';
        _isLoading = false;
        _pin = ''; // Clear PIN on error
        _pinController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
      final l10n = AppLocalizations.of(context)!;
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.enterPIN),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _isLoading ? null : () => Navigator.pop(context),
          ),
        ),
      body: SafeArea(
        child: Column(
          children: [
            // User info section - minimal space
            Flexible(
              flex: 1,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      widget.userAvatar,
                      const SizedBox(height: 8),
                      Text(
                        widget.userName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // PIN Display
                      PINDisplay(
                        length: _maxPinLength,
                        enteredLength: _pin.length,
                        obscureText: true,
                      ),
                      // Hidden text field for keyboard input
                      Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _pinController,
                          focusNode: _pinFocusNode,
                          keyboardType: TextInputType.number,
                          maxLength: _maxPinLength,
                          textAlign: TextAlign.center,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onSubmitted: (_) {
                            if (_pin.length == _maxPinLength) {
                              _login();
                            }
                          },
                          style: const TextStyle(fontSize: 1),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                          ),
                        ),
                      ),
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_isLoading) ...[
                        const SizedBox(height: 8),
                        const CircularProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Numeric Keypad - takes remaining space
            Flexible(
              flex: 2,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                        maxHeight: double.infinity,
                      ),
                      child: NumericKeypad(
                        onNumberTap: _isLoading ? (_) {} : _onNumberTap,
                        onBackspace: _isLoading ? () {} : _onBackspace,
                        onClear: _isLoading ? null : _onClear,
                        showClearButton: true,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

