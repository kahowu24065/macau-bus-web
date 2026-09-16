import 'package:flutter/material.dart';
import '../controllers/bus_controller.dart';
import '../controllers/location_controller.dart';

class GpsService {
  /// 統一處理開啟/關閉 GPS，並在首次定位成功時自動選取最近站點
  static void toggleGpsAndAutoSelectStop(BuildContext context, BusController busCtrl, LocationController locCtrl) {
    bool wasFollowing = locCtrl.isFollowingUser;
    bool hasAutoSelected = false; // 單次執行鎖標記

    // 清除舊有提示
    ScaffoldMessenger.of(context).clearSnackBars();

    locCtrl.toggleLocationTracking((loc) {
      // 雙重攔截：只有啱啱開啟定位 (!wasFollowing) 而且未選擇過 (!hasAutoSelected) 先執行
      if (!wasFollowing && !hasAutoSelected) {
        hasAutoSelected = true; // 鎖上標記，防止後續更新狂彈
        final res = busCtrl.findNearestStop(loc);
        
        if (res != null) {
          busCtrl.selectStop(res['seq']);
          busCtrl.fetchBusETA();
          
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '📍 已為您選取最近站點：${res['seq']}. ${res['name']}\n(距離約 ${res['distance']} 公尺)'
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    });

    // 顯示開關狀態提示
    if (!wasFollowing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已開啟實時追蹤及定位'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已取消實時定位追蹤'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}