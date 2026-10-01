// ignore_for_file: file_names
import 'dart:io'; 
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_screen.dart';   
import 'route_list_screen.dart';  
import 'bus_route_screen.dart';   
import 'map_screen.dart';         
import 'favorites_screen.dart';   
import 'settings_screen.dart';    
import '../widgets/custom_banner_ad.dart';

import '../../controllers/bus_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/keyboard_controller.dart'; 
import '../../controllers/background_controller.dart'; 
// 🌟 引入語言控制器
import '../../controllers/language_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override 
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  
  Future<void> _loadLastSearchedRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRoute = prefs.getString('last_searched_route');

    if (mounted) {
      final busCtrl = context.read<BusController>();
      if (lastRoute != null && lastRoute.isNotEmpty) {
        busCtrl.setRoute(lastRoute); 
      }
      busCtrl.fetchStops(); 
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLastSearchedRoute();
    });
    _loadDefaultTab();
  }

  Future<void> _loadDefaultTab() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt('default_tab_index') ?? 0;
    if (mounted) {
      context.read<NavigationController>().changeTab(savedIndex);
    }
  }

  @override 
  Widget build(BuildContext context) { 
    final isDark = Theme.of(context).brightness == Brightness.dark; 
    final navCtrl = context.watch<NavigationController>();
    final busCtrl = context.watch<BusController>();
    
    final isKeyboardOpen = context.select<KeyboardController, bool>((ctrl) => ctrl.isOpen); 
    
    final bgCtrl = context.watch<BackgroundController>();
    final hasCustomBg = bgCtrl.backgroundImagePath != null; 
    
    final isSimpleMode = busCtrl.isSimpleMode;
    // 🌟 監聽語言設定
    final langCtrl = context.watch<LanguageController>();

    final visibleIndices = isSimpleMode ? [0, 2, 4, 5] : [0, 1, 2, 3, 4, 5];

    int navBarIndex = visibleIndices.indexOf(navCtrl.selectedIndex);
    if (navBarIndex == -1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
         navCtrl.changeTab(0);
      });
      navBarIndex = 0;
    }

    // 🌟 替換為動態語言翻譯
    List<BottomNavigationBarItem> buildNavItems() {
      final allItems = {
        0: BottomNavigationBarItem(icon: const Icon(Icons.search), label: langCtrl.tr('tab_search')),
        1: BottomNavigationBarItem(icon: const Icon(Icons.list_alt), label: langCtrl.tr('tab_route')),
        2: BottomNavigationBarItem(icon: const Icon(Icons.directions_bus), label: langCtrl.tr('tab_station')),
        3: BottomNavigationBarItem(icon: const Icon(Icons.map), label: langCtrl.tr('tab_map')),
        4: BottomNavigationBarItem(icon: const Icon(Icons.star), label: langCtrl.tr('tab_favorite')),
        5: BottomNavigationBarItem(icon: const Icon(Icons.settings), label: langCtrl.tr('tab_settings')),
      };
      return visibleIndices.map((idx) => allItems[idx]!).toList();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: hasCustomBg 
                ? Colors.black 
                : (isDark ? Colors.black : const Color(0xFFF5F5F7)), 
          ),
        ),

        if (hasCustomBg)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: bgCtrl.bgBlur > 0 ? bgCtrl.bgBlur : 0.001, 
                sigmaY: bgCtrl.bgBlur > 0 ? bgCtrl.bgBlur : 0.001
              ),
              child: Image.file(
                File(bgCtrl.backgroundImagePath!),
                fit: BoxFit.cover,
              ),
            ),
          ),
          
        if (hasCustomBg)
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.65)),
          ),
        
        Scaffold(
          backgroundColor: Colors.transparent, 
          extendBody: false, 
          body: SafeArea(
            bottom: false, 
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: navCtrl.selectedIndex, 
                    children: [
                      const DashboardScreen(),  
                      isSimpleMode ? const SizedBox.shrink() : const RouteListScreen(),  
                      const BusRouteScreen(),   
                      isSimpleMode ? const SizedBox.shrink() : const MapScreen(),        
                      const FavoritesScreen(),  
                      const SettingsScreen()    
                    ]
                  ),
                ),
                
                if (isKeyboardOpen) const GlobalCustomKeyboard(),
              ],
            ),
          ),

          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CustomBannerAd(),
              _LiquidGlassNavBar(
                isDark: isDark,
                hasCustomBg: hasCustomBg,
                child: BottomNavigationBar(
                  elevation: 0, 
                  backgroundColor: Colors.transparent, 
                  currentIndex: navBarIndex, 
                  onTap: (index) {
                    context.read<BusController>().cancelMapPicking();
                    context.read<KeyboardController>().closeKeyboard(); 
                    context.read<NavigationController>().changeTab(visibleIndices[index]);
                  }, 
                  selectedItemColor: Colors.amber, 
                  unselectedItemColor: isDark 
                      ? Colors.white.withValues(alpha: 0.62) 
                      : Colors.black.withValues(alpha: 0.55), 
                  type: BottomNavigationBarType.fixed, 
                  selectedFontSize: 11,
                  unselectedFontSize: 11,
                  items: buildNavItems(),
                ),
              ),
            ],
          ),
        ),
      ],
    ); 
  }
}

class _LiquidGlassNavBar extends StatelessWidget {
  final bool isDark;
  final bool hasCustomBg;
  final Widget child;

  const _LiquidGlassNavBar({
    required this.isDark,
    required this.hasCustomBg,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final Color tintTop = isDark
        ? Colors.white.withValues(alpha: hasCustomBg ? 0.16 : 0.10)
        : Colors.white.withValues(alpha: 0.72);
    final Color tintMid = isDark
        ? Colors.white.withValues(alpha: hasCustomBg ? 0.06 : 0.04)
        : Colors.white.withValues(alpha: 0.50);
    final Color tintBottom = isDark
        ? Colors.black.withValues(alpha: hasCustomBg ? 0.22 : 0.42)
        : Colors.white.withValues(alpha: 0.38);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.22, 1.0],
              colors: [tintTop, tintMid, tintBottom],
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: isDark ? 0.38 : 0.85),
                width: 0.7,
              ),
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 24,
                right: 24,
                height: 1.4,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.0),
                          Colors.white.withValues(alpha: isDark ? 0.55 : 0.9),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class GlobalCustomKeyboard extends StatelessWidget {
  const GlobalCustomKeyboard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final keyboardCtrl = context.watch<KeyboardController>();
    final busCtrl = context.read<BusController>(); 
    
    final input = keyboardCtrl.routeController.text.toUpperCase();
    
    Set<String> validNext = {};
    List<String> rawRoutes = busCtrl.allRoutesWithDir.map((r) => r.split(' ')[0].toUpperCase()).toSet().toList();

    if (input.isEmpty) {
      validNext = rawRoutes.map((r) => r.isNotEmpty ? r[0] : '').toSet();
    } else {
      for (String r in rawRoutes) {
        if (r.startsWith(input) && r.length > input.length) {
          validNext.add(r[input.length]);
        }
      }
    }

    List<String> validLetters = validNext.where((c) => RegExp(r'[A-Z]').hasMatch(c)).toList()..sort();

    Widget keyButton(String text, {VoidCallback? onTap, bool isEnabled = true, IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.all(4.0),
        child: Material(
          color: isEnabled ? (isDark ? const Color(0xFF2C2C2E) : Colors.white) : (isDark ? const Color(0xFF1C1C1E) : Colors.grey[200]),
          borderRadius: BorderRadius.circular(10),
          elevation: isEnabled ? 2 : 0,
          child: Listener(
            onPointerDown: (_) {
              if (isEnabled && onTap != null) onTap(); 
            },
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: isEnabled ? () {} : null, 
              child: Center(
                child: icon != null
                    ? Icon(icon, color: isEnabled ? (isDark ? Colors.white : Colors.black) : Colors.grey[600], size: 26)
                    : Text(text, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: isEnabled ? (isDark ? Colors.white : Colors.black) : Colors.grey[600])),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 280,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : const Color(0xFFD1D1D6),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                for (var row in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
                  Expanded(child: Row(children: row.map((n) => Expanded(child: keyButton(n, isEnabled: validNext.contains(n), onTap: () => keyboardCtrl.typeChar(n)))).toList())),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: keyButton('', icon: Icons.keyboard_hide, onTap: () => keyboardCtrl.closeKeyboard())),
                      Expanded(child: keyButton('0', isEnabled: validNext.contains('0'), onTap: () => keyboardCtrl.typeChar('0'))),
                      Expanded(child: keyButton('', icon: Icons.backspace_outlined, isEnabled: input.isNotEmpty, onTap: () => keyboardCtrl.backspace())),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: validLetters.isEmpty
                ? Center(child: Icon(Icons.directions_bus, color: isDark ? Colors.white10 : Colors.black12, size: 64))
                : GridView.builder(
                    padding: EdgeInsets.zero, physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.1, mainAxisSpacing: 0, crossAxisSpacing: 0),
                    itemCount: validLetters.length,
                    itemBuilder: (ctx, i) => keyButton(validLetters[i], isEnabled: true, onTap: () => keyboardCtrl.typeChar(validLetters[i])),
                  ),
          ),
        ],
      ),
    );
  }
}