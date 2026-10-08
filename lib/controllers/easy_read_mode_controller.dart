import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted accessibility mode. Off unless the user turns it on.
///
/// Arrival read-aloud is stored separately for each mode. Normal mode
/// defaults to off. Easy Read defaults to on. A mode keeps that default
/// until the user changes the switch while that mode is active.
class EasyReadModeController extends ChangeNotifier {
  static const prefKey = 'easy_read_mode';
  static const speakArrivalsNormalPrefKey = 'easy_read_speak_arrivals_normal';
  static const speakArrivalsEasyPrefKey = 'easy_read_speak_arrivals_easy';

  bool enabled = false;
  bool? _speakNormal;
  bool? _speakEasy;
  bool _enabledSet = false;
  bool _speakNormalSet = false;
  bool _speakEasySet = false;
  late final Future<void> ready;

  EasyReadModeController() {
    ready = _load();
  }

  /// Does not read preferences. For tests and previews.
  /// [speakArrivals] is an explicit choice for the mode given by [enabled].
  EasyReadModeController.fixed(this.enabled, {bool? speakArrivals}) {
    if (speakArrivals != null) {
      if (enabled) {
        _speakEasy = speakArrivals;
      } else {
        _speakNormal = speakArrivals;
      }
    }
    ready = Future<void>.value();
  }

  /// Read-aloud for the mode that is active now.
  bool get speakArrivals => enabled ? (_speakEasy ?? true) : (_speakNormal ?? false);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_enabledSet) enabled = prefs.getBool(prefKey) ?? false;
    if (!_speakNormalSet && prefs.containsKey(speakArrivalsNormalPrefKey)) {
      _speakNormal = prefs.getBool(speakArrivalsNormalPrefKey);
    }
    if (!_speakEasySet && prefs.containsKey(speakArrivalsEasyPrefKey)) {
      _speakEasy = prefs.getBool(speakArrivalsEasyPrefKey);
    }
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
    final key = enabled ? speakArrivalsEasyPrefKey : speakArrivalsNormalPrefKey;
    if (enabled) {
      _speakEasySet = true;
      if (_speakEasy == value) return;
      _speakEasy = value;
    } else {
      _speakNormalSet = true;
      if (_speakNormal == value) return;
      _speakNormal = value;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
