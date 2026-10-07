import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/bus_controller.dart';
import '../controllers/location_controller.dart';
import '../controllers/language_controller.dart';
import '../utils/easy_read_access.dart';
import '../views/widgets/route_liquid_glass_nav.dart';

class GpsService {
  /// 統一處理開啟/關閉 GPS，並在首次定位成功時自動選取最近站點
  static void toggleGpsAndAutoSelectStop(
    BuildContext context, 
    BusController busCtrl, 
    LocationController locCtrl, 
    {bool showSnackbar = true} 
  ) {
    bool wasFollowing = locCtrl.isFollowingUser;
    bool hasAutoSelected = false; 
    
    // 🌟 即時讀取語言設定，確保獲取最新狀態
    final langCtrl = context.read<LanguageController>();
    final allowSnack = showSnackbar && !EasyReadAccess.enabled(context, listen: false);

    if (allowSnack) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    locCtrl.toggleLocationTracking((loc) {
      if (!wasFollowing && !hasAutoSelected) {
        hasAutoSelected = true; 
        final res = busCtrl.findNearestStop(loc);
        
        if (res != null) {
          busCtrl.selectStop(res['seq']);
          busCtrl.fetchBusETA();
          
          if (allowSnack) {
            // 💡 1. 提取靜態 UI 翻譯
            String stopMsg = langCtrl.tr('auto_selected_stop');
            String distMsg = langCtrl.tr('distance_approx');
            
            // 💡 2. 終極解法：喺 busCtrl.stopsList 搵返個車站，然後叫佢自己做翻譯！
            String stopName = res['name'] ?? '未知站點'; // 預設用中文兜底
            try {
              // 透過 seq 搵返對應嘅車站 Object
              final stopObj = busCtrl.stopsList.firstWhere((s) => s.seq == res['seq']);
              // 直接調用你 Model 已經寫好嘅翻譯函數！
              stopName = stopObj.getLocalizedName(langCtrl.currentLanguage);
            } catch (e) {
              // 防呆機制：萬一搵唔到，就繼續用預設中文
              debugPrint('GPS Auto Select: 搵唔到對應嘅車站 Object');
            }
            
            // 💡 3. 將翻譯好嘅 $stopName 放入 SnackBar
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              RouteLiquidGlassNavStyle.snackBar(
                context: context,
                content: Text(
                  '📍 $stopMsg: ${res['seq']}. $stopName\n($distMsg ${res['distance']}m)'
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    });

    if (allowSnack) {
      if (!wasFollowing) {
        ScaffoldMessenger.of(context).showSnackBar(
          RouteLiquidGlassNavStyle.snackBar(
            context: context,
            content: Text(langCtrl.tr('gps_tracking_on')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          RouteLiquidGlassNavStyle.snackBar(
            context: context,
            content: Text(langCtrl.tr('gps_tracking_off')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}