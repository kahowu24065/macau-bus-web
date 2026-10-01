import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/itinerary.dart';
import '../../controllers/bus_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/language_controller.dart';
import '../../constants/app_translations.dart';

class RouteResultHelper {
  static void showOTPResultBottomSheet(
    BuildContext context, 
    List<Itinerary> itineraries, 
    String destination, 
    NavigationController navCtrl, 
    LanguageController langCtrl
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<Itinerary> transitItineraries = [];
    List<Itinerary> walkItineraries = [];

    for (var it in itineraries) {
      bool hasTransit = it.legs.any((leg) => leg.mode == 'BUS' || leg.mode == 'TRANSIT');
      if (hasTransit) { 
        transitItineraries.add(it); 
      } else { 
        walkItineraries.add(it); 
      }
    }

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: Colors.amber, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(langCtrl.tr('nav_result'), style: TextStyle(color: Colors.amber[600], fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('${langCtrl.tr('go_to_dest')}${AppTranslations.localizePlaceLabel(destination, langCtrl.tr)}', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  indicatorColor: Colors.amber, labelColor: Colors.amber, unselectedLabelColor: Colors.grey,
                  tabs: [
                    Tab(text: '${langCtrl.tr('bus_transit')} (${transitItineraries.length})'), 
                    Tab(text: '${langCtrl.tr('walk_only')} (${walkItineraries.length})')
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildItineraryPager(ctx, transitItineraries, isDark, navCtrl, destination, langCtrl),
                      _buildItineraryPager(ctx, walkItineraries, isDark, navCtrl, destination, langCtrl),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx), 
                      child: Text(langCtrl.tr('btn_close'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16))
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (navCtrl.isDrawingNavRoute || navCtrl.otpNavigationPolylines.isNotEmpty) {
        return;
      }
      navCtrl.setPlanningRoute(false);
      if (navCtrl.otpNavigationPolylines.isEmpty) {
        if (!context.mounted) return;
        context.read<BusController>().clearCustomMapPoints();
      }
    });
  }

  static Widget _buildItineraryPager(
    BuildContext context, 
    List<Itinerary> itineraries, 
    bool isDark, 
    NavigationController navCtrl, 
    String destinationName, 
    LanguageController langCtrl
  ) {
    if (itineraries.isEmpty) return Center(child: Text(langCtrl.tr('no_route_plan'), style: TextStyle(color: Colors.grey[500], fontSize: 16)));
    
    int currentPage = 0; 
    final PageController pageController = PageController();

    return StatefulBuilder(
      builder: (ctx, setPagerState) {
        int activeSeconds = 0;
        for (var leg in itineraries[currentPage].legs) { activeSeconds += leg.duration; }
        final activeMinutes = (activeSeconds / 60).round();

        // 🌟 獲取翻譯後嘅時間字眼 (例如: "(約 23 分鐘)")
        final totalTimeStr = langCtrl.tr('approx_mins_brackets').replaceAll('@mins', activeMinutes.toString());

        return Column(
          children: [
            Container(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[200],
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left, color: currentPage > 0 ? (isDark ? Colors.white : Colors.black) : Colors.grey),
                    onPressed: currentPage > 0 ? () => pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut) : null,
                  ),
                  
                  // 🌟 修復重點：加入 Expanded，強制過長文字自動換行，防止黃黑間條爆版！
                  Expanded(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${langCtrl.tr('plan_num')}${currentPage + 1} / ${itineraries.length} $totalTimeStr\n', // 加咗 \n 稍作排版優化
                            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 13) // 字體微調
                          ),
                          TextSpan(text: langCtrl.tr('no_wait_time_calc'), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.normal)),
                        ],
                      ),
                    ),
                  ),

                  IconButton(
                    icon: Icon(Icons.chevron_right, color: currentPage < itineraries.length - 1 ? (isDark ? Colors.white : Colors.black) : Colors.grey),
                    onPressed: currentPage < itineraries.length - 1 ? () => pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut) : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pageController,
                onPageChanged: (index) => setPagerState(() => currentPage = index),
                itemCount: itineraries.length,
                itemBuilder: (c, index) {
                  return Consumer<NavigationController>(
                    builder: (context, nav, child) {
                  final it = itineraries[index]; 
                  final legs = it.legs;
                  return ListView.separated(
                    itemCount: legs.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                    itemBuilder: (_, i) {
                      final leg = legs[i]; 
                      final mode = leg.mode; 
                      final legDuration = (leg.duration / 60).round();
                      
                      String startName = langCtrl.tr('map_start_name');
                      String destName = langCtrl.tr('map_dest_name');

                      // 🌟 關鍵：教 UI 呼叫 Model 內建嘅翻譯函數！
                      String rawFromName = leg.getLocalizedFromName(langCtrl.currentLanguage);
                      String fromName = rawFromName.isNotEmpty ? rawFromName : startName;
                      if (fromName.toLowerCase() == 'origin') fromName = startName;
                      
                      // 🌟 關鍵：教 UI 呼叫 Model 內建嘅翻譯函數！
                      String rawToName = leg.getLocalizedToName(langCtrl.currentLanguage);
                      String toName = rawToName.isNotEmpty ? rawToName : destName;
                      fromName = AppTranslations.localizePlaceLabel(fromName, langCtrl.tr);
                      toName = AppTranslations.localizePlaceLabel(toName, langCtrl.tr);
                      if (i == legs.length - 1) {
                        toName = AppTranslations.localizePlaceLabel(destinationName, langCtrl.tr);
                      }
                      
                      final routeName = leg.routeName; 
                      
                      final etaRaw = leg.realtimeEta ?? '';
                      final etaStr = AppTranslations.localizeEtaStatus(
                        etaRaw,
                        langCtrl.tr,
                      );
                      final etaPending = etaRaw.isEmpty;
                      
                      final isNoService = etaStr == langCtrl.tr('no_service_today') ||
                          etaStr == langCtrl.tr('service_ended') ||
                          etaStr == langCtrl.tr('service_not_started') ||
                          etaStr == langCtrl.tr('last_bus_departed') ||
                          etaStr == langCtrl.tr('no_service_ghost');

                      // 🌟 獲取路段嘅翻譯時間 (例如: "約 6 分鐘" 或 "(約 12 分鐘)")
                      final legTimeStr = langCtrl.tr('approx_mins').replaceAll('@mins', legDuration.toString());
                      final legTimeStrBrackets = langCtrl.tr('approx_mins_brackets').replaceAll('@mins', legDuration.toString());

                      if (mode == 'WALK') {
                        num distanceMeters = leg.distance?.round() ?? 0;
                        if (distanceMeters <= 0 && leg.duration > 0) { 
                          double exactMeters = leg.duration / 60 * 80; 
                          distanceMeters = ((exactMeters / 10).round() * 10); 
                        } else if (distanceMeters > 0) { 
                          distanceMeters = ((distanceMeters / 10).round() * 10); 
                        }
                        final String distanceText = distanceMeters > 0 ? ' ($distanceMeters m)' : '';
                        
                        return ListTile(
                          leading: const Icon(Icons.directions_walk, color: Colors.blueAccent, size: 28),
                          title: Text('${langCtrl.tr('walk_to')}$toName', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15, fontWeight: FontWeight.bold)),
                          subtitle: Text('$legTimeStr$distanceText', style: TextStyle(color: Colors.grey[500])),
                        );
                      } else {
                        return ListTile(
                          leading: Icon(Icons.directions_bus, color: isNoService ? Colors.grey : Colors.amber, size: 28),
                          title: Text('${langCtrl.tr('take_bus')}${routeName.isNotEmpty ? routeName : '?'}${langCtrl.tr('bus_line')}', style: TextStyle(color: isNoService ? Colors.grey : Colors.amber, fontWeight: FontWeight.bold, fontSize: 15, decoration: isNoService ? TextDecoration.lineThrough : null)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${langCtrl.tr('board_from')}$fromName\n${langCtrl.tr('alight_at')}$toName${langCtrl.tr('get_off')} $legTimeStrBrackets', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.4)),
                                const SizedBox(height: 4),
                                Text(
                                  isNoService
                                      ? langCtrl.tr('no_service_ghost')
                                      : '${langCtrl.tr('realtime_eta')}${etaPending ? langCtrl.tr('eta_updating') : etaStr}',
                                  style: TextStyle(
                                    color: isNoService ? Colors.redAccent : Colors.greenAccent[700],
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                  );
                    },
                  );
                },
              ),
            ),
            if (!context.read<BusController>().isSimpleMode)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  icon: const Icon(Icons.map, color: Colors.white),
                  label: Text(langCtrl.tr('show_on_map_btn'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final busCtrl = context.read<BusController>();
                    final selectedLegs = itineraries[currentPage].legs;

                    navCtrl.captureRouteForRestore(busCtrl.currentRoute);
                    busCtrl.stopsList.clear();
                    busCtrl.gpxRoutePoints.clear();

                    nav.pop();
                    final drawFuture = navCtrl.buildPolylinesFromLegs(selectedLegs);
                    if (!busCtrl.isSimpleMode) {
                      navCtrl.openMap();
                    }
                    await drawFuture;

                    if (navCtrl.navBusRoutes.isNotEmpty) {
                      busCtrl.setRoute(navCtrl.navBusRoutes.first);
                      busCtrl.fetchStops(keepNavigation: true);
                    }
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}