import 'package:flutter/material.dart';
import 'package:pos_system/l10n/app_localizations.dart';

/// Full-screen route for entering stocktake skip reason so the text field
/// reliably receives focus (no competition from barcode/scan fields).
class StocktakeSkipReasonScreen extends StatefulWidget {
  const StocktakeSkipReasonScreen({
    super.key,
    required this.hintText,
  });

  final String hintText;

  /// Pushes this screen and returns the reason string, or null if cancelled.
  static Future<String?> push(BuildContext context, String hintText) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => StocktakeSkipReasonScreen(hintText: hintText),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<StocktakeSkipReasonScreen> createState() => _StocktakeSkipReasonScreenState();
}

class _StocktakeSkipReasonScreenState extends State<StocktakeSkipReasonScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Delay focus so we win over any focus the previous route or framework assigns
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _focusNode.canRequestFocus) {
          _focusNode.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final r = _controller.text.trim();
    if (r.isEmpty) return;
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.stocktakeSkip),
        leading: Focus(
          skipTraversal: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: l10n.cancel,
          ),
        ),
      ),
      body: FocusScope(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                onSubmitted: (_) => _submit(),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _submit,
                  child: Text(l10n.ok),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }
}
