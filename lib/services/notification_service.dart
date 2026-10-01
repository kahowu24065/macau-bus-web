import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

class NotificationService {
  static const int arrivalNotificationId = 889;
  static const String boardingAlarmSentKey = 'track_alarm_sent';
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (!kIsWeb && !Platform.isWindows) {
      const androidSettings = AndroidInitializationSettings('ic_bg_service_small');
      
      // 💡 結合新功能：加入 iOS 的通知權限設定
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
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
}