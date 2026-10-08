import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/alighting_location.dart';

/// iOS Always-location prompt for the alighting reminder.
///
/// Map location and the boarding reminder do not use this. Geolocator's
/// requestPermission stays on While Using because the When In Use purpose
/// string is present.
class AlightingLocationService {
  static const MethodChannel _channel = MethodChannel('mbka/alighting_location');
  static const String upgradePromptKey = 'alighting_always_upgrade_requested';

  @visibleForTesting
  static Future<String> Function()? debugStatus;

  @visibleForTesting
  static Future<String> Function()? debugRequestAlways;

  static Future<AlightingPermissionDecision> requestForAlightingReminder() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return _whileUsing();
    }
    final prefs = await SharedPreferences.getInstance();
    final decision = await decideAlightingPermission(
      readStatus: _status,
      requestAlways: _requestAlways,
      upgradePromptUsed: prefs.getBool(upgradePromptKey) ?? false,
    );
    await prefs.setBool(upgradePromptKey, decision.upgradePromptUsed);
    return decision;
  }

  static Future<String> _status() async {
    final override = debugStatus;
    if (override != null) return override();
    final value = await _channel.invokeMethod<String>('authorizationStatus');
    return value ?? 'denied';
  }

  static Future<String> _requestAlways() async {
    final override = debugRequestAlways;
    if (override != null) return override();
    final value = await _channel.invokeMethod<String>('requestAlways');
    return value ?? 'denied';
  }

  static Future<AlightingPermissionDecision> _whileUsing() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      return const AlightingPermissionDecision(
        action: AlightingPermissionAction.ready,
        upgradePromptUsed: false,
      );
    }
    if (permission == LocationPermission.deniedForever) {
      return const AlightingPermissionDecision(
        action: AlightingPermissionAction.settingsOnly,
        upgradePromptUsed: false,
      );
    }
    return const AlightingPermissionDecision(
      action: AlightingPermissionAction.denied,
      upgradePromptUsed: false,
    );
  }
}
