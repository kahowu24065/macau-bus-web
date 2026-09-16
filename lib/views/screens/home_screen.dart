import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 引入所有 6 個分頁
import 'dashboard_screen.dart';   // 首頁
import 'route_list_screen.dart';  // 路線
import 'bus_route_screen.dart';   // 車站
import 'map_screen.dart';         // 地圖
import 'favorites_screen.dart';   // 收藏
import 'settings_screen.dart';    // 設定

import '../../controllers/bus_controller.dart';
import '../../controllers/navigation_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override 
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BusController>().fetchStops();
    });
    _loadDefaultTab();
  }

  Future<void> _loadDefaultTab() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt('default_tab_index') ?? 0; // 預設首頁
    if (mounted) {
      context.read<NavigationController>().changeTab(savedIndex);
    }
  }

  @override 
  Widget build(BuildContext context) { 
    final isDark = Theme.of(context).brightness == Brightness.dark; 
    final navCtrl = context.watch<NavigationController>();

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: navCtrl.selectedIndex, 
          children: const [
            DashboardScreen(),  // Index 0: 首頁
            RouteListScreen(),  // Index 1: 路線
            BusRouteScreen(),   // Index 2: 車站
            MapScreen(),        // Index 3: 地圖
            FavoritesScreen(),  // Index 4: 收藏
            SettingsScreen()    // Index 5: 設定
          ]
        )
      ), 
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navCtrl.selectedIndex, 
        onTap: (index) {
          context.read<BusController>().cancelMapPicking();
          context.read<NavigationController>().changeTab(index);
        }, 
        backgroundColor: isDark ? Colors.black : Colors.white, 
        selectedItemColor: Colors.amber, 
        unselectedItemColor: isDark ? Colors.grey : Colors.grey[600], 
        type: BottomNavigationBarType.fixed, 
        // 🌟 核心微調：因為有 6 個 Tab，將字體稍微縮細，防止文字重疊
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首頁'), 
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '路線'), 
          BottomNavigationBarItem(icon: Icon(Icons.directions_bus), label: '車站'), 
          BottomNavigationBarItem(icon: Icon(Icons.map), label: '地圖'), 
          BottomNavigationBarItem(icon: Icon(Icons.star), label: '收藏'), 
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定')
        ]
      )
    ); 
  }
}