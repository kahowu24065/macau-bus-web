import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted accessibility mode. Off unless the user turns it on.
class ElderlyModeController extends ChangeNotifier {
  static const prefKey = 'elderly_mode';

  bool enabled = false;
  bool _userSet = false;
  late final Future<void> ready;

  ElderlyModeController() {
    ready = _load();
  }

  /// Does not read preferences. For tests and previews.
  ElderlyModeController.fixed(this.enabled) {
    ready = Future<void>.value();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_userSet) return;
    enabled = prefs.getBool(prefKey) ?? false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _userSet = true;
    if (enabled == value) return;
    enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, value);
  }
}
