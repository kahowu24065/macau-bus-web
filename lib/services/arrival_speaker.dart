import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Device speech. Tests can pass a fake [SpeechEngine].
abstract class SpeechEngine {
  /// Returns false when [language] is not installed.
  Future<bool> isLanguageAvailable(String language);
  Future<bool> setLanguage(String language);

  /// Installed voices. Each map has at least `name` and `locale`.
  Future<List<Map<String, String>>> getVoices();

  /// Selects one installed voice. Returns false when it cannot be applied.
  Future<bool> setVoice(Map<String, String> voice);
  Future<void> setSpeechRate(double rate);
  Future<void> speak(String text);
  Future<void> prepareIos();
}

class FlutterTtsEngine implements SpeechEngine {
  FlutterTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  var _iosReady = false;

  @override
  Future<bool> isLanguageAvailable(String language) async {
    final available = await _tts.isLanguageAvailable(language);
    return _voiceReady(available);
  }

  @override
  Future<bool> setLanguage(String language) async {
    final available = await isLanguageAvailable(language);
    if (!available) return false;
    final result = await _tts.setLanguage(language);
    return _voiceReady(result);
  }

  /// flutter_tts reports a usable voice as `true` or `1`.
  static bool _voiceReady(dynamic result) => result == true || result == 1;

  @override
  Future<List<Map<String, String>>> getVoices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          {
            for (final entry in item.entries)
              entry.key.toString(): entry.value?.toString() ?? '',
          },
    ];
  }

  @override
  Future<bool> setVoice(Map<String, String> voice) async {
    final result = await _tts.setVoice(voice);
    return _voiceReady(result);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<void> speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  Future<void> prepareIos() async {
    if (_iosReady) return;
    _iosReady = true;
    await _tts.setSharedInstance(true);
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      const [
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
      ],
      IosTextToSpeechAudioMode.voicePrompt,
    );
  }
}

class ArrivalSpeaker {
  ArrivalSpeaker({
    this.engine,
    this.isWeb,
    this.isIos,
  });

  static ArrivalSpeaker shared = ArrivalSpeaker();

  final SpeechEngine? engine;
  final bool? isWeb;
  final bool? isIos;
  Future<bool>? _tail;

  bool get _web => isWeb ?? kIsWeb;

  bool get _ios {
    final override = isIos;
    if (override != null) return override;
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Preferred voice, then installed fallbacks.
  ///
  /// Traditional Chinese is Cantonese (`zh-HK` / `yue-HK`) only. iOS `zh-TW`
  /// and `zh-CN` are Mandarin, so they are not fallbacks: a missing Cantonese
  /// voice must not speak Mei-Jia or Ting-Ting. Simplified Chinese is Mandarin
  /// and never falls back to zh-HK.
  static List<String> localesFor(String langCode) {
    switch (langCode) {
      case 'zh':
        return const ['zh-HK', 'yue-HK'];
      case 'zhHans':
        return const ['zh-CN', 'zh-Hans'];
      case 'pt':
        return const ['pt', 'pt-PT', 'pt-BR'];
      case 'en':
        return const ['en', 'en-US', 'en-GB'];
      default:
        return const ['zh-HK', 'en'];
    }
  }

  static String _normLocale(String locale) => locale.toLowerCase().replaceAll('_', '-');

  static bool _isCantoneseLocale(String locale) {
    final loc = _normLocale(locale);
    return loc == 'zh-hk' ||
        loc.startsWith('zh-hk-') ||
        loc == 'yue-hk' ||
        loc.startsWith('yue-hk-') ||
        loc == 'zh-yue' ||
        loc.startsWith('zh-yue-');
  }

  static bool _isMandarinLocale(String locale) {
    final loc = _normLocale(locale);
    return loc == 'zh-cn' || loc.startsWith('zh-cn-') || loc == 'zh-hans' || loc.startsWith('zh-hans');
  }

  static bool _isSinji(Map<String, String> voice) {
    final blob = '${voice['name'] ?? ''} ${voice['identifier'] ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-]'), '');
    return blob.contains('sinji');
  }

  /// A voice for [locale]. Cantonese prefers Sin-ji and never a zh-CN or
  /// zh-TW voice. Simplified Chinese only accepts a zh-CN voice.
  static Map<String, String>? iosVoiceFor(List<Map<String, String>> voices, String locale) {
    final want = _normLocale(locale);
    final cantonese = _isCantoneseLocale(want);
    final mandarin = _isMandarinLocale(want);
    Map<String, String>? match;
    for (final voice in voices) {
      final loc = _normLocale(voice['locale'] ?? '');
      final ident = _normLocale(voice['identifier'] ?? '');
      if (cantonese) {
        final cantoneseVoice = _isCantoneseLocale(loc) || ident.contains('zh-hk') || ident.contains('yue-hk');
        if (!cantoneseVoice || _isMandarinLocale(loc)) continue;
        if (_isSinji(voice)) return voice;
        match ??= voice;
        continue;
      }
      if (mandarin) {
        if (_isMandarinLocale(loc)) match ??= voice;
        continue;
      }
      if (loc.isEmpty) continue;
      if (loc == want || loc.startsWith('$want-')) match ??= voice;
    }
    return match;
  }

  /// Speaks [text]. Returns false when speech is unavailable.
  /// Web failures are swallowed so the rest of the app keeps working.
  ///
  /// Calls are queued so one utterance finishes applying its language before
  /// the next one starts, and the chosen language is awaited again immediately
  /// before [SpeechEngine.speak].
  Future<bool> speak(String text, String langCode) {
    final previous = _tail;
    final Future<bool> done;
    if (previous == null) {
      done = _speakNow(text, langCode);
    } else {
      done = previous.then((_) => _speakNow(text, langCode), onError: (Object _, StackTrace _) {
        return _speakNow(text, langCode);
      });
    }
    _tail = done;
    return done;
  }

  Future<bool> _speakNow(String text, String langCode) async {
    final spoken = text.trim();
    if (spoken.isEmpty) return false;
    try {
      final speech = engine ?? FlutterTtsEngine();
      if (_ios) {
        try {
          await speech.prepareIos();
        } catch (_) {
          // Speech can still work without the playback category.
        }
      }
      await speech.setSpeechRate(0.42);
      final chosen = await _firstAvailable(speech, localesFor(langCode));
      if (chosen == null) return false;

      final applied = await _applyLanguage(speech, langCode, chosen);
      if (applied == null) return false;

      if (_ios) {
        await _applyIosVoice(speech, applied);
      }
      await speech.speak(spoken);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _firstAvailable(SpeechEngine speech, List<String> locales) async {
    for (final locale in locales) {
      try {
        if (await speech.isLanguageAvailable(locale)) return locale;
      } catch (_) {
        // Web and device failures stay in this search so the page keeps working.
        if (!_web) continue;
      }
    }
    return null;
  }

  /// Applies the locale after the fallback search, awaited immediately before
  /// the voice is selected and before [SpeechEngine.speak].
  ///
  /// Traditional Chinese always awaits `zh-HK` first so a Mandarin voice left
  /// by an earlier speak cannot stick. Simplified Chinese always awaits
  /// `zh-CN` first so a Cantonese voice cannot stick.
  Future<String?> _applyLanguage(SpeechEngine speech, String langCode, String chosen) async {
    if (langCode == 'zh') {
      if (await _setLanguage(speech, 'zh-HK')) return 'zh-HK';
      if (chosen != 'zh-HK' && _isCantoneseLocale(chosen) && await _setLanguage(speech, chosen)) {
        return chosen;
      }
      return null;
    }
    if (langCode == 'zhHans') {
      if (await _setLanguage(speech, 'zh-CN')) return 'zh-CN';
      if (chosen != 'zh-CN' && _isMandarinLocale(chosen) && await _setLanguage(speech, chosen)) {
        return chosen;
      }
      return null;
    }
    if (await _setLanguage(speech, chosen)) return chosen;
    return null;
  }

  Future<bool> _setLanguage(SpeechEngine speech, String language) async {
    try {
      return await speech.setLanguage(language);
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyIosVoice(SpeechEngine speech, String language) async {
    try {
      final voices = await speech.getVoices();
      final voice = iosVoiceFor(voices, language);
      if (voice == null) return;
      final payload = <String, String>{
        if ((voice['name'] ?? '').isNotEmpty) 'name': voice['name']!,
        if ((voice['locale'] ?? '').isNotEmpty) 'locale': voice['locale']!,
        if ((voice['identifier'] ?? '').isNotEmpty) 'identifier': voice['identifier']!,
      };
      if (payload.isEmpty) return;
      await speech.setVoice(payload);
    } catch (_) {
      // The language is already set. Speech can continue without a named voice.
    }
  }
}
