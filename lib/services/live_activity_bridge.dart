import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of asking ActivityKit to show the boarding reminder.
class LiveActivityStart {
  final bool started;
  final String? token;
  final String? error;

  /// This platform has no Live Activity. That is not a failure of the reminder.
  final bool unavailable;

  const LiveActivityStart({
    required this.started,
    this.token,
    this.error,
    this.unavailable = false,
  });

  const LiveActivityStart.unavailable()
      : started = false,
        token = null,
        error = null,
        unavailable = true;

  /// Snackbar key when the activity did not start. Null when it did, or when
  /// this platform does not show Live Activities.
  String? get messageKey {
    if (started || unavailable || error == null || error!.isEmpty) return null;
    switch (error) {
      case 'activities_disabled':
      case 'denied':
      case 'visibility':
        return 'boarding_live_disabled';
      default:
        return 'boarding_live_failed';
    }
  }

  static LiveActivityStart fromChannel(Object? raw) {
    if (raw is Map) {
      final token = raw['token'];
      final error = raw['error'];
      final tokenText = token is String && token.isNotEmpty ? token : null;
      final errorText = error is String && error.isNotEmpty ? error : null;
      return LiveActivityStart(
        started: raw['started'] == true,
        token: tokenText,
        error: errorText,
      );
    }
    if (raw is String && raw.isNotEmpty) {
      return LiveActivityStart(started: true, token: raw);
    }
    return const LiveActivityStart(started: false, error: 'empty');
  }
}

/// Talks to ActivityKit. Off iOS, and in tests, the token stays null.
class LiveActivityBridge {
  static const MethodChannel _channel = MethodChannel('mbka/boarding_live_activity');

  static void Function(String token)? onActivityToken;

  @visibleForTesting
  static Future<String?> Function()? debugPushToStartToken;

  @visibleForTesting
  static Future<LiveActivityStart> Function({
    required String route,
    required String stopName,
    required int minutes,
    required String text,
    double? endsAt,
    String? etaLabel,
    String? arrivedText,
    String? imminentText,
  })? debugStartActivity;

  @visibleForTesting
  static Future<void> Function({
    required int minutes,
    required String text,
    double? endsAt,
    String? etaLabel,
    String? arrivedText,
    String? imminentText,
  })? debugUpdate;

  @visibleForTesting
  static Future<void> Function()? debugEnd;

  static bool _handlerInstalled = false;

  static void _ensureHandler() {
    if (_handlerInstalled || kIsWeb) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'activityToken' && call.arguments is String) {
        final token = call.arguments as String;
        if (token.isNotEmpty) onActivityToken?.call(token);
      }
      return null;
    });
  }

  /// A push-to-start token lets the server refresh the Live Activity while the
  /// app is backgrounded. Null when the phone cannot provide one.
  static Future<String?> pushToStartToken() async {
    final override = debugPushToStartToken;
    if (override != null) return override();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    _ensureHandler();
    try {
      final token = await _channel.invokeMethod<String>('pushToStartToken');
      if (token == null || token.isEmpty) return null;
      return token;
    } catch (e) {
      debugPrint('pushToStartToken: $e');
      return null;
    }
  }

  static Future<LiveActivityStart> startActivity({
    required String route,
    required String stopName,
    required int minutes,
    required String text,
    double? endsAt,
    String? etaLabel,
    String? arrivedText,
    String? imminentText,
  }) async {
    final override = debugStartActivity;
    if (override != null) {
      return override(
        route: route,
        stopName: stopName,
        minutes: minutes,
        text: text,
        endsAt: endsAt,
        etaLabel: etaLabel,
        arrivedText: arrivedText,
        imminentText: imminentText,
      );
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const LiveActivityStart.unavailable();
    }
    _ensureHandler();
    try {
      final raw = await _channel.invokeMethod<dynamic>('startActivity', {
        'route': route,
        'stopName': stopName,
        'minutes': minutes,
        'text': text,
        if (endsAt != null) 'endsAt': endsAt,
        if (etaLabel != null && etaLabel.isNotEmpty) 'etaLabel': etaLabel,
        if (arrivedText != null && arrivedText.isNotEmpty) 'arrivedText': arrivedText,
        if (imminentText != null && imminentText.isNotEmpty) 'imminentText': imminentText,
      });
      final start = LiveActivityStart.fromChannel(raw);
      if (!start.started) {
        debugPrint('startActivity failed: ${start.error}');
      }
      return start;
    } catch (e) {
      debugPrint('startActivity: $e');
      return const LiveActivityStart(started: false, error: 'channel');
    }
  }

  static Future<void> update({
    required int minutes,
    required String text,
    double? endsAt,
    String? etaLabel,
    String? arrivedText,
    String? imminentText,
  }) async {
    final override = debugUpdate;
    if (override != null) {
      await override(
        minutes: minutes,
        text: text,
        endsAt: endsAt,
        etaLabel: etaLabel,
        arrivedText: arrivedText,
        imminentText: imminentText,
      );
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>('updateActivity', {
        'minutes': minutes,
        'text': text,
        if (endsAt != null) 'endsAt': endsAt,
        if (etaLabel != null && etaLabel.isNotEmpty) 'etaLabel': etaLabel,
        if (arrivedText != null && arrivedText.isNotEmpty) 'arrivedText': arrivedText,
        if (imminentText != null && imminentText.isNotEmpty) 'imminentText': imminentText,
      });
    } catch (e) {
      debugPrint('updateActivity: $e');
    }
  }

  static Future<void> end() async {
    final override = debugEnd;
    if (override != null) {
      await override();
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>('endActivity');
    } catch (e) {
      debugPrint('endActivity: $e');
    }
  }
}
