import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // 👈 必須加入這行匯入
import 'package:shared_preferences/shared_preferences.dart';
import 'bus_api_service.dart';
import 'notification_service.dart';

class BackgroundTrackerService {
static Future<void> initialize() async {
    // 1. 註冊通知頻道 (保留上次的修改)
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'macau_bus_alarm', 
      '巴士實時追蹤', 
      description: '顯示巴士背景追蹤狀態', 
      importance: Importance.high, 
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 2. 設定背景服務
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // 🔑 必須確保這裡是 false，禁止系統自動啟動
        isForegroundMode: true,
        notificationChannelId: 'macau_bus_alarm',
        initialNotificationTitle: '巴士追蹤中',
        initialNotificationContent: '正在背景為您實時監測巴士到站狀態',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );

    // 👇 3. 終極防呆清場機制：App 啟動時，檢查是否有進行中的任務
    final prefs = await SharedPreferences.getInstance();
    final route = prefs.getString('track_route');
    
    // 如果發現沒有儲存路線（代表用戶根本未撳追蹤），但服務卻在運行（幽靈進程）
    if (route == null || route.isEmpty) {
      if (await service.isRunning()) {
        // 即刻發送停止指令，將殘留的通知與服務強制擊殺
        service.invoke('stopService');
      }
    }
  }

  // 啟動追蹤：將當前路線參數寫入 SharedPreferences，然後啟動服務
  static Future<void> startTracking({
    required String route, 
    required int direction, 
    required int targetStopSeq
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('track_route', route);
    await prefs.setInt('track_dir', direction);
    await prefs.setInt('track_stop_seq', targetStopSeq);
    
    final service = FlutterBackgroundService();
    await service.startService();
  }

  // 停止追蹤
  static Future<void> stopTracking() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('track_route');
    await prefs.remove('track_dir');
    await prefs.remove('track_stop_seq');
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.init();
  
  final prefs = await SharedPreferences.getInstance();
  
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 背景定時器：每 10 秒檢查一次
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    String route = prefs.getString('track_route') ?? '';
    int dir = prefs.getInt('track_dir') ?? 0;
    int stopSeq = prefs.getInt('track_stop_seq') ?? -1;

    if (route.isEmpty || stopSeq == -1) {
      timer.cancel();
      service.stopSelf();
      return;
    }

    try {
      final result = await BusApiService.fetchBusETA(route, dir, targetStopSeq: stopSeq);
      
      if (result['success'] == true) {
        List<dynamic> allBuses = result['allBuses'];
        
        for (var bus in allBuses) {
          int currentSeq = bus.currentStopSeq;
          if (currentSeq > 0) {
            int stopsAway = stopSeq - currentSeq;
            
            if (stopsAway >= 0 && stopsAway <= 2) {
              await NotificationService.showAlarm(
                '🚌 準備上車！', 
                '$route 路線即將抵達第 $stopSeq 站，請準備！'
              );
              
              timer.cancel();
              service.stopSelf();
              break;
            }
          }
        }
      }
    } catch (e) {
      // 容錯處理
    }
  });
}