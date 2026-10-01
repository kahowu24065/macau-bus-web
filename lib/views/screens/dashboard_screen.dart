import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/bus_controller.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../controllers/keyboard_controller.dart';
import '../../controllers/language_controller.dart'; 
import '../../services/gps_service.dart';
import '../../services/otp_service.dart';
import '../../utils/route_result_helper.dart';
import '../widgets/routing_bottom_sheet.dart';
import '../widgets/route_liquid_glass_nav.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override 
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<String> _recentSearches = [];
  dynamic _lastFetchedLoc;
  List<dynamic> _nearbyStopsCache = [];
  bool _isFetchingNearby = false;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches(); 
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locCtrl = context.read<LocationController>();
      final busCtrl = context.read<BusController>();
      final langCtrl = context.read<LanguageController>();
      busCtrl.fetchAllRoutes(lang: langCtrl.currentLanguage);
      if (!locCtrl.isFollowingUser) {
        GpsService.toggleGpsAndAutoSelectStop(context, busCtrl, locCtrl, showSnackbar: false);
      }
    });
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

  Future<void> _fetchNearbyStopsFromAPI(double lat, double lng, String lang) async {
    try {
      final stops = await OTPService.fetchNearbyStops(lat: lat, lng: lng);
      if (!mounted) return;
      setState(() {
        _nearbyStopsCache = stops;
        _isFetchingNearby = false;
      });
    } catch (e) {
      debugPrint('Fetch nearby stops error: $e');
      if (mounted) {
        setState(() { _isFetchingNearby = false; });
      }
    }
  }

  void _checkAndFetchNearby(LocationController locCtrl, LanguageController langCtrl) {
    if (!locCtrl.isFollowingUser || locCtrl.userLocation == null) return;
    final currentLoc = locCtrl.userLocation!;
    bool shouldFetch = _lastFetchedLoc == null ||
        _calculateDistance(_lastFetchedLoc!.latitude, _lastFetchedLoc!.longitude, currentLoc.latitude, currentLoc.longitude) > 50;

    if (shouldFetch && !_isFetchingNearby) {
      _isFetchingNearby = true;
      _lastFetchedLoc = currentLoc;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchNearbyStopsFromAPI(currentLoc.latitude, currentLoc.longitude, langCtrl.currentLanguage);
      });
    }
  }

  void _openRoutingPanel() {
    final parentContext = context;
    final busCtrl = parentContext.read<BusController>();
    if (busCtrl.isSimpleMode) return;
    final navCtrl = parentContext.read<NavigationController>();
    final locCtrl = parentContext.read<LocationController>();
    final langCtrl = parentContext.read<LanguageController>();
    
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
            navCtrl.captureRouteForRestore(busCtrl.currentRoute);
            navCtrl.clearNavigation();
            navCtrl.setPlanningRoute(true);
            navCtrl.openMap();
          }, 
          onPickEndOnMap: () { 
            Navigator.pop(sheetContext); 
            busCtrl.startPickingMapEnd();
            navCtrl.captureRouteForRestore(busCtrl.currentRoute);
            navCtrl.clearNavigation();
            navCtrl.setPlanningRoute(true);
            navCtrl.openMap();
          }, 
          onRouteCalculated: (itineraries, destination, onlyGhostsLeft) {
            wasRouteCalculated = true;
            Navigator.pop(sheetContext); 
            busCtrl.clearCustomMapPoints(); 
            if (itineraries.isNotEmpty) {
              if (onlyGhostsLeft) {
                ScaffoldMessenger.of(parentContext).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: parentContext, content: Text(langCtrl.tr('warning_offline')), backgroundColor: Colors.redAccent));
              }
              navCtrl.addHistory(itineraries, destination, onlyGhostsLeft);
              Future.delayed(const Duration(milliseconds: 350), () {
                if (parentContext.mounted) {
                  // 🌟 呼叫共用工具
                  RouteResultHelper.showOTPResultBottomSheet(parentContext, itineraries, destination, navCtrl, langCtrl);
                }
              });
            } else {
              ScaffoldMessenger.of(parentContext).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: parentContext, content: Text(langCtrl.tr('calc_route_failed'))));
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

  Widget _buildSectionTitle(IconData icon, String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 18),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecentSearches(bool isDark, BusController busCtrl, NavigationController navCtrl, LanguageController langCtrl) {
    if (_recentSearches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16, top: 4),
        child: Center(child: Text(langCtrl.tr('no_recent_searches'), style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade600, fontSize: 14))),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (int i = 0; i < _recentSearches.length; i++) ...[
              _buildRecentSearchRow(_recentSearches[i], isDark, busCtrl, navCtrl, langCtrl),
              if (i < _recentSearches.length - 1)
                Divider(height: 1, indent: 72, color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSearchRow(String fullRouteString, bool isDark, BusController busCtrl, NavigationController navCtrl, LanguageController langCtrl) {
    String routeNum = fullRouteString;
    final match = RegExp(r'^([a-zA-Z0-9]+)').firstMatch(fullRouteString);
    if (match != null) {
      routeNum = match.group(1) ?? fullRouteString;
    }

    String routeDesc = langCtrl.tr('macau_bus_route_desc');
    for (String r in busCtrl.allRoutesWithDir) {
      final parts = r.split('|');
      final code = parts.isNotEmpty ? parts[0].trim() : '';
      if (code.toUpperCase() == routeNum.toUpperCase() && parts.length > 1 && parts[1].trim().isNotEmpty) {
        routeDesc = parts[1].trim();
        break;
      }
    }

    return InkWell(
      onTap: () {
        busCtrl.setRoute(routeNum);
        busCtrl.fetchStops();
        navCtrl.clearNavigation();
        navCtrl.changeTab(2);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 52),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2E) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
              ),
              alignment: Alignment.center,
              child: Text(
                routeNum,
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                routeDesc,
                style: TextStyle(color: isDark ? const Color(0xFFC7C7CC) : Colors.black54, fontSize: 13, height: 1.3),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyStopRow(Map<String, dynamic> stop, bool isDark) {
    final stopName = stop['name'].toString().replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
    final dist = (double.tryParse(stop['distance'].toString()) ?? 0).round();
    final routes = ((stop['routes'] as List?) ?? []).map((r) => r.toString()).where((r) => r.isNotEmpty).join(' · ');

    return InkWell(
      onTap: () => _showStopBusesBottomSheet(stop, isDark),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 52),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2E) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
              ),
              alignment: Alignment.center,
              child: Text(
                '${dist}m',
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (routes.isNotEmpty)
                    Text(
                      routes,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isDark ? const Color(0xFFC7C7CC) : Colors.black54, fontSize: 12, height: 1.3),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 18),
          ],
        ),
      ),
    );
  }

  void _showStopBusesBottomSheet(Map<String, dynamic> stopData, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final busCtrl = context.read<BusController>();
        final navCtrl = context.read<NavigationController>();
        final routes = stopData['routes'] as List<dynamic>;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text(stopData['name'] ?? context.read<LanguageController>().tr('unknown_stop'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Code: ${stopData['code'] ?? '-'}', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
              const SizedBox(height: 24),
              
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 2.0, mainAxisSpacing: 10, crossAxisSpacing: 10),
                  itemCount: routes.length,
                  itemBuilder: (context, index) {
                    final route = routes[index].toString();
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx); 
                        busCtrl.setRoute(route);
                        busCtrl.fetchStops();
                        navCtrl.changeTab(2); 
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(color: isDark ? Colors.grey.shade800 : Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.withValues(alpha: 0.5))),
                        alignment: Alignment.center,
                        child: Text(route, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      }
    );
  }

  Widget _buildDynamicNearbyStops(LocationController locCtrl, BusController busCtrl, bool isDark, LanguageController langCtrl) {
    if (!locCtrl.isFollowingUser || locCtrl.userLocation == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(langCtrl.tr('need_location_for_nearby'), style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15))),
      );
    }
    if (_isFetchingNearby && _nearbyStopsCache.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(color: Colors.amber)));
    }
    if (_nearbyStopsCache.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(langCtrl.tr('no_nearby_stops'), style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 15))),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (int i = 0; i < _nearbyStopsCache.length; i++) ...[
              _buildNearbyStopRow(Map<String, dynamic>.from(_nearbyStopsCache[i] as Map), isDark),
              if (i < _nearbyStopsCache.length - 1)
                Divider(height: 1, indent: 72, color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busCtrl = context.watch<BusController>();
    final locCtrl = context.watch<LocationController>();
    final navCtrl = context.read<NavigationController>();
    final keyboardCtrl = context.watch<KeyboardController>(); 
    final langCtrl = context.watch<LanguageController>(); 
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    _checkAndFetchNearby(locCtrl, langCtrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      busCtrl.fetchAllRoutes(lang: langCtrl.currentLanguage);
    });

    final inputText = keyboardCtrl.routeController.text;
    bool showSuggestions = keyboardCtrl.isOpen && inputText.isNotEmpty;
    List<String> routeSuggestions = [];
    if (showSuggestions) {
      final query = inputText.trim().toLowerCase();
      routeSuggestions = busCtrl.allRoutesWithDir.where((r) => r.trimLeft().toLowerCase().startsWith(query)).toList();
    }

    return Scaffold(
      backgroundColor: Colors.transparent, 
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(langCtrl.tr('search_route_title'), style: TextStyle(color: Colors.amber.shade600, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: TextField(
                              controller: keyboardCtrl.routeController, 
                              focusNode: keyboardCtrl.searchFocusNode,  
                              readOnly: true,     
                              showCursor: false,
                              onTap: () { keyboardCtrl.openKeyboard(); },
                              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15, fontWeight: FontWeight.w500), 
                              decoration: InputDecoration(
                                hintText: langCtrl.tr('input_route_hint'), 
                                hintStyle: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.normal), 
                                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20), 
                                suffixIcon: inputText.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey, size: 18), onPressed: () => keyboardCtrl.clearText()) : null, 
                                filled: true, 
                                fillColor: isDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.8),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10), 
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)
                              )
                            )
                          )
                        ),
                        const SizedBox(width: 8),
                        IconButton(icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: isDark ? Colors.amber : Colors.orange), onPressed: () => context.read<ThemeController>().toggleTheme()),
                        IconButton(
                          icon: locCtrl.isLocating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)) : Icon(Icons.my_location, color: locCtrl.isFollowingUser ? Colors.green : Colors.amber),
                          onPressed: () => GpsService.toggleGpsAndAutoSelectStop(context, busCtrl, locCtrl),
                        ),
                        if (!busCtrl.isSimpleMode)
                          IconButton(icon: const Icon(Icons.directions, color: Colors.blueAccent), onPressed: _openRoutingPanel),
                      ]
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    _buildSectionTitle(Icons.access_time, langCtrl.tr('recent_searches'), isDark),
                    _buildRecentSearches(isDark, busCtrl, navCtrl, langCtrl),
                    
                    const SizedBox(height: 16),
                    _buildSectionTitle(Icons.location_on, langCtrl.tr('nearby_stops'), isDark),
                    _buildDynamicNearbyStops(locCtrl, busCtrl, isDark, langCtrl),
                  ],
                ),
              ),
            ],
          ),

          if (showSuggestions && routeSuggestions.isNotEmpty)
            Positioned(
              top: 128, left: 16, right: 16,
              child: Container(
                constraints: BoxConstraints(maxHeight: math.max(100.0, MediaQuery.of(context).size.height - 400)), 
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
                          onTap: () {},
                          onTapDown: (_) {
                            keyboardCtrl.closeKeyboard(); 
                            keyboardCtrl.routeController.text = routeNum;
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
        ],
      ),
    );
  }
}