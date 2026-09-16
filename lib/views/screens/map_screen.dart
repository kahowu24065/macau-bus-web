import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;
import '../../controllers/bus_controller.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../models/itinerary.dart';
import '../../services/gps_service.dart';
import '../widgets/routing_bottom_sheet.dart';
import '../widgets/custom_banner_ad.dart'; 

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  late BusController _busCtrl;

  @override
  void initState() {
    super.initState();
    _busCtrl = context.read<BusController>();
    _busCtrl.addListener(_onBusStateChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerMapOnRoute();
    });
  }

  void _onBusStateChanged() {
    if (_busCtrl.pendingAlarmTitle != null && mounted) {
      final title = _busCtrl.pendingAlarmTitle!;
      final body = _busCtrl.pendingAlarmBody ?? '';

      _busCtrl.clearPendingAlarm();
      final isDark = Theme.of(context).brightness == Brightness.dark;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.notifications_active,
                color: Colors.amber,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            body,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                '收到',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _busCtrl.removeListener(_onBusStateChanged);
    super.dispose();
  }

  void _centerMapOnRoute() {
    final busCtrl = context.read<BusController>();
    if (busCtrl.stopsList.isNotEmpty) {
      final validStop = busCtrl.stopsList.firstWhere(
        (s) => s.lat != 0.0 && s.lng != 0.0,
        orElse: () => busCtrl.stopsList.first,
      );
      if (validStop.lat != 0.0 && validStop.lng != 0.0) {
        _mapController.move(LatLng(validStop.lat, validStop.lng), 14.5);
      }
    }
  }

  void _moveToSelectedStop(BusController busCtrl) {
    LatLng? coord = busCtrl.getSelectedStopCoordinate();
    if (coord != null) {
      _mapController.move(coord, 16.5);
    }
  }

  void _openRoutingHistory(NavigationController navCtrl) {
    if (navCtrl.routingHistory.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暫無導航紀錄')));
      return;
    }
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parentContext = context; 
    
    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    '🕒 導航歷史紀錄',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: navCtrl.routingHistory.length,
                      separatorBuilder: (ctx, i) => Divider(
                        color: isDark ? const Color(0xFF333333) : Colors.grey[300],
                        height: 1,
                      ),
                      itemBuilder: (ctx, i) {
                        final item = navCtrl.routingHistory[i];
                        return ListTile(
                          leading: const Icon(Icons.history, color: Colors.grey),
                          title: Text(
                            '前往: ${item['destination']}',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            '${(item['itineraries'] as List).length} 個路線方案',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: Colors.grey,
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext); 
                            navCtrl.setPlanningRoute(true); 
                            Future.delayed(const Duration(milliseconds: 350), () {
                              if (parentContext.mounted) {
                                List<Itinerary> itins = item['itineraries'] as List<Itinerary>;
                                _showOTPResultBottomSheet(
                                  parentContext,
                                  itins,
                                  item['destination'].toString(),
                                  navCtrl,
                                );
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showOTPResultBottomSheet(
    BuildContext context,
    List<Itinerary> itineraries,
    String destination,
    NavigationController navCtrl,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<Itinerary> transitItineraries = [];
    List<Itinerary> walkItineraries = [];

    for (var it in itineraries) {
      bool hasTransit = it.legs.any(
        (leg) => leg.mode == 'BUS' || leg.mode == 'TRANSIT',
      );
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                            Text(
                              '導航結果',
                              style: TextStyle(
                                color: Colors.amber[600],
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '前往: $destination',
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  indicatorColor: Colors.amber,
                  labelColor: Colors.amber,
                  unselectedLabelColor: Colors.grey,
                  tabs: [
                    Tab(text: '巴士 / 轉乘 (${transitItineraries.length})'),
                    Tab(text: '純步行 (${walkItineraries.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildItineraryPager(
                        ctx,
                        transitItineraries,
                        isDark,
                        navCtrl,
                        destination,
                      ),
                      _buildItineraryPager(
                        ctx,
                        walkItineraries,
                        isDark,
                        navCtrl,
                        destination,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        '關閉',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      navCtrl.setPlanningRoute(false);
      if (navCtrl.otpNavigationPolylines.isEmpty) {
        if (!context.mounted) return;
        context.read<BusController>().clearCustomMapPoints();
      }
    });
  }

  Widget _buildItineraryPager(
    BuildContext context,
    List<Itinerary> itineraries,
    bool isDark,
    NavigationController navCtrl,
    String destinationName,
  ) {
    if (itineraries.isEmpty) {
      return Center(
        child: Text(
          '沒有相關方案',
          style: TextStyle(color: Colors.grey[500], fontSize: 16),
        ),
      );
    }

    int currentPage = 0;
    final PageController pageController = PageController();

    return StatefulBuilder(
      builder: (ctx, setPagerState) {
        int activeSeconds = 0;
        for (var leg in itineraries[currentPage].legs) {
          activeSeconds += leg.duration;
        }
        final activeMinutes = (activeSeconds / 60).round();

        return Column(
          children: [
            Container(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[200],
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.chevron_left,
                      color: currentPage > 0
                          ? (isDark ? Colors.white : Colors.black)
                          : Colors.grey,
                    ),
                    onPressed: currentPage > 0
                        ? () => pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          )
                        : null,
                  ),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '方案 ${currentPage + 1} / ${itineraries.length} (約 $activeMinutes 分鐘)',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const TextSpan(
                          text: '  未計算等車',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.chevron_right,
                      color: currentPage < itineraries.length - 1
                          ? (isDark ? Colors.white : Colors.black)
                          : Colors.grey,
                    ),
                    onPressed: currentPage < itineraries.length - 1
                        ? () => pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          )
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pageController,
                onPageChanged: (index) =>
                    setPagerState(() => currentPage = index),
                itemCount: itineraries.length,
                itemBuilder: (c, index) {
                  final it = itineraries[index];
                  final legs = it.legs;

                  return ListView.separated(
                    itemCount: legs.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                    itemBuilder: (_, i) {
                      final leg = legs[i];
                      final mode = leg.mode;
                      final legDuration = (leg.duration / 60).round();
                      
                      String fromName = leg.fromName.isNotEmpty ? leg.fromName : '起點';
                      if (fromName.toLowerCase() == 'origin') fromName = '起點';
                      
                      String toName = leg.toName.isNotEmpty ? leg.toName : '終點';
                      if (i == legs.length - 1 && toName.toLowerCase() == 'destination') {
                        toName = destinationName;
                      } else if (toName.toLowerCase() == 'destination') {
                        toName = '終點';
                      }

                      final routeName = leg.routeName;
                      final etaStr = leg.realtimeEta ?? '未有預計時間';
                      final isGhostBus =
                          etaStr == '未有預計時間' ||
                          etaStr == '連線失敗' ||
                          etaStr == 'null';

                      if (mode == 'WALK') {
                        int distanceMeters = leg.distance?.round() ?? 0;
                        if (distanceMeters <= 0 && leg.duration > 0) {
                          double exactMeters = leg.duration / 60 * 80;
                          distanceMeters = ((exactMeters / 10).round() * 10);
                        } else if (distanceMeters > 0) {
                          distanceMeters = ((distanceMeters / 10).round() * 10);
                        }
                        
                        final String distanceText = distanceMeters > 0 ? ' ($distanceMeters 米)' : '';

                        return ListTile(
                          leading: const Icon(
                            Icons.directions_walk,
                            color: Colors.blueAccent,
                            size: 28,
                          ),
                          title: Text(
                            '步行至 $toName',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            '約 $legDuration 分鐘$distanceText',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        );
                      } else {
                        return ListTile(
                          leading: Icon(
                            Icons.directions_bus,
                            color: isGhostBus ? Colors.grey : Colors.amber,
                            size: 28,
                          ),
                          title: Text(
                            '乘搭 ${routeName.isNotEmpty ? routeName : '?'} 號線',
                            style: TextStyle(
                              color: isGhostBus ? Colors.grey : Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              decoration: isGhostBus
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '從 $fromName 上車\n到 $toName 下車 (約 $legDuration 分鐘)',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isGhostBus
                                      ? '🚫 暫無班次 (請考慮其他方案)'
                                      : '🔄 實時到站: $etaStr',
                                  style: TextStyle(
                                    color: isGhostBus
                                        ? Colors.redAccent
                                        : Colors.greenAccent[700],
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.map, color: Colors.white),
                  label: const Text(
                    '在地圖顯示此路線',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final busCtrl = context.read<BusController>();
                    
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => const Center(
                        child: CircularProgressIndicator(color: Colors.amber),
                      ),
                    );
                    
                    busCtrl.stopsList.clear();
                    busCtrl.gpxRoutePoints.clear();
                    
                    await navCtrl.buildPolylinesFromLegs(
                      itineraries[currentPage].legs,
                    );
                    
                    if (!context.mounted) return;
                    
                    navigator.pop();
                    navigator.pop();
                    navCtrl.changeTab(2);
                    
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

  void _openRoutingPanel() {
    final busCtrl = context.read<BusController>();
    final navCtrl = context.read<NavigationController>();
    final locCtrl = context.read<LocationController>();
    final parentContext = context; 

    bool wasRouteCalculated = false;
    navCtrl.setPlanningRoute(true); 

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Theme.of(parentContext).brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: RoutingBottomSheet(
          // 🌟 雙重保險：如果定位掣係熄嘅，連「最後已知位置」都唔會傳畀面板，徹底斷絕自動填寫！
          userLocation: locCtrl.isFollowingUser ? locCtrl.userLocation : null,
          isLocationActive: locCtrl.isFollowingUser,
          customMapStart: busCtrl.customMapStart,
          customMapEnd: busCtrl.customMapEnd,
          onPickOnMap: () {
            Navigator.pop(sheetContext);
            busCtrl.startPickingMapStart();
            navCtrl.clearNavigation(); 
            navCtrl.setPlanningRoute(true);
          },
          onPickEndOnMap: () {
            Navigator.pop(sheetContext);
            busCtrl.startPickingMapEnd();
            navCtrl.clearNavigation(); 
            navCtrl.setPlanningRoute(true);
          },
          onRouteCalculated: (itineraries, destination, onlyGhostsLeft) {
            wasRouteCalculated = true;
            Navigator.pop(sheetContext); 
            
            busCtrl.clearCustomMapPoints(); 
            
            if (itineraries.isNotEmpty) {
              if (onlyGhostsLeft) {
                ScaffoldMessenger.of(parentContext).showSnackBar(const SnackBar(content: Text('⚠️ 警告：目前建議路線可能已收車或不設服務'), backgroundColor: Colors.redAccent));
              }
              navCtrl.addHistory(itineraries, destination, onlyGhostsLeft);
              
              Future.delayed(const Duration(milliseconds: 350), () {
                if (mounted) {
                  _showOTPResultBottomSheet(
                    context, 
                    itineraries,
                    destination,
                    navCtrl,
                  );
                }
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未能計算出合適路線')));
              navCtrl.setPlanningRoute(false);
            }
          },
        ),
      ),
    ).whenComplete(() {
      if (!busCtrl.isPickingMapStart && !busCtrl.isPickingMapEnd && !wasRouteCalculated) {
        busCtrl.clearCustomMapPoints();
        navCtrl.setPlanningRoute(false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final busCtrl = context.watch<BusController>();
    final locCtrl = context.watch<LocationController>();
    final navCtrl = context.watch<NavigationController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final currentTerminal = busCtrl.currentDirection == 0
        ? busCtrl.outboundTerminal
        : busCtrl.inboundTerminal;
        
    bool isNavigating = navCtrl.otpNavigationPolylines.isNotEmpty;
    bool isPicking = busCtrl.isPickingMapStart || busCtrl.isPickingMapEnd;
    
    bool shouldHideOriginalRoute = isNavigating || isPicking || navCtrl.isPlanningRoute;

    // 🌟 保險：如果閂咗定位追蹤，就唔好當「最後已知位置」係有效嘅地圖中心點
    LatLng mapCenter = (locCtrl.isFollowingUser && locCtrl.userLocation != null) 
        ? locCtrl.userLocation! 
        : const LatLng(22.1987, 113.5439);
        
    if (!shouldHideOriginalRoute && busCtrl.stopsList.isNotEmpty) {
      final firstValid = busCtrl.stopsList.firstWhere(
        (s) => s.lat != 0.0 && s.lng != 0.0,
        orElse: () => busCtrl.stopsList.first,
      );
      if (firstValid.lat != 0.0) {
        mapCenter = LatLng(firstValid.lat, firstValid.lng);
      }
    }

    final List<Marker> stopMarkers = [];
    if (!shouldHideOriginalRoute) {
      stopMarkers.addAll(
        busCtrl.stopsList.where((s) => s.lat != 0.0).map((stop) {
          bool isSelected = stop.seq == busCtrl.selectedStopSeq;
          return Marker(
            point: LatLng(stop.lat, stop.lng),
            width: isSelected ? 32 : 26,
            height: isSelected ? 32 : 26,
            child: GestureDetector(
              onTap: () {
                busCtrl.selectStop(stop.seq);
                busCtrl.fetchBusETA();
                _moveToSelectedStop(busCtrl);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('站點 ${stop.seq}: ${stop.name}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.amber : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color.fromARGB(255, 114, 0, 162),
                    width: 2.5,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 2),
                  ],
                ),
                child: Text(
                  '${stop.seq}',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: isSelected ? 13 : 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }),
      );
    }

    final List<Marker> busMarkers = [];
    int actualMapBusCount = 0;
    if (!shouldHideOriginalRoute) {
      busMarkers.addAll(
        busCtrl.allBusesList.map((bus) {
          LatLng? displayLoc = busCtrl.snapBusToStop(bus);
          if (displayLoc == null) return null;

          actualMapBusCount++;
          
          bool hasRawGps = (bus.lat != 0.0 && bus.lng != 0.0);
          bool isAtStop = false;
          
          if (hasRawGps && bus.currentStopSeq > 0 && bus.speed < 5) {
            int stopIdx = busCtrl.stopsList.indexWhere((s) => s.seq == bus.currentStopSeq);
            if (stopIdx != -1) {
              final stop = busCtrl.stopsList[stopIdx];
              final dist = const Distance().as(LengthUnit.Meter, displayLoc, LatLng(stop.lat, stop.lng));
              if (dist <= 50) {
                isAtStop = true;
              }
            }
          }

          Color bgColor;
          String text;
          Color textColor = Colors.black;

          if (!hasRawGps) {
            bgColor = Colors.grey.shade300; 
            text = '${bus.busLicense}\n獲取中';
            textColor = Colors.black54;
          } else if (isAtStop) {
            bgColor = Colors.orangeAccent;
            text = '${bus.busLicense}\n已到站';
          } else {
            bgColor = Colors.amber;
            text = '${bus.busLicense}\n${bus.speed.toInt()}km/h';
          }

          return Marker(
            point: displayLoc,
            width: 85,
            height: 56,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
                Icon(
                  Icons.directions_bus,
                  color: bgColor,
                  size: 20,
                ),
              ],
            ),
          );
        }).whereType<Marker>(),
      );
    }

    final List<Marker> extraMarkers = [];
    // 🌟 核心修復：只有喺「開緊定位追蹤」嘅情況下，地圖先會顯示嗰粒代表用家嘅藍色點！
    if (locCtrl.userLocation != null && locCtrl.isFollowingUser) {
      extraMarkers.add(
        Marker(
          point: locCtrl.userLocation!,
          width: 48,
          height: 48,
          child: Transform.rotate(
            angle: locCtrl.userHeading * (math.pi / 180),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 0,
                  child: Icon(
                    Icons.navigation,
                    color: Colors.blueAccent.shade700,
                    size: 28,
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (busCtrl.customMapStart != null) {
      extraMarkers.add(
        Marker(
          point: busCtrl.customMapStart!,
          width: 45,
          height: 45,
          child: const Column(
            children: [Icon(Icons.location_on, color: Colors.green, size: 36)],
          ),
        ),
      );
    }
    if (busCtrl.customMapEnd != null) {
      extraMarkers.add(
        Marker(
          point: busCtrl.customMapEnd!,
          width: 45,
          height: 45,
          child: const Column(
            children: [
              Icon(Icons.location_on, color: Colors.redAccent, size: 36),
            ],
          ),
        ),
      );
    }
    if (navCtrl.navStartPt != null && isNavigating) {
      extraMarkers.add(
        Marker(
          point: navCtrl.navStartPt!,
          width: 28,
          height: 28,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
            ),
            child: const Text(
              'S',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
    }
    if (navCtrl.navEndPt != null && isNavigating) {
      extraMarkers.add(
        Marker(
          point: navCtrl.navEndPt!,
          width: 28,
          height: 28,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
            ),
            child: const Text(
              'E',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
    }

    if (isNavigating &&
        navCtrl.navBusLegsInfo.isNotEmpty &&
        navCtrl.activeBusLegIndex < navCtrl.navBusLegsInfo.length) {
      final RouteLeg currentLeg =
          navCtrl.navBusLegsInfo[navCtrl.activeBusLegIndex];
      extraMarkers.add(
        Marker(
          point: LatLng(currentLeg.fromLat, currentLeg.fromLon),
          width: 34,
          height: 34,
          child: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    currentLeg.boardingStopSeq != null
                        ? '🟢 上車點: 第 ${currentLeg.boardingStopSeq} 站 (${currentLeg.fromName})'
                        : '🟢 上車點: ${currentLeg.fromName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.green.shade700,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 4),
                ],
              ),
              child: const Text(
                '上',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      );
      extraMarkers.add(
        Marker(
          point: LatLng(currentLeg.toLat, currentLeg.toLon),
          width: 34,
          height: 34,
          child: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    currentLeg.alightStopSeq != null
                        ? '🔴 落車點: 第 ${currentLeg.alightStopSeq} 站 (${currentLeg.toName})'
                        : '🔴 落車點: ${currentLeg.toName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.red.shade700,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 4),
                ],
              ),
              child: const Text(
                '落',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final List<Color> busColors = [
      Colors.orange,
      Colors.greenAccent,
      Colors.purpleAccent,
    ];

    String stopsDisplay = '站點數: ${busCtrl.stopsList.length}';
    if (isNavigating &&
        navCtrl.navBusLegsInfo.isNotEmpty &&
        navCtrl.activeBusLegIndex < navCtrl.navBusLegsInfo.length) {
      final RouteLeg currentLeg =
          navCtrl.navBusLegsInfo[navCtrl.activeBusLegIndex];
      if (currentLeg.boardingStopSeq != null &&
          currentLeg.alightStopSeq != null) {
        int rideCount =
            (currentLeg.alightStopSeq! - currentLeg.boardingStopSeq!).abs();
        stopsDisplay = '乘搭站數: $rideCount';
      }
    }

    return Column(
      children: [
        if (!isPicking && busCtrl.currentRoute.isNotEmpty)
          Container(
            color: isDark ? Colors.black : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '路線 ${busCtrl.currentRoute} 往 $currentTerminal',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.swap_calls,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      tooltip: '切換對頭線方向',
                      onPressed: () {
                        busCtrl.toggleDirection();
                        busCtrl.fetchStops();
                        navCtrl.clearNavigation();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.amber),
                      onPressed: () => busCtrl.fetchBusETA(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (navCtrl.navBusRoutes.isNotEmpty && isNavigating)
          Container(
            height: 40,
            color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[200],
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: navCtrl.navBusRoutes.length,
              itemBuilder: (context, index) {
                final routeName = navCtrl.navBusRoutes[index];
                final isActive = navCtrl.activeBusLegIndex == index;
                final tabColor = busColors[index % busColors.length];
                return InkWell(
                  onTap: () {
                    navCtrl.setActiveBusLeg(index);
                    busCtrl.setRoute(routeName);
                    busCtrl.fetchStops(keepNavigation: true);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: isActive
                          ? tabColor.withValues(alpha: 0.2)
                          : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: isActive ? tabColor : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      children: [
                        Icon(
                          Icons.directions_bus,
                          size: 16,
                          color: isActive ? tabColor : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '第 ${index + 1} 程: $routeName',
                          style: TextStyle(
                            color: isActive ? tabColor : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: mapCenter,
                  initialZoom: 14.5,
                  onTap: (tapPosition, point) {
                    if (busCtrl.isPickingMapStart) {
                      busCtrl.setCustomMapStart(point);
                      _openRoutingPanel();
                    } else if (busCtrl.isPickingMapEnd) {
                      busCtrl.setCustomMapEnd(point);
                      _openRoutingPanel();
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.macau.bus_app',
                    tileProvider: CachedTileProvider(),
                  ),
                  PolylineLayer(
                    polylines: [
                      if (navCtrl.otpNavigationPolylines.isNotEmpty)
                        ...navCtrl.otpNavigationPolylines
                      else if (!shouldHideOriginalRoute && busCtrl.gpxRoutePoints.isNotEmpty)
                        Polyline(
                          points: busCtrl.gpxRoutePoints,
                          strokeWidth: 5.0,
                          color: const Color.fromARGB(255, 114, 0, 162),
                        )
                      else if (!shouldHideOriginalRoute && busCtrl.routePoints.isNotEmpty)
                        Polyline(
                          points: busCtrl.routePoints,
                          strokeWidth: 5.0,
                          color: const Color.fromARGB(255, 114, 0, 162),
                        ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [...stopMarkers, ...busMarkers, ...extraMarkers],
                  ),
                ],
              ),
              if (busCtrl.isPickingMapStart || busCtrl.isPickingMapEnd)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Material(
                    color: busCtrl.isPickingMapStart
                        ? Colors.amber
                        : Colors.redAccent,
                    borderRadius: BorderRadius.circular(8),
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.touch_app,
                            color: busCtrl.isPickingMapStart
                                ? Colors.black
                                : Colors.white,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              busCtrl.isPickingMapStart
                                  ? '請在地圖上點擊選擇「起點」'
                                  : '請在地圖上點擊選擇「終點」',
                              style: TextStyle(
                                color: busCtrl.isPickingMapStart
                                    ? Colors.black
                                    : Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              busCtrl.cancelMapPicking();
                              _openRoutingPanel();
                            },
                            child: Icon(
                              Icons.close,
                              color: busCtrl.isPickingMapStart
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (busCtrl.isLoadingStops)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.amber),
                        SizedBox(height: 12),
                        Text(
                          '正載入實時數據...',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!isPicking && navCtrl.routingHistory.isNotEmpty)
                Positioned(
                  bottom: 50,
                  left: 16,
                  child: FloatingActionButton(
                    heroTag: 'history_fab',
                    backgroundColor: isDark
                        ? const Color(0xFF2A2A2A)
                        : Colors.white,
                    onPressed: () => _openRoutingHistory(navCtrl),
                    tooltip: '導航紀錄',
                    child: const Icon(Icons.history, color: Colors.amber),
                  ),
                ),
              Positioned(
                bottom: 50,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!shouldHideOriginalRoute && busCtrl.selectedStopSeq != null) ...[
                      FloatingActionButton(
                        heroTag: 'go_to_stop_fab',
                        backgroundColor: Colors.white,
                        onPressed: () => _moveToSelectedStop(busCtrl),
                        tooltip: '跳轉至選定車站',
                        child: const Icon(
                          Icons.pin_drop,
                          color: Color.fromARGB(255, 114, 0, 162),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FloatingActionButton(
                      heroTag: 'gps_fab',
                      backgroundColor: locCtrl.isFollowingUser
                          ? Colors.green
                          : Colors.amber,
                      onPressed: () => GpsService.toggleGpsAndAutoSelectStop(context, busCtrl, locCtrl),
                      child: locCtrl.isLocating
                          ? const CircularProgressIndicator(color: Colors.black)
                          : Icon(
                              locCtrl.isFollowingUser
                                  ? Icons.explore
                                  : Icons.my_location,
                              color: locCtrl.isFollowingUser
                                  ? Colors.white
                                  : Colors.black,
                            ),
                    ),
                  ],
                ),
              ),
              if (!isPicking && !navCtrl.isPlanningRoute)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: (isDark ? Colors.black : Colors.white).withValues(
                      alpha: 0.85,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text(
                          stopsDisplay,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '營運中: ${busCtrl.allBusesList.length} 輛 (地圖顯示: $actualMapBusCount)',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (busCtrl.stopsList.isEmpty && !busCtrl.isLoadingStops)
                          InkWell(
                            onTap: () => busCtrl.fetchStops(),
                            child: const Text(
                              '點擊重試連線',
                              style: TextStyle(
                                color: Colors.amber,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // 🌟 新增：指南針 (置於右上角)
              Positioned(
                top: 60, 
                right: 16, 
                child: StreamBuilder(
                  stream: _mapController.mapEventStream, 
                  builder: (context, snapshot) {
                    // 獲取當前地圖旋轉角度
                    // ⚠️ 注意：如果你用緊較舊版本嘅 flutter_map 導致 .camera 報錯，請將下面嗰行改為 final double rotation = _mapController.rotation;
                    final double rotation = _mapController.camera.rotation; 
                    
                    // 如果地圖已經向住正北 (0度)，自動隱藏指南針保持畫面簡潔
                    if (rotation == 0.0) return const SizedBox.shrink(); 

                    return Material(
                      elevation: 4,
                      shape: const CircleBorder(),
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          // 點擊指南針，地圖重置轉向正北 (0度)
                          _mapController.rotate(0.0);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Transform.rotate(
                            // 將角度轉換為 Radian (弧度)
                            angle: -rotation * (math.pi / 180),
                            child: const Icon(Icons.navigation, color: Color.fromARGB(255, 255, 68, 68), size: 24),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const CustomBannerAd(),
      ],
    );
  }
}

class CachedTileProvider extends TileProvider {
  CachedTileProvider(); 

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(
      getTileUrl(coordinates, options),
    );
  }
}