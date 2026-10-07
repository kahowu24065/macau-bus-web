import 'dart:async';
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
// Put route_liquid_glass_nav.dart next to custom_banner_ad.dart
import '../widgets/route_liquid_glass_nav.dart';

import '../../controllers/bus_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/keyboard_controller.dart';
import '../../controllers/background_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/purchase_controller.dart';
import '../../utils/easy_read_access.dart';
import '../widgets/preserve_chrome.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Home-shell AdMob banner, including the 50px slot reserved above the tab bar.
///
/// Hidden on the map overlay, the station/stops tab (and the legacy map index
/// that still renders that tab), and while route planning is open. Pro and web
/// never show it. Every other tab keeps the slot.
bool showHomeBannerSlot({
  required bool isWeb,
  required bool isPro,
  required bool showMapView,
  required int selectedIndex,
  required bool isPlanningRoute,
  bool easyReadMode = false,
}) {
  if (isWeb || isPro) return false;
  // Easy Read Mode keeps the banner on the settings tab only.
  if (easyReadMode && selectedIndex != 5) return false;
  if (showMapView || isPlanningRoute) return false;
  if (selectedIndex == 2 || selectedIndex == 3) return false;
  return true;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _bannerOccupiedHeight = 0;

  Future<void> _loadLastSearchedRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRoute = prefs.getString('last_searched_route');

    if (mounted) {
      final busCtrl = context.read<BusController>();
      final lang = context.read<LanguageController>().currentLanguage;
      unawaited(busCtrl.fetchAllRoutes(lang: lang));
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
      // Map is no longer a tab (index 3); open the station page instead.
      context.read<NavigationController>().changeTab(savedIndex == 3 ? 2 : savedIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Narrow listens: Home shell only needs a few fields.
    // Watching whole BusController rebuilt this tree on every ETA tick.
    final selectedIndex = context.select<NavigationController, int>(
      (c) => c.selectedIndex,
    );
    final showMapView = context.select<NavigationController, bool>(
      (c) => c.showMapView,
    );
    final isSimpleMode = context.select<BusController, bool>(
      (c) => c.isSimpleMode,
    );
    final easyRead = EasyReadAccess.enabled(context);
    final bgPath = context.select<BackgroundController, String?>(
      (c) => c.backgroundImagePath,
    );
    final bgBlur = context.select<BackgroundController, double>(
      (c) => c.bgBlur,
    );
    // LanguageController only notifies on locale change — watch is cheap
    // and keeps tab labels in sync without extra ceremony.
    final langCtrl = context.watch<LanguageController>();

    final isKeyboardOpen =
        context.select<KeyboardController, bool>((ctrl) => ctrl.isOpen);

    final hasCustomBg = bgPath != null;

    final visibleIndices = (isSimpleMode || easyRead) ? [0, 2, 4, 5] : [0, 1, 2, 4, 5];

    if (isSimpleMode && showMapView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<NavigationController>().closeMap(
              busCtrl: context.read<BusController>(),
            );
      });
    }

    int navBarIndex = visibleIndices.indexOf(selectedIndex);
    if (navBarIndex == -1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<NavigationController>().changeTab(
              selectedIndex == 3 ? 2 : 0,
            );
      });
      navBarIndex = 0;
    }

    final allSpecs = <int, _NavTabSpec>{
      0: _NavTabSpec(
        icon: Icons.search,
        label: langCtrl.tr('tab_search'),
      ),
      1: _NavTabSpec(
        icon: Icons.list_alt,
        label: langCtrl.tr('tab_route'),
      ),
      2: _NavTabSpec(
        icon: Icons.directions_bus,
        label: langCtrl.tr('tab_station'),
      ),
      4: _NavTabSpec(
        icon: Icons.star,
        label: langCtrl.tr('tab_favorite'),
      ),
      5: _NavTabSpec(
        icon: Icons.settings,
        label: langCtrl.tr('tab_settings'),
      ),
    };

    final navItems =
        visibleIndices.map((idx) => allSpecs[idx]!).toList(growable: false);

    final isPro =
        context.select<PurchaseController, bool>((c) => c.isPro);
    final isPlanningRoute = context.select<NavigationController, bool>(
      (c) => c.isPlanningRoute,
    );
    // Map, station/stops, and route planning: no banner and no reserved gap.
    // Search, route list, favorites, and settings keep the slot.
    final showBannerAd = showHomeBannerSlot(
      isWeb: kIsWeb,
      isPro: isPro,
      showMapView: showMapView,
      selectedIndex: selectedIndex,
      isPlanningRoute: isPlanningRoute,
      easyReadMode: easyRead,
    );
    final bannerH =
        showBannerAd ? RouteLiquidGlassNavStyle.bannerAdHeight : 0.0;

    return BannerSlotHeight(
      height: showBannerAd ? _bannerOccupiedHeight : 0,
      child: Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: isDark
                ? Colors.black
                : (easyRead ? Colors.white : const Color(0xFFF5F5F7)),
          ),
        ),
        if (bgPath != null)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: bgBlur > 0 ? bgBlur : 0.001,
                sigmaY: bgBlur > 0 ? bgBlur : 0.001,
              ),
              child: Image.file(
                File(bgPath),
                fit: BoxFit.cover,
              ),
            ),
          ),
        if (hasCustomBg)
          Positioned.fill(
            child: Container(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.72),
            ),
          ),
        // NOTE: do NOT use Scaffold.bottomNavigationBar — Flutter wraps that
        // slot in an opaque Material (theme canvas/surface), which blocks any
        // glass transparency behind the floating bar.
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final mq = MediaQuery.of(context);
                      final reserve = RouteLiquidGlassNavStyle.bottomReserve(
                        context,
                        bannerHeight: bannerH,
                      );
                      return MediaQuery(
                        data: mq.copyWith(
                          padding: mq.padding.copyWith(bottom: reserve),
                        ),
                        child: Stack(
                          children: [
                            IndexedStack(
                              index: selectedIndex == 3 ? 2 : selectedIndex,
                              children: [
                                const DashboardScreen(),
                                isSimpleMode
                                    ? const SizedBox.shrink()
                                    : const RouteListScreen(),
                                const BusRouteScreen(),
                                const SizedBox.shrink(),
                                const FavoritesScreen(),
                                const SettingsScreen(),
                              ],
                            ),
                            if (showMapView && !isSimpleMode)
                              Positioned.fill(
                                child: MapScreen(
                                  onClose: () {
                                    context.read<NavigationController>().closeMap(
                                      busCtrl: context.read<BusController>(),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (isKeyboardOpen)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: RouteLiquidGlassNavStyle.bottomReserve(
                        context,
                        bannerHeight: 0,
                      ),
                    ),
                    child: const GlobalCustomKeyboard(),
                  ),
              ],
            ),
          ),
        ),
        // Banner + nav live in the Stack (not Scaffold bottom slot).
        if (!isKeyboardOpen)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomBannerAd(
                  visible: showBannerAd,
                  allowInEasyReadMode: selectedIndex == 5,
                  onOccupiedHeight: (h) {
                    if (h == _bannerOccupiedHeight) return;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && h != _bannerOccupiedHeight) {
                        setState(() => _bannerOccupiedHeight = h);
                      }
                    });
                  },
                ),
                // Docked tab-bar footprint. The banner stays above it
                // (Music mini-player), not in the sliver under the capsule.
                SizedBox(
                  height: RouteLiquidGlassNavStyle.bottomReserve(context),
                ),
              ],
            ),
          ),
        PreserveChrome(
          child: RouteLiquidGlassNav(
            selectedIndex: navBarIndex,
            isDark: isDark,
            selectedColor: isDark
                ? kRouteLgAccent
                : const Color.fromARGB(255, 255, 140, 0),
            unselectedColor: easyRead
                ? (isDark ? Colors.white : Colors.black)
                : (isDark
                    ? Colors.white
                    : Colors.black.withValues(alpha: 0.55)),
            items: [
              for (final spec in navItems)
                RouteLiquidGlassNavItem(
                  icon: spec.icon,
                  label: spec.label,
                ),
            ],
            onReselect: (index) {
              // Tapping 路線 again while a category is open -> category list.
              if (visibleIndices[index] == 1) {
                context.read<NavigationController>().closeRouteCategory();
              }
            },
            onChanged: (index) {
              final busCtrl = context.read<BusController>();
              busCtrl.cancelMapPicking();
              context.read<KeyboardController>().closeKeyboard();
              context.read<NavigationController>().changeTab(
                visibleIndices[index],
                busCtrl: busCtrl,
              );
            },
          ),
        ),
      ],
    ),
    );
  }
}

class _NavTabSpec {
  const _NavTabSpec({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class GlobalCustomKeyboard extends StatelessWidget {
  const GlobalCustomKeyboard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final easyRead = EasyReadAccess.enabled(context);

    final keyboardCtrl = context.watch<KeyboardController>();
    final busCtrl = context.read<BusController>();

    final input = keyboardCtrl.routeController.text.toUpperCase();

    Set<String> validNext = {};
    List<String> rawRoutes = busCtrl.allRoutesWithDir
        .map((r) => r.split(' ')[0].toUpperCase())
        .toSet()
        .toList();

    if (input.isEmpty) {
      validNext = rawRoutes.map((r) => r.isNotEmpty ? r[0] : '').toSet();
    } else {
      for (String r in rawRoutes) {
        if (r.startsWith(input) && r.length > input.length) {
          validNext.add(r[input.length]);
        }
      }
    }

    List<String> validLetters = validNext
        .where((c) => RegExp(r'[A-Z]').hasMatch(c))
        .toList()
      ..sort();

    Widget keyButton(String text,
        {VoidCallback? onTap, bool isEnabled = true, IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.all(4.0),
        child: Material(
          color: isEnabled
              ? (isDark ? const Color(0xFF2C2C2E) : Colors.white)
              : (isDark ? const Color(0xFF1C1C1E) : Colors.grey[200]),
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
                    ? Icon(
                        icon,
                        color: isEnabled
                            ? (isDark ? Colors.white : Colors.black)
                            : (easyRead ? (isDark ? Colors.white : Colors.black) : Colors.grey[600]),
                        size: 26,
                      )
                    : Text(
                        text,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: isEnabled
                              ? (isDark ? Colors.white : Colors.black)
                              : (easyRead ? (isDark ? Colors.white : Colors.black) : Colors.grey[600]),
                        ),
                      ),
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
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                for (var row in [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9']
                ])
                  Expanded(
                    child: Row(
                      children: row
                          .map(
                            (n) => Expanded(
                              child: keyButton(
                                n,
                                isEnabled: validNext.contains(n),
                                onTap: () => keyboardCtrl.typeChar(n),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: keyButton(
                          '',
                          icon: Icons.keyboard_hide,
                          onTap: () => keyboardCtrl.closeKeyboard(),
                        ),
                      ),
                      Expanded(
                        child: keyButton(
                          '0',
                          isEnabled: validNext.contains('0'),
                          onTap: () => keyboardCtrl.typeChar('0'),
                        ),
                      ),
                      Expanded(
                        child: keyButton(
                          '',
                          icon: Icons.backspace_outlined,
                          isEnabled: input.isNotEmpty,
                          onTap: () => keyboardCtrl.backspace(),
                        ),
                      ),
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
                ? Center(
                    child: Icon(
                      Icons.directions_bus,
                      color: isDark ? Colors.white10 : Colors.black12,
                      size: 64,
                    ),
                  )
                : GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.1,
                      mainAxisSpacing: 0,
                      crossAxisSpacing: 0,
                    ),
                    itemCount: validLetters.length,
                    itemBuilder: (ctx, i) => keyButton(
                      validLetters[i],
                      isEnabled: true,
                      onTap: () => keyboardCtrl.typeChar(validLetters[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
