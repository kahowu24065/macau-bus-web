import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class NotificationService {
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
      
      // 🛡️ 保留原版：使用 settings: 標籤
      await _plugin.initialize(settings: settings);
    }
  }

  static Future<void> requestPermission() async {
    if (!kIsWeb && !Platform.isWindows) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) await androidImpl.requestNotificationsPermission();
    }
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
    
    // 🛡️ 保留原版：使用 id:, title:, body:, notificationDetails: 標籤
    // 💡 優化：將 id 設為毫秒時間戳，確保連續觸發多個站點時，通知唔會互相冚走
    await _plugin.show(
      id: DateTime.now().millisecond, 
      title: title, 
      body: body, 
      notificationDetails: details
    );
  }
}