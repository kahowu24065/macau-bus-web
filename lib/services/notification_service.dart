import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:io' show File, Platform;

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

    final iconPath = await _mbkaIconPath();
    final androidDetails = AndroidNotificationDetails(
      'macau_bus_alarm', '巴士到站提醒',
      channelDescription: '用於推送巴士即將到站及下車提醒',
      importance: Importance.max, 
      priority: Priority.high, 
      enableVibration: true,
      playSound: true,
      onlyAlertOnce: true,
      largeIcon: _mbkaLargeIcon,
    );
    
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      attachments: _mbkaAttachment(iconPath),
    );
    
    final details = NotificationDetails(
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
      final details = await _boardingAlertDetails();
      for (final alert in alerts) {
        await _zonedBoardingAlert(alert, details);
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

  static Future<void> _zonedBoardingAlert(
    ScheduledBoardingAlert alert,
    NotificationDetails details,
  ) async {
    final when = tz.TZDateTime.from(alert.at.toUtc(), tz.UTC);
    try {
      await _plugin.zonedSchedule(
        id: alert.id,
        title: alert.title,
        body: alert.body,
        scheduledDate: when,
        notificationDetails: details,
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
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'boarding',
      );
    }
  }
}

/// Color MBKa artwork for the notification shade. The status-bar small icon
/// stays the white silhouette (`ic_bg_service_small`); a color PNG there
/// collapses to a white blob.
const DrawableResourceAndroidBitmap _mbkaLargeIcon =
    DrawableResourceAndroidBitmap('ic_mbka_notification');

String? _mbkaIconPathCache;

/// Copies the MBKa icon so iOS can attach it. The banner's leading glyph is
/// the app icon (AppIcon); the attachment is the same artwork, which the
/// system copies when the notification is scheduled.
Future<String?> _mbkaIconPath() async {
  final cached = _mbkaIconPathCache;
  if (cached != null && File(cached).existsSync()) return cached;
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'mbka_notification_icon.png'));
    if (!file.existsSync() || file.lengthSync() == 0) {
      final data = await rootBundle.load('assets/notification_icon.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    _mbkaIconPathCache = file.path;
    return file.path;
  } catch (e) {
    debugPrint('boarding app icon: $e');
    return null;
  }
}

List<DarwinNotificationAttachment>? _mbkaAttachment(String? iconPath) {
  if (iconPath == null || iconPath.isEmpty) return null;
  return [DarwinNotificationAttachment(iconPath, identifier: 'mbka_app_icon')];
}

/// Default sound is left unset so iOS uses UNNotificationSound.default, which
/// vibrates. Time Sensitive is not set: that needs an entitlement.
Future<NotificationDetails> _boardingAlertDetails() async {
  final iconPath = await _mbkaIconPath();
  return NotificationDetails(
    android: const AndroidNotificationDetails(
      'macau_bus_alarm',
      '巴士到站提醒',
      channelDescription: '用於推送巴士即將到站及下車提醒',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      onlyAlertOnce: false,
      largeIcon: _mbkaLargeIcon,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentBanner: true,
      presentList: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
      attachments: _mbkaAttachment(iconPath),
    ),
  );
}