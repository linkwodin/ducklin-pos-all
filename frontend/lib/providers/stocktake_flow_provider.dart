import 'package:flutter/foundation.dart';

/// Gates barcode scan focus until the stocktake (day start) flow has finished.
/// This prevents barcode fields from stealing focus during the day start dialog
/// or skip-reason screen. POS sets [allowBarcodeFocus] true when:
/// - No day start prompt was needed, or
/// - User finished day start stocktake screen (pushed and popped), or
/// - User skipped day start with reason.
class StocktakeFlowProvider extends ChangeNotifier {
  bool _allowBarcodeFocus = false;

  bool get allowBarcodeFocus => _allowBarcodeFocus;

  void setAllowBarcodeFocus(bool value) {
    if (_allowBarcodeFocus == value) return;
    _allowBarcodeFocus = value;
    notifyListeners();
  }
}
