import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Device speech. Tests can pass a fake [SpeechEngine].
abstract class SpeechEngine {
  Future<void> setLanguage(String language);
  Future<void> setSpeechRate(double rate);
  Future<void> speak(String text);
  Future<void> prepareIos();
}

class FlutterTtsEngine implements SpeechEngine {
  FlutterTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  var _iosReady = false;

  @override
  Future<void> setLanguage(String language) async {
    await _tts.setLanguage(language);
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

  bool get _web => isWeb ?? kIsWeb;

  bool get _ios {
    final override = isIos;
    if (override != null) return override;
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  static List<String> localesFor(String langCode) {
    switch (langCode) {
      case 'zh':
        return const ['zh-HK', 'zh-TW', 'zh-CN'];
      case 'zhHans':
        return const ['zh-CN', 'zh-Hans'];
      case 'pt':
        return const ['pt-PT', 'pt-BR'];
      case 'en':
        return const ['en-US', 'en-GB'];
      default:
        return const ['zh-HK', 'en-US'];
    }
  }

  /// Speaks [text]. Returns false when speech is unavailable.
  /// Web failures are swallowed so the rest of the app keeps working.
  Future<bool> speak(String text, String langCode) async {
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
      Object? lastError;
      for (final locale in localesFor(langCode)) {
        try {
          await speech.setLanguage(locale);
          await speech.speak(spoken);
          return true;
        } catch (error) {
          lastError = error;
        }
      }
      if (lastError != null) {
        if (_web) return false;
        throw lastError;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
