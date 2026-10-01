import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bus_api_service.dart';
import 'notification_service.dart';
import '../constants/app_translations.dart';

class _NotificationConfig {
  static const String foregroundChannelId = 'macau_bus_tracking_v2';
  static const String alarmChannelId = 'macau_bus_arrival_v2';

  static const String foregroundChannelName = '巴士背景監測';
  static const String alarmChannelName = '巴士到站提示';

  static const int foregroundNotificationId = 888;
}

const String _alarmSentKey = NotificationService.boardingAlarmSentKey;

String _normaliseLanguage(String language) {
  final String value = language.trim().replaceAll('_', '-').toLowerCase();

  if (value == 'zh-hk' || value == 'zh-tw' || value == 'zh-hant') return 'zh';
  if (value == 'zh-cn' || value == 'zh-sg' || value == 'zh-hans') return 'zh';
  if (value.startsWith('en')) return 'en';
  if (value.startsWith('pt')) return 'pt';

  return value.isEmpty ? 'zh' : value;
}

String _bgTr(
  String key,
  String language, {
  Map<String, String>? params,
}) {
  final Map<String, Map<String, String>> data = AppTranslations.data;
  final String lang = _normaliseLanguage(language);

  String text = data[lang]?[key] ?? data[language]?[key] ?? data['zh']?[key] ?? key;

  if (params != null) {
    for (final entry in params.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
  }
  return text;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

int? _getCurrentStopSeq(dynamic bus) {
  if (bus is Map) {
    const keys = <String>['currentStopSeq', 'current_stop_seq', 'currentStop', 'stopSeq', 'stop_seq'];
    for (final key in keys) {
      final int? value = _toInt(bus[key]);
      if (value != null) return value;
    }
    return null;
  }
  try {
    return _toInt((bus as dynamic).currentStopSeq);
  } catch (_) {
    return null;
  }
}

List<dynamic> _getAllBuses(dynamic result) {
  if (result is! Map) return <dynamic>[];
  final dynamic buses = result['allBuses'] ?? result['all_buses'];
  return buses is List ? List<dynamic>.from(buses) : <dynamic>[];
}

class BackgroundTrackerService {
  static Future<void> initialize() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String lang = prefs.getString('language_code') ?? 'zh';
    final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

    const AndroidNotificationChannel foregroundChannel = AndroidNotificationChannel(
      _NotificationConfig.foregroundChannelId,
      _NotificationConfig.foregroundChannelName,
      description: '顯示巴士背景監測狀態',
      importance: Importance.high,
      playSound: false,
      enableVibration: true,
    );

    const AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
      _NotificationConfig.alarmChannelId,
      _NotificationConfig.alarmChannelName,
      description: '顯示巴士到站提示',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidNotifications =
        notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidNotifications?.createNotificationChannel(foregroundChannel);
    await androidNotifications?.createNotificationChannel(alarmChannel);

    final FlutterBackgroundService service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _NotificationConfig.foregroundChannelId,
        initialNotificationTitle: _bgTr('bg_tracking_title', lang),
        initialNotificationContent: _bgTr('bg_tracking_body', lang),
        foregroundServiceNotificationId: _NotificationConfig.foregroundNotificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );

    final String route = prefs.getString('track_route') ?? '';
    if (route.isEmpty && await service.isRunning()) {
      service.invoke('stopService');
    }
  }

  static Future<void> startTracking({
    required String route,
    required int direction,
    required int targetStopSeq,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final FlutterBackgroundService service = FlutterBackgroundService();
    final bool alreadyRunning = await service.isRunning();

    await prefs.setString('track_route', route);
    await prefs.setInt('track_dir', direction);
    await prefs.setInt('track_stop_seq', targetStopSeq);

    final String lang = prefs.getString('language_code') ?? 'zh';

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _NotificationConfig.foregroundChannelId,
        initialNotificationTitle: _bgTr('bg_tracking_title', lang),
        initialNotificationContent: _bgTr('bg_tracking_body', lang),
        foregroundServiceNotificationId: _NotificationConfig.foregroundNotificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );

    await prefs.setBool(_alarmSentKey, false);

    if (!alreadyRunning) {
      await service.startService();
    }
  }

  static Future<void> stopTracking() async {
    final FlutterBackgroundService service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stopService');
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('track_route');
    await prefs.remove('track_dir');
    await prefs.remove('track_stop_seq');
    await prefs.remove(_alarmSentKey);
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.init();

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  Timer? timer;
  bool isChecking = false;
  bool hasShownAlarm = false;
  String lastLanguage = '';

  void stopBackgroundTracking() {
    timer?.cancel();
    timer = null;
    service.stopSelf();
  }

  service.on('stopService').listen((_) {
    stopBackgroundTracking();
  });

  // 🌟 已修復：避開 AndroidServiceInstance，直接用 Plugin 覆寫通知
  Future<void> updateForegroundText(String lang, String route) async {
    final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
    
    // 🌟 修正重點：補返 id:, title:, body:, notificationDetails: 呢四個標籤
    await plugin.show(
      id: _NotificationConfig.foregroundNotificationId, // 888
      title: _bgTr('bg_tracking_title', lang),
      body: _bgTr('bg_tracking_body', lang),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _NotificationConfig.foregroundChannelId,
          _NotificationConfig.foregroundChannelName,
          icon: 'ic_bg_service_small', 
          ongoing: true,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
        ),
      ),
    );
  }

  Future<void> checkTracking() async {
    if (isChecking) return;
    isChecking = true;

    try {
      await prefs.reload();

      final String route = prefs.getString('track_route') ?? '';
      final int direction = prefs.getInt('track_dir') ?? 0;
      final int targetStopSeq = prefs.getInt('track_stop_seq') ?? -1;
      final String lang = prefs.getString('language_code') ?? 'zh';
      final bool alarmSent = prefs.getBool(_alarmSentKey) ?? false;

      if (route.isEmpty || targetStopSeq < 0 || alarmSent) {
        stopBackgroundTracking();
        return;
      }

      if (lang != lastLanguage) {
        lastLanguage = lang;
        await updateForegroundText(lang, route);
      }

      final dynamic result = await BusApiService.fetchBusETA(
        route,
        direction,
        targetStopSeq: targetStopSeq,
        lang: _normaliseLanguage(lang),
      );

      if (result is! Map || result['success'] != true) return;

      for (final dynamic bus in _getAllBuses(result)) {
        final int? currentStopSeq = _getCurrentStopSeq(bus);
        if (currentStopSeq == null || currentStopSeq <= 0) continue;

        final int stopsAway = targetStopSeq - currentStopSeq;
        if (stopsAway < 0 || stopsAway > 2) continue;

        if (hasShownAlarm) {
          stopBackgroundTracking();
          return;
        }

        final bool claimed = await NotificationService.claimBoardingAlarm();
        if (!claimed) {
          hasShownAlarm = true;
          stopBackgroundTracking();
          return;
        }

        hasShownAlarm = true;

        final String title = _bgTr('board_ready_title', lang);
        final String body = _bgTr(
          'board_ready_body',
          lang,
          params: <String, String>{
            '@route': route,
            '@stop': targetStopSeq.toString(),
          },
        );

        await NotificationService.showAlarm(title, body);
        stopBackgroundTracking();
        return;
      }
    } catch (error, stackTrace) {
      debugPrint('Background tracking error: $error');
      debugPrint('$stackTrace');
    } finally {
      isChecking = false;
    }
  }

  timer = Timer.periodic(
    const Duration(seconds: 10),
    (_) => checkTracking(),
  );

  await checkTracking();
}