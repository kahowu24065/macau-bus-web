import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'controllers/purchase_controller.dart';

import 'services/background_tracker_service.dart';
import 'services/notification_service.dart';
import 'controllers/theme_controller.dart';
import 'controllers/bus_controller.dart';
import 'controllers/location_controller.dart';
import 'controllers/navigation_controller.dart';
import 'views/screens/home_screen.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await MobileAds.instance.initialize();
  }
  
  await NotificationService.init();
  await BackgroundTrackerService.initialize();
  await NotificationService.requestPermission();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => BusController()),
        ChangeNotifierProvider(create: (_) => LocationController()),
        ChangeNotifierProvider(create: (_) => NavigationController()),
        ChangeNotifierProvider(create: (_) => PurchaseController()),
      ],
      child: const MacauBusApp(),
    ),
  );
}

class MacauBusApp extends StatelessWidget {
  const MacauBusApp({super.key});
  @override 
  Widget build(BuildContext context) { 
    final theme = context.watch<ThemeController>();
    return MaterialApp(
      title: '澳門巴士實時報站與地圖', 
      debugShowCheckedModeBanner: false,
      themeMode: theme.themeMode,
      theme: ThemeData(brightness: Brightness.light, scaffoldBackgroundColor: Colors.grey[100], cardColor: Colors.white, appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0), colorScheme: const ColorScheme.light(primary: Colors.amber, surface: Colors.white)),
      darkTheme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF121212), cardColor: const Color(0xFF1E1E1E), appBarTheme: const AppBarTheme(backgroundColor: Colors.black, elevation: 0), colorScheme: const ColorScheme.dark(primary: Colors.amber, surface: Color(0xFF1E1E1E))),
      home: const HomeScreen()
    ); 
  }
}