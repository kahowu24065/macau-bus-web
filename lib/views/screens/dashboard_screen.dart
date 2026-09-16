import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/bus_controller.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../services/gps_service.dart'; 
import '../../models/itinerary.dart';
import '../widgets/routing_bottom_sheet.dart';
import '../widgets/custom_banner_ad.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override 
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _routeController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showSuggestions = false;
  bool _showCustomKeyboard = false;
  
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _loadRecentSearches(); 
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() { _showSuggestions = false; _showCustomKeyboard = false; });
        });
      }
    });
  }

  @override
  void dispose() {
    _routeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches = prefs.getStringList('recent_routes') ?? [];
    });
  }

  Future<void> _addRecentSearch(String routeDesc) async {
    final prefs = await SharedPreferences.getInstance();
    _recentSearches.remove(routeDesc); 
    _recentSearches.insert(0, routeDesc); 
    if (_recentSearches.length > 3) {
      _recentSearches = _recentSearches.sublist(0, 3); 
    }
    await prefs.setStringList('recent_routes', _recentSearches);
    setState(() {});
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - math.cos((lat2 - lat1) * p)/2 + 
              math.cos(lat1 * p) * math.cos(lat2 * p) * 
              (1 - math.cos((lon2 - lon1) * p))/2;
    return 12742 * math.asin(math.sqrt(a)) * 1000; 
  }

  void _openRoutingPanel() {
    final parentContext = context;
    final busCtrl = parentContext.read<BusController>();
    final navCtrl = parentContext.read<NavigationController>();
    final locCtrl = parentContext.read<LocationController>();
    
    bool wasRouteCalculated = false;
    navCtrl.setPlanningRoute(true);

    showModalBottomSheet(
      context: parentContext, 
      isScrollControlled: true, 
      backgroundColor: Theme.of(parentContext).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), 
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom), 
        child: RoutingBottomSheet(
          userLocation: locCtrl.isFollowingUser ? locCtrl.userLocation : null, 
          isLocationActive: locCtrl.isFollowingUser, 
          customMapStart: busCtrl.customMapStart, 
          customMapEnd: busCtrl.customMapEnd, 
          onPickOnMap: () { 
            Navigator.pop(sheetContext); 
            busCtrl.startPickingMapStart();
            navCtrl.clearNavigation();
            navCtrl.setPlanningRoute(true);
            navCtrl.changeTab(3);
          }, 
          onPickEndOnMap: () { 
            Navigator.pop(sheetContext); 
            busCtrl.startPickingMapEnd();
            navCtrl.clearNavigation();
            navCtrl.setPlanningRoute(true);
            navCtrl.changeTab(3);
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
                if (parentContext.mounted) {
                  _showOTPResultBottomSheet(parentContext, itineraries, destination, navCtrl);
                }
              });
            } else {
              ScaffoldMessenger.of(parentContext).showSnackBar(const SnackBar(content: Text('未能計算出合適路線')));
              navCtrl.setPlanningRoute(false);
            }
          }
        )
      )
    ).whenComplete(() { 
      if (!busCtrl.isPickingMapStart && !busCtrl.isPickingMapEnd && !wasRouteCalculated) {
        busCtrl.clearCustomMapPoints();
        navCtrl.setPlanningRoute(false);
      }
    });
  }

  void _showOTPResultBottomSheet(BuildContext context, List<Itinerary> itineraries, String destination, NavigationController navCtrl) {
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
      context: context, isScrollControlled: true,
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
                            Text('導航結果', style: TextStyle(color: Colors.amber[600], fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('前往: $destination', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  indicatorColor: Colors.amber, labelColor: Colors.amber, unselectedLabelColor: Colors.grey,
                  tabs: [Tab(text: '巴士 / 轉乘 (${transitItineraries.length})'), Tab(text: '純步行 (${walkItineraries.length})')],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildItineraryPager(ctx, transitItineraries, isDark, navCtrl, destination),
                      _buildItineraryPager(ctx, walkItineraries, isDark, navCtrl, destination),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => Navigator.pop(ctx), child: Text('關閉', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16))),
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

  Widget _buildItineraryPager(BuildContext context, List<Itinerary> itineraries, bool isDark, NavigationController navCtrl, String destinationName) {
    if (itineraries.isEmpty) return Center(child: Text('沒有相關方案', style: TextStyle(color: Colors.grey[500], fontSize: 16)));
    int currentPage = 0; final PageController pageController = PageController();

    return StatefulBuilder(
      builder: (ctx, setPagerState) {
        int activeSeconds = 0;
        for (var leg in itineraries[currentPage].legs) { activeSeconds += leg.duration; }
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
                    icon: Icon(Icons.chevron_left, color: currentPage > 0 ? (isDark ? Colors.white : Colors.black) : Colors.grey),
                    onPressed: currentPage > 0 ? () => pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut) : null,
                  ),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(text: '方案 ${currentPage + 1} / ${itineraries.length} (約 $activeMinutes 分鐘)', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
                        const TextSpan(text: '  未計算等車', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.normal)),
                      ],
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
                  final it = itineraries[index]; final legs = it.legs;
                  return ListView.separated(
                    itemCount: legs.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                    itemBuilder: (_, i) {
                      final leg = legs[i]; final mode = leg.mode; final legDuration = (leg.duration / 60).round();
                      String fromName = leg.fromName.isNotEmpty ? leg.fromName : '起點';
                      if (fromName.toLowerCase() == 'origin') fromName = '起點';
                      String toName = leg.toName.isNotEmpty ? leg.toName : '終點';
                      if (i == legs.length - 1 && toName.toLowerCase() == 'destination') { toName = destinationName; } else if (toName.toLowerCase() == 'destination') { toName = '終點'; }
                      final routeName = leg.routeName; final etaStr = leg.realtimeEta ?? '未有預計時間';
                      final isGhostBus = etaStr == '未有預計時間' || etaStr == '連線失敗' || etaStr == 'null';

                      if (mode == 'WALK') {
                        num distanceMeters = leg.distance?.round() ?? 0;
                        if (distanceMeters <= 0 && leg.duration > 0) { 
                          double exactMeters = leg.duration / 60 * 80; 
                          distanceMeters = ((exactMeters / 10).round() * 10); 
                        } 
                        else if (distanceMeters > 0) { 
                          distanceMeters = ((distanceMeters / 10).round() * 10); 
                        }
                        final String distanceText = distanceMeters > 0 ? ' ($distanceMeters 米)' : '';
                        
                        return ListTile(
                          leading: const Icon(Icons.directions_walk, color: Colors.blueAccent, size: 28),
                          title: Text('步行至 $toName', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15, fontWeight: FontWeight.bold)),
                          subtitle: Text('約 $legDuration 分鐘$distanceText', style: TextStyle(color: Colors.grey[500])),
                        );
                      } else {
                        return ListTile(
                          leading: Icon(Icons.directions_bus, color: isGhostBus ? Colors.grey : Colors.amber, size: 28),
                          title: Text('乘搭 ${routeName.isNotEmpty ? routeName : '?'} 號線', style: TextStyle(color: isGhostBus ? Colors.grey : Colors.amber, fontWeight: FontWeight.bold, fontSize: 15, decoration: isGhostBus ? TextDecoration.lineThrough : null)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('從 $fromName 上車\n到 $toName 下車 (約 $legDuration 分鐘)', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.4)),
                                const SizedBox(height: 4),
                                Text(isGhostBus ? '🚫 暫無班次 (請考慮其他方案)' : '🔄 實時到站: $etaStr', style: TextStyle(color: isGhostBus ? Colors.redAccent : Colors.greenAccent[700], fontSize: 12, fontWeight: FontWeight.bold)),
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
                width: double.infinity, height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  icon: const Icon(Icons.map, color: Colors.white),
                  label: const Text('在地圖顯示此路線', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final busCtrl = context.read<BusController>();
                    
                    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.amber)));
                    
                    await navCtrl.buildPolylinesFromLegs(itineraries[currentPage].legs);
                    
                    if (!context.mounted) return;
                    
                    navigator.pop(); 
                    navigator.pop(); 
                    navCtrl.changeTab(3); 
                    
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

  Widget _buildCustomKeyboard(bool isDark, BusController busCtrl) {
    final input = _routeController.text.toUpperCase();
    Set<String> validNext = {};

    List<String> rawRoutes = busCtrl.allRoutesWithDir.map((r) {
      return r.split(' ')[0].toUpperCase();
    }).toSet().toList();

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
          color: isEnabled
              ? (isDark ? const Color(0xFF2C2C2E) : Colors.white)
              : (isDark ? const Color(0xFF1C1C1E) : Colors.grey[200]),
          borderRadius: BorderRadius.circular(10),
          elevation: isEnabled ? 2 : 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: isEnabled ? () => onTap?.call() : null,
            child: Center(
              child: icon != null
                  ? Icon(icon, color: isEnabled ? (isDark ? Colors.white : Colors.black) : Colors.grey[600], size: 26)
                  : Text(text, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: isEnabled ? (isDark ? Colors.white : Colors.black) : Colors.grey[600])),
            ),
          ),
        ),
      );
    }

    void handleKeyPress(String char) {
      _routeController.text += char;
      _routeController.selection = TextSelection.fromPosition(TextPosition(offset: _routeController.text.length));
      setState(() => _showSuggestions = true);
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
                  Expanded(child: Row(children: row.map((n) => Expanded(child: keyButton(n, isEnabled: validNext.contains(n), onTap: () => handleKeyPress(n)))).toList())),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: keyButton('', icon: Icons.keyboard_hide, onTap: () { _focusNode.unfocus(); setState(() => _showCustomKeyboard = false); })),
                      Expanded(child: keyButton('0', isEnabled: validNext.contains('0'), onTap: () => handleKeyPress('0'))),
                      Expanded(child: keyButton('', icon: Icons.backspace_outlined, isEnabled: input.isNotEmpty, onTap: () {
                        if (_routeController.text.isNotEmpty) {
                          _routeController.text = _routeController.text.substring(0, _routeController.text.length - 1);
                          _routeController.selection = TextSelection.fromPosition(TextPosition(offset: _routeController.text.length));
                          setState(() => _showSuggestions = _routeController.text.isNotEmpty);
                        }
                      })),
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
                    itemBuilder: (ctx, i) => keyButton(validLetters[i], isEnabled: true, onTap: () => handleKeyPress(validLetters[i])),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 22),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecentSearchCard(String fullRouteString, bool isDark, BusController busCtrl, NavigationController navCtrl) {
    String routeNum = fullRouteString;
    String routeDesc = '';
    
    final match = RegExp(r'^([a-zA-Z0-9]+)(.*)').firstMatch(fullRouteString);
    if (match != null) { 
      routeNum = match.group(1) ?? fullRouteString; 
      routeDesc = match.group(2)?.trim() ?? ''; 
      routeDesc = routeDesc.replaceFirst(RegExp(r'^[\-\|\s]+'), '').trim(); 
      routeDesc = routeDesc.replaceAll('-', '➔');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: InkWell(
        onTap: () {
          busCtrl.setRoute(routeNum); 
          busCtrl.fetchStops(); 
          navCtrl.clearNavigation(); 
          navCtrl.changeTab(2);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 54, height: 42,
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? Colors.white54 : Colors.grey.shade400, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(routeNum, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(routeDesc, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16))),
              // 🌟 已經移除時鐘 Icon 同 SizedBox
              Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNearbyStopCard(String stopName, String stopCode, String distance, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: InkWell(
        onTap: () {}, 
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: isDark ? Colors.white54 : Colors.grey.shade400, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(stopName.isNotEmpty ? stopName[0] : '站', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 22, fontWeight: FontWeight.w300)), 
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stopName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('編號: $stopCode', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(distance, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.amber, size: 18),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 20),
                    ],
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicNearbyStops(LocationController locCtrl, BusController busCtrl, bool isDark) {
    if (!locCtrl.isFollowingUser || locCtrl.userLocation == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('需先開啟定位才能找到附近車站', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15)),
        ),
      );
    }

    if (busCtrl.stopsList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('暫時未能獲取車站數據，請稍後再試', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 15)),
        ),
      );
    }

    final userLoc = locCtrl.userLocation!;
    
    var stopsWithDist = busCtrl.stopsList.where((s) => s.lat != 0.0 && s.lng != 0.0).map((stop) {
      double dist = _calculateDistance(userLoc.latitude, userLoc.longitude, stop.lat, stop.lng);
      return {'stop': stop, 'dist': dist};
    }).toList();

    stopsWithDist.sort((a, b) => (a['dist'] as double).compareTo(b['dist'] as double));
    final nearestStops = stopsWithDist.take(3).toList();

    if (nearestStops.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('附近沒有發現車站', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 15))),
      );
    }

    return Column(
      children: nearestStops.map((data) {
        final stop = data['stop'] as dynamic; 
        final dist = data['dist'] as double;
        String cleanName = stop.name.replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
        return _buildNearbyStopCard(cleanName, stop.code ?? '-', '${dist.round()} m', isDark);
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busCtrl = context.watch<BusController>();
    final locCtrl = context.watch<LocationController>();
    final navCtrl = context.read<NavigationController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    List<String> routeSuggestions = [];
    if (_showSuggestions && _routeController.text.isNotEmpty) {
      final query = _routeController.text.trim().toLowerCase();
      routeSuggestions = busCtrl.allRoutesWithDir
          .where((r) => r.trimLeft().toLowerCase().startsWith(query))
          .toList();
    }

    return Stack(
      children: [
        Container(color: isDark ? Colors.black : const Color(0xFFF5F5F7)),

        Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('尋找路線', style: TextStyle(color: Colors.amber.shade600, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: TextField(
                            controller: _routeController,
                            focusNode: _focusNode,
                            readOnly: true,     
                            showCursor: true,   
                            onTap: () { 
                              setState(() { 
                                _showCustomKeyboard = true; 
                                if (_routeController.text.isNotEmpty) _showSuggestions = true;
                              }); 
                            },
                            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15, fontWeight: FontWeight.w500), 
                            decoration: InputDecoration(
                              hintText: '輸入路線 (例如 1...)', 
                              hintStyle: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.normal), 
                              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20), 
                              suffixIcon: _routeController.text.isNotEmpty 
                                ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey, size: 18), onPressed: () { _routeController.clear(); setState(() { _showSuggestions = false; _showCustomKeyboard = true; }); _focusNode.requestFocus(); })
                                : null, 
                              filled: true, 
                              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white, 
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10), 
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)
                            )
                          )
                        )
                      ),
                      const SizedBox(width: 8), 
                      IconButton(icon: Icon(context.read<ThemeController>().themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode, color: Colors.amber), onPressed: () => context.read<ThemeController>().toggleTheme()), 
                      IconButton(icon: locCtrl.isLocating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)) : Icon(Icons.my_location, color: locCtrl.isFollowingUser ? Colors.greenAccent : Colors.amber), onPressed: () => GpsService.toggleGpsAndAutoSelectStop(context, busCtrl, locCtrl)), 
                      IconButton(icon: const Icon(Icons.directions, color: Colors.blueAccent), onPressed: _openRoutingPanel),
                    ]
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSectionTitle(Icons.access_time, '最近搜尋', isDark),
                  
                  if (_recentSearches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24, top: 12),
                      child: Center(child: Text('暫無搜尋紀錄', style: TextStyle(color: Colors.grey.shade600, fontSize: 15))),
                    )
                  else
                    ..._recentSearches.map((routeData) => _buildRecentSearchCard(routeData, isDark, busCtrl, navCtrl)),
                  
                  const SizedBox(height: 16),
                  _buildSectionTitle(Icons.location_on, '附近車站', isDark),
                  
                  _buildDynamicNearbyStops(locCtrl, busCtrl, isDark),
                ],
              ),
            ),
            // 🌟 加入橫幅廣告 (同其他頁面持平)
            if (!_showCustomKeyboard) const CustomBannerAd(),
          ],
        ),

        if (_showSuggestions && routeSuggestions.isNotEmpty)
          Positioned(
            top: 130, left: 16, right: 16,
            child: Container(
              constraints: BoxConstraints(maxHeight: _showCustomKeyboard ? math.max(100.0, MediaQuery.of(context).size.height - 400) : 350),
              child: Material(
                elevation: 8, borderRadius: BorderRadius.circular(12), color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                child: ListView.separated(
                  shrinkWrap: true, padding: EdgeInsets.zero, itemCount: routeSuggestions.length, separatorBuilder: (ctx, i) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                  itemBuilder: (ctx, i) {
                    final suggestion = routeSuggestions[i]; 
                    String routeNum = suggestion; String routeDesc = '';
                    final match = RegExp(r'^([a-zA-Z0-9]+)(.*)').firstMatch(suggestion);
                    if (match != null) { routeNum = match.group(1) ?? suggestion; routeDesc = match.group(2)?.trim() ?? ''; routeDesc = routeDesc.replaceFirst(RegExp(r'^[\-\|\s]+'), '').trim(); }
                    return InkWell(
                      onTap: () {
                        _focusNode.unfocus(); 
                        setState(() { _showSuggestions = false; _showCustomKeyboard = false; }); 
                        _routeController.text = routeNum;
                        
                        _addRecentSearch(suggestion);
                        
                        busCtrl.setRoute(routeNum); 
                        busCtrl.fetchStops(); 
                        navCtrl.clearNavigation();
                        navCtrl.changeTab(2); 
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.directions_bus, color: Colors.amber, size: 20), const SizedBox(width: 16),
                            SizedBox(width: 55, child: Text(routeNum, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold))),
                            Expanded(child: Text(routeDesc, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          
        if (_showCustomKeyboard)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildCustomKeyboard(isDark, busCtrl), 
          )
      ],
    );
  }
}