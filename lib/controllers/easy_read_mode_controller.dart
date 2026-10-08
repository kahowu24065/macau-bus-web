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
  static const speechLanguagePrefKey = 'speech_language';

  /// Cantonese, Mandarin, English, Portuguese. Stored values match app language codes.
  static const speechLanguageChoices = ['zh', 'zhHans', 'en', 'pt'];

  bool enabled = false;
  bool? _speakNormal;
  bool? _speakEasy;
  String? _speechLanguage;
  bool _enabledSet = false;
  bool _speakNormalSet = false;
  bool _speakEasySet = false;
  bool _speechLanguageSet = false;
  late final Future<void> ready;

  EasyReadModeController() {
    ready = _load();
  }

  /// Does not read preferences. For tests and previews.
  /// [speakArrivals] is an explicit choice for the mode given by [enabled].
  /// [speechLanguage] is an explicit readout language. Null follows the app language.
  EasyReadModeController.fixed(this.enabled, {bool? speakArrivals, String? speechLanguage}) {
    if (speakArrivals != null) {
      if (enabled) {
        _speakEasy = speakArrivals;
      } else {
        _speakNormal = speakArrivals;
      }
    }
    if (speechLanguage != null && speechLanguageChoices.contains(speechLanguage)) {
      _speechLanguage = speechLanguage;
      _speechLanguageSet = true;
    }
    ready = Future<void>.value();
  }

  /// Read-aloud language. Follows [appLanguage] until the user picks one.
  String speechLanguageFor(String appLanguage) {
    return _speechLanguage ?? defaultSpeechLanguage(appLanguage);
  }

  static String defaultSpeechLanguage(String appLanguage) {
    switch (appLanguage) {
      case 'zhHans':
      case 'en':
      case 'pt':
        return appLanguage;
      default:
        return 'zh';
    }
  }

  static String speechLanguageLabelKey(String code) {
    switch (code) {
      case 'zhHans':
        return 'speech_lang_cmn';
      case 'en':
        return 'speech_lang_en';
      case 'pt':
        return 'speech_lang_pt';
      default:
        return 'speech_lang_yue';
    }
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
    if (!_speechLanguageSet && prefs.containsKey(speechLanguagePrefKey)) {
      final stored = prefs.getString(speechLanguagePrefKey);
      if (stored != null && speechLanguageChoices.contains(stored)) {
        _speechLanguage = stored;
      }
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

  Future<void> setSpeechLanguage(String value) async {
    if (!speechLanguageChoices.contains(value)) return;
    _speechLanguageSet = true;
    if (_speechLanguage == value) return;
    _speechLanguage = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(speechLanguagePrefKey, value);
  }
}
