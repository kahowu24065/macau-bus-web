import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to ActivityKit. Off iOS, and in tests, the token stays null.
class LiveActivityBridge {
  static const MethodChannel _channel = MethodChannel('mbka/boarding_live_activity');

  static void Function(String token)? onActivityToken;

  @visibleForTesting
  static Future<String?> Function()? debugPushToStartToken;

  @visibleForTesting
  static Future<String?> Function({
    required String route,
    required String stopName,
    required int minutes,
    required String text,
  })? debugStartActivity;

  @visibleForTesting
  static Future<void> Function({required int minutes, required String text})? debugUpdate;

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

  /// A push-to-start token lets the server show the Live Activity when the
  /// estimate reaches about five minutes. Null when the phone cannot provide one.
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

  static Future<String?> startActivity({
    required String route,
    required String stopName,
    required int minutes,
    required String text,
  }) async {
    final override = debugStartActivity;
    if (override != null) {
      return override(route: route, stopName: stopName, minutes: minutes, text: text);
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    _ensureHandler();
    try {
      final token = await _channel.invokeMethod<String>('startActivity', {
        'route': route,
        'stopName': stopName,
        'minutes': minutes,
        'text': text,
      });
      if (token == null || token.isEmpty) return null;
      return token;
    } catch (e) {
      debugPrint('startActivity: $e');
      return null;
    }
  }

  static Future<void> update({required int minutes, required String text}) async {
    final override = debugUpdate;
    if (override != null) {
      await override(minutes: minutes, text: text);
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>('updateActivity', {
        'minutes': minutes,
        'text': text,
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
