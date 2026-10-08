import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted accessibility mode. Off unless the user turns it on.
/// Arrival read-aloud defaults to on.
class EasyReadModeController extends ChangeNotifier {
  static const prefKey = 'easy_read_mode';
  static const speakArrivalsPrefKey = 'easy_read_speak_arrivals';

  bool enabled = false;
  bool speakArrivals = true;
  bool _enabledSet = false;
  bool _speakSet = false;
  late final Future<void> ready;

  EasyReadModeController() {
    ready = _load();
  }

  /// Does not read preferences. For tests and previews.
  EasyReadModeController.fixed(this.enabled, {this.speakArrivals = true}) {
    ready = Future<void>.value();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_enabledSet) enabled = prefs.getBool(prefKey) ?? false;
    if (!_speakSet) speakArrivals = prefs.getBool(speakArrivalsPrefKey) ?? true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabledSet = true;
    if (enabled == value) return;
    enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, value);
  }

  Future<void> setSpeakArrivals(bool value) async {
    _speakSet = true;
    if (speakArrivals == value) return;
    speakArrivals = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(speakArrivalsPrefKey, value);
  }
}
