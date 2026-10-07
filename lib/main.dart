import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'controllers/purchase_controller.dart';

import 'services/background_tracker_service.dart';
import 'services/notification_service.dart';
import 'controllers/theme_controller.dart';
import 'controllers/elderly_mode_controller.dart';
import 'theme/elderly_theme.dart';
import 'views/widgets/elderly_tap_haptics.dart';
import 'views/widgets/preserve_chrome.dart';
import 'controllers/bus_controller.dart';
import 'controllers/location_controller.dart';
import 'controllers/navigation_controller.dart';
import 'controllers/keyboard_controller.dart'; // 🌟 匯入新 Controller
import 'views/screens/home_screen.dart';
import 'views/widgets/route_liquid_glass_nav.dart';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'controllers/background_controller.dart';
import 'controllers/language_controller.dart';
import 'http_overrides_setup.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installApiHttpOverrides();
  await LiquidGlassShaders.ensureLoaded();
  
  if (!kIsWeb) {
    if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
      // 🌟 移除 await：讓廣告 SDK 喺背景自行初始化，唔好阻住開機
      MobileAds.instance.initialize();
    }
    
    // 呢兩個通常純粹係本地設定，保留 await 影響唔大，但如果 init 入面有重型任務，亦可以考慮移除 await
    await NotificationService.init();
    await BackgroundTrackerService.initialize();
    
    // 🌟 移除 await：請求權限應該喺背景執行，或者移去 HomeScreen 嘅 initState
    await NotificationService.requestPermission();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => ElderlyModeController()),
        ChangeNotifierProvider(create: (_) => BusController()),
        ChangeNotifierProvider(create: (_) => LocationController()),
        ChangeNotifierProvider(create: (_) => NavigationController()),
        ChangeNotifierProvider(create: (_) => PurchaseController()),
        ChangeNotifierProvider(create: (_) => KeyboardController()), // 🌟 註冊全局鍵盤狀態
        ChangeNotifierProvider(create: (_) => BackgroundController()), // 🌟 註冊 BackgroundController
        ChangeNotifierProvider(create: (_) => LanguageController()),
      ],
      child: const MacauBusApp(),
    ),
  );

  // iOS：先顯示畫面，再問通知權限（Android 照舊喺上面處理）
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.requestIosPermission();
    });
  }
}

class MacauBusApp extends StatelessWidget {
  const MacauBusApp({super.key});
  
  @override 
  Widget build(BuildContext context) { 
    final theme = context.watch<ThemeController>();
    final view = View.of(context);
    final barHeight = RouteLiquidGlassNavStyle.barHeightOf(context);
    final safeBottom = view.padding.bottom / view.devicePixelRatio;
    final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final snackBarTheme = SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      insetPadding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        barHeight +
            RouteLiquidGlassNavStyle.barBottomOffset(safeBottom, ios: ios),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );
    return MaterialApp(
      title: '巴士預報-MBKa', 
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final elderlyOn = context.watch<ElderlyModeController>().enabled;
        if (!elderlyOn || child == null) return child ?? const SizedBox.shrink();
        final base = Theme.of(context);
        final mq = MediaQuery.of(context);
        final scaled = mq.textScaler.scale(1) * ElderlyTheme.textScale;
        return ElderlyChrome(
          baseTheme: base,
          child: MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(scaled)),
            child: Theme(
              data: ElderlyTheme.apply(base),
              child: ElderlyTapHaptics(child: child),
            ),
          ),
        );
      },
      themeMode: theme.themeMode,
      theme: ThemeData(
        brightness: Brightness.light, 
        scaffoldBackgroundColor: Colors.grey[100], 
        cardColor: Colors.white, 
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0), 
        colorScheme: const ColorScheme.light(primary: Colors.amber, surface: Colors.white),
        snackBarTheme: snackBarTheme,
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212), 
        cardColor: const Color(0xFF1E1E1E), 
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black, elevation: 0), 
        colorScheme: const ColorScheme.dark(primary: Colors.amber, surface: Color(0xFF1E1E1E)),
        snackBarTheme: snackBarTheme,
      ),
      home: const HomeScreen()
    ); 
  }
}