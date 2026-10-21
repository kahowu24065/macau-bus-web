import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:io' show Platform;

import '../utils/boarding_alert_schedule.dart';

class NotificationService {
  static const int arrivalNotificationId = 889;
  static const String boardingAlarmSentKey = 'track_alarm_sent';
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (!kIsWeb && !Platform.isWindows) {
      const androidSettings = AndroidInitializationSettings('ic_bg_service_small');
      
      // 💡 iOS：初始化時唔即刻問通知權限（會阻住第一個畫面），
      // 改為第一個畫面出咗之後由 requestIosPermission() 再問。
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      await _plugin.initialize(settings: settings);
    }
  }

  static Future<void> requestPermission() async {
    if (!kIsWeb && !Platform.isWindows) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) await androidImpl.requestNotificationsPermission();
    }
  }

  /// iOS only: ask for notification permission after the first frame is shown.
  static Future<void> requestIosPermission() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      final iosImpl = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('iOS notification permission request failed: $e');
    }
  }

  /// Returns false if the foreground or background isolate already claimed this boarding alert.
  static Future<bool> claimBoardingAlarm() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool(boardingAlarmSentKey) == true) return false;
    await prefs.setBool(boardingAlarmSentKey, true);
    return true;
  }

  static Future<void> showAlarm(String title, String body) async {
    if (kIsWeb || Platform.isWindows) return; 
    
    // 💡 結合新功能：加入聲音及詳細描述
    const androidDetails = AndroidNotificationDetails(
      'macau_bus_alarm', '巴士到站提醒',
      channelDescription: '用於推送巴士即將到站及下車提醒',
      importance: Importance.max, 
      priority: Priority.high, 
      enableVibration: true,
      playSound: true,
      onlyAlertOnce: true,
    );
    
    // 💡 結合新功能：加入 iOS 橫幅設定
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    // Fixed ID so foreground + background monitors overwrite each other
    // instead of stacking duplicate alerts. Must not be 888 (ongoing tracking).
    await _plugin.show(
      id: arrivalNotificationId,
      title: title, 
      body: body, 
      notificationDetails: details
    );
  }

  /// Tests record the banners instead of calling the plugin, which is not
  /// implemented on the Linux test VM.
  @visibleForTesting
  static Future<void> Function(List<ScheduledBoardingAlert> alerts)? debugScheduleBoardingAlerts;

  @visibleForTesting
  static Future<void> Function()? debugCancelBoardingAlerts;

  /// Arms the 3-minute and arrival banners from the predicted arrival time.
  /// Replaces any banners already armed for the previous stop. Does not need a
  /// Live Activity push token: iOS keeps the request after the app is backgrounded.
  static Future<void> scheduleBoardingAlerts(List<ScheduledBoardingAlert> alerts) async {
    final override = debugScheduleBoardingAlerts;
    if (override != null) {
      await override(alerts);
      return;
    }
    if (kIsWeb || Platform.isWindows || alerts.isEmpty) return;
    try {
      await _cancelBoardingAlertIds();
      await requestPermission();
      await requestIosPermission();
      for (final alert in alerts) {
        await _zonedBoardingAlert(alert);
      }
    } catch (e) {
      debugPrint('schedule boarding alerts: $e');
    }
  }

  static Future<void> cancelBoardingAlerts() async {
    final override = debugCancelBoardingAlerts;
    if (override != null) {
      await override();
      return;
    }
    if (kIsWeb || Platform.isWindows) return;
    try {
      await _cancelBoardingAlertIds();
    } catch (e) {
      debugPrint('cancel boarding alerts: $e');
    }
  }

  static Future<void> _cancelBoardingAlertIds() async {
    await _plugin.cancel(id: boardingWarningNotificationId);
    await _plugin.cancel(id: boardingArrivalNotificationId);
  }

  static Future<void> _zonedBoardingAlert(ScheduledBoardingAlert alert) async {
    final when = tz.TZDateTime.from(alert.at.toUtc(), tz.UTC);
    try {
      await _plugin.zonedSchedule(
        id: alert.id,
        title: alert.title,
        body: alert.body,
        scheduledDate: when,
        notificationDetails: _boardingAlertDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // A payload marks this as a plugin notification, so the foreground
        // delegate presents the banner and plays the default sound.
        payload: 'boarding',
      );
    } catch (e) {
      debugPrint('exact boarding alert ${alert.id}: $e');
      await _plugin.zonedSchedule(
        id: alert.id,
        title: alert.title,
        body: alert.body,
        scheduledDate: when,
        notificationDetails: _boardingAlertDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'boarding',
      );
    }
  }
}

/// Default sound is left unset so iOS uses UNNotificationSound.default, which
/// vibrates. Time Sensitive is not set: that needs an entitlement.
const NotificationDetails _boardingAlertDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'macau_bus_alarm',
    '巴士到站提醒',
    channelDescription: '用於推送巴士即將到站及下車提醒',
    importance: Importance.max,
    priority: Priority.high,
    enableVibration: true,
    playSound: true,
    onlyAlertOnce: false,
  ),
  iOS: DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: false,
    presentBanner: true,
    presentList: true,
    presentSound: true,
    interruptionLevel: InterruptionLevel.active,
  ),
);