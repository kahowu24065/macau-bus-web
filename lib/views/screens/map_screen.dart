import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import '../../constants/feature_flags.dart';
import '../../controllers/bus_controller.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/language_controller.dart'; 
import '../../models/bus.dart';
import '../../models/itinerary.dart';
import '../../services/gps_service.dart';
import '../../utils/route_result_helper.dart'; // 🌟 引入共用工具
import '../widgets/routing_bottom_sheet.dart';
import '../widgets/route_liquid_glass_nav.dart';
import '../widgets/fit_marquee_text.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.onClose});
  final VoidCallback? onClose;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  late BusController _busCtrl;
  late NavigationController _navCtrl;
  bool _mapReady = false;
  int _fittedPolySig = 0;
  Timer? _tileKickTimer;
  Timer? _motionTimer;
  double? _labelZoom;
  double? _labelRotation;

  @override
  void initState() {
    super.initState();
    _busCtrl = context.read<BusController>();
    _navCtrl = context.read<NavigationController>();
    _busCtrl.addListener(_onBusStateChanged);
    _navCtrl.addListener(_onNavChanged);
    _motionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      if (_busCtrl.advanceBusMotion()) setState(() {});
    });
  }

  void _onBusStateChanged() {
    if (_busCtrl.pendingAlarmTitle != null && mounted) {
      final title = _busCtrl.pendingAlarmTitle!;
      final body = _busCtrl.pendingAlarmBody ?? '';

      _busCtrl.clearPendingAlarm();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final langCtrl = context.read<LanguageController>();

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.amber, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold))),
            ],
          ),
          content: Text(body, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(langCtrl.tr('received'), style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _tileKickTimer?.cancel();
    _motionTimer?.cancel();
    _busCtrl.removeListener(_onBusStateChanged);
    _navCtrl.removeListener(_onNavChanged);
    super.dispose();
  }

  void _onNavChanged() {
    if (!_mapReady || !mounted) return;
    final sig = _polylineSignature(_navCtrl);
    if (sig == 0 || sig == _fittedPolySig) return;
    _fittedPolySig = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshMapCamera(fitRoute: true);
    });
  }

  int _polylineSignature(NavigationController nav) {
    if (nav.otpNavigationPolylines.isEmpty) return 0;
    final first = nav.otpNavigationPolylines.first.points;
    final last = nav.otpNavigationPolylines.last.points;
    return Object.hash(
      nav.otpNavigationPolylines.length,
      first.isEmpty ? 0 : first.first.latitude,
      last.isEmpty ? 0 : last.last.longitude,
    );
  }

  void _onMapReady() {
    _mapReady = true;
    _scheduleTileKicks();
  }

  /// TileLayer often skips the first layout (0-size / sheet still closing).
  /// A camera event is required before OSM tiles actually download.
  void _scheduleTileKicks() {
    _tileKickTimer?.cancel();
    void kick({required bool fitRoute}) {
      if (mounted) _refreshMapCamera(fitRoute: fitRoute);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => kick(fitRoute: true));
    _tileKickTimer = Timer(const Duration(milliseconds: 320), () {
      kick(fitRoute: true);
    });
  }

  void _refreshMapCamera({required bool fitRoute}) {
    if (!_mapReady || !mounted) return;
    try {
      if (fitRoute) {
        final nav = context.read<NavigationController>();
        final busCtrl = context.read<BusController>();
        final pts = <LatLng>[
          for (final line in nav.otpNavigationPolylines) ...line.points,
        ];
        if (pts.length >= 2) {
          _fittedPolySig = _polylineSignature(nav);
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(pts),
              padding: const EdgeInsets.all(56),
              maxZoom: 16,
            ),
          );
          return;
        }
        final selected = busCtrl.getSelectedStopCoordinate();
        if (selected != null) {
          _nudgeCamera(selected, 16.5);
          return;
        }
        if (busCtrl.stopsList.isNotEmpty) {
          final validStop = busCtrl.stopsList.firstWhere(
            (s) => s.lat != 0.0 && s.lng != 0.0,
            orElse: () => busCtrl.stopsList.first,
          );
          if (validStop.lat != 0.0 && validStop.lng != 0.0) {
            _nudgeCamera(LatLng(validStop.lat, validStop.lng), 14.5);
            return;
          }
        }
      }
      final cam = _mapController.camera;
      _nudgeCamera(cam.center, cam.zoom);
    } catch (_) {
      // MapController not attached yet.
    }
  }

  /// move() is a no-op when center+zoom are unchanged, so tiles stay blank.
  void _nudgeCamera(LatLng center, double zoom) {
    _mapController.move(center, zoom);
    _mapController.move(center, zoom + 0.02);
    _mapController.move(center, zoom);
  }

  void _moveToSelectedStop(BusController busCtrl) {
    LatLng? coord = busCtrl.getSelectedStopCoordinate();
    if (coord != null) {
      _nudgeCamera(coord, 16.5);
    }
  }

  void _openRoutingHistory(NavigationController navCtrl) {
    final parentContext = context;
    final langCtrl = parentContext.read<LanguageController>();
    if (navCtrl.routingHistory.isEmpty) {
      ScaffoldMessenger.of(parentContext).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: parentContext, content: Text(langCtrl.tr('no_nav_history'))));
      return;
    }
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
              child: Column(
                children: [
                  Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2))),
                  Text(langCtrl.tr('nav_history'), style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: navCtrl.routingHistory.length,
                      separatorBuilder: (ctx, i) => Divider(color: isDark ? const Color(0xFF333333) : Colors.grey[300], height: 1),
                      itemBuilder: (ctx, i) {
                        final item = navCtrl.routingHistory[i];
                        return ListTile(
                          leading: const Icon(Icons.history, color: Colors.grey),
                          title: Text('${langCtrl.tr('go_to_dest')}${item['destination']}', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15)),
                          subtitle: Text('${(item['itineraries'] as List).length}${langCtrl.tr('route_plan_count')}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () {
                            Navigator.pop(sheetContext); 
                            navCtrl.setPlanningRoute(true); 
                            Future.delayed(const Duration(milliseconds: 350), () {
                              if (parentContext.mounted) {
                                List<Itinerary> itins = item['itineraries'] as List<Itinerary>;
                                // 🌟 呼叫共用工具
                                RouteResultHelper.showOTPResultBottomSheet(parentContext, itins, item['destination'].toString(), navCtrl, langCtrl);
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

  void _openRoutingPanel(LanguageController langCtrl) {
    final busCtrl = context.read<BusController>();
    if (busCtrl.isSimpleMode) return;
    final navCtrl = context.read<NavigationController>();
    final locCtrl = context.read<LocationController>();
    final parentContext = context; 

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
            Navigator.pop(sheetContext); busCtrl.startPickingMapStart(); navCtrl.clearNavigation(); navCtrl.setPlanningRoute(true);
          },
          onPickEndOnMap: () {
            Navigator.pop(sheetContext); busCtrl.startPickingMapEnd(); navCtrl.clearNavigation(); navCtrl.setPlanningRoute(true);
          },
          onRouteCalculated: (itineraries, destination, onlyGhostsLeft) {
            wasRouteCalculated = true;
            Navigator.pop(sheetContext); 
            busCtrl.clearCustomMapPoints(); 
            if (itineraries.isNotEmpty) {
              if (onlyGhostsLeft) ScaffoldMessenger.of(parentContext).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: parentContext, content: Text(langCtrl.tr('warning_offline')), backgroundColor: Colors.redAccent));
              navCtrl.addHistory(itineraries, destination, onlyGhostsLeft);
              Future.delayed(const Duration(milliseconds: 350), () {
                // 🌟 呼叫共用工具
                if (mounted) RouteResultHelper.showOTPResultBottomSheet(context, itineraries, destination, navCtrl, langCtrl);
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: context, content: Text(langCtrl.tr('calc_route_failed'))));
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

  void _handleClose(BuildContext context) {
    final navCtrl = context.read<NavigationController>();
    final busCtrl = context.read<BusController>();
    final isNavigating = navCtrl.otpNavigationPolylines.isNotEmpty ||
        navCtrl.isDrawingNavRoute;
    // Transfer / multi-leg nav: X → 車站 for the selected route tab.
    if (isNavigating && navCtrl.navBusRoutes.isNotEmpty) {
      navCtrl.closeNavMapToStationPage(busCtrl: busCtrl);
      return;
    }
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final busCtrl = context.watch<BusController>();
    final locCtrl = context.watch<LocationController>();
    final navCtrl = context.watch<NavigationController>();
    final langCtrl = context.watch<LanguageController>(); 
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String legPrefixText = langCtrl.currentLanguage == 'en' ? 'Leg' : (langCtrl.currentLanguage == 'pt' ? 'Etapa' : '第');
    final String legSuffixText = langCtrl.currentLanguage == 'en' ? ':' : (langCtrl.currentLanguage == 'pt' ? ':' : '程:');
    final String boardPointText = langCtrl.currentLanguage == 'en' ? 'Boarding:' : (langCtrl.currentLanguage == 'pt' ? 'Embarque:' : '上車點:');
    final String alightPointText = langCtrl.currentLanguage == 'en' ? 'Alighting:' : (langCtrl.currentLanguage == 'pt' ? 'Saída:' : '落車點:');
    final String stopWordText = langCtrl.currentLanguage == 'en' ? 'Stop' : (langCtrl.currentLanguage == 'pt' ? 'Paragem' : '站');

    String currentTerminal = busCtrl.currentDirection == 0 ? busCtrl.outboundTerminal : busCtrl.inboundTerminal;
    if (busCtrl.stopsList.isNotEmpty) {
       currentTerminal = busCtrl.stopsList.last.getLocalizedName(langCtrl.currentLanguage).replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
    }
        
    bool isNavigating = navCtrl.otpNavigationPolylines.isNotEmpty ||
        navCtrl.isDrawingNavRoute;
    bool isPicking = busCtrl.isPickingMapStart || busCtrl.isPickingMapEnd;
    bool shouldHideOriginalRoute = isNavigating || isPicking || navCtrl.isPlanningRoute;

    LatLng mapCenter = const LatLng(22.1987, 113.5439);
    double initialZoom = 14.5;
    if (!shouldHideOriginalRoute) {
      final selected = busCtrl.getSelectedStopCoordinate();
      if (selected != null) {
        mapCenter = selected;
        initialZoom = 16.5;
      } else if (locCtrl.isFollowingUser && locCtrl.userLocation != null) {
        mapCenter = locCtrl.userLocation!;
      } else if (busCtrl.stopsList.isNotEmpty) {
        final firstValid = busCtrl.stopsList.firstWhere(
          (s) => s.lat != 0.0 && s.lng != 0.0,
          orElse: () => busCtrl.stopsList.first,
        );
        if (firstValid.lat != 0.0) mapCenter = LatLng(firstValid.lat, firstValid.lng);
      }
    } else if (locCtrl.isFollowingUser && locCtrl.userLocation != null) {
      mapCenter = locCtrl.userLocation!;
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
                ScaffoldMessenger.of(context).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: context, content: Text('$stopWordText ${stop.seq}: ${stop.getLocalizedName(langCtrl.currentLanguage)}')));
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(color: isSelected ? Colors.amber : Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color.fromARGB(255, 114, 0, 162), width: 2.5), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 2)]),
                child: Text('${stop.seq}', style: TextStyle(color: Colors.black, fontSize: isSelected ? 13 : 11, fontWeight: FontWeight.bold)),
              ),
            ),
          );
        }),
      );
    }

    final List<Marker> busMarkers = [];
    int actualMapBusCount = 0;
    if (!shouldHideOriginalRoute) {
      final drawn = <({Bus bus, LatLng loc, bool atStop})>[];
      for (final bus in busCtrl.allBusesList) {
        final loc = busCtrl.snapBusToStop(bus);
        if (loc == null) continue;
        drawn.add((bus: bus, loc: loc, atStop: busCtrl.hasVisuallyArrived(bus)));
      }
      actualMapBusCount = drawn.length;
      final busPoints = [for (final item in drawn) item.loc];
      final stopPoints = [
        for (final stop in busCtrl.stopsList)
          if (stop.lat != 0.0 && stop.lng != 0.0) LatLng(stop.lat, stop.lng),
      ];
      final expanded = _expandedCards(busPoints, stopPoints);
      final offsets = _layoutCapsuleOffsets(busPoints, stopPoints, expanded);
      for (var i = 0; i < drawn.length; i++) {
        final item = drawn[i];
        final speedLabel = '${busCtrl.displaySpeedKmh(item.bus).toInt()}km/h';
        final detail = item.atStop ? langCtrl.tr('arrived_at_stop') : speedLabel;
        final headingName = _busHeadingStopName(busCtrl, item.bus, item.atStop, langCtrl.currentLanguage);
        final heading = headingName.isEmpty
            ? ''
            : item.atStop
                ? headingName
                : '${langCtrl.tr('direction_to')} $headingName';
        final iconColor = item.atStop ? Colors.orangeAccent : Colors.amber;
        busMarkers.add(Marker(
          point: item.loc,
          width: _BusCallout.boxWidth,
          height: _BusCallout.boxHeight,
          alignment: Alignment.center,
          rotate: true,
          child: IgnorePointer(
            child: _BusCallout(
              plate: item.bus.busLicense,
              heading: heading,
              detail: detail,
              detailColor: item.atStop ? Colors.deepOrange : const Color.fromARGB(255, 114, 0, 162),
              iconColor: iconColor,
              capsuleOffset: offsets[i],
              compact: !expanded[i],
            ),
          ),
        ));
      }
    }

    final List<Marker> extraMarkers = [];
    if (locCtrl.userLocation != null && locCtrl.isFollowingUser) {
      extraMarkers.add(Marker(point: locCtrl.userLocation!, width: 48, height: 48, child: Transform.rotate(angle: locCtrl.userHeading * (math.pi / 180), child: Stack(alignment: Alignment.center, children: [Positioned(top: 0, child: Icon(Icons.navigation, color: Colors.blueAccent.shade700, size: 28)), Container(width: 18, height: 18, decoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)))]))));
    }
    if (busCtrl.customMapStart != null) extraMarkers.add(Marker(point: busCtrl.customMapStart!, width: 45, height: 45, child: const Column(children: [Icon(Icons.location_on, color: Colors.green, size: 36)])));
    if (busCtrl.customMapEnd != null) extraMarkers.add(Marker(point: busCtrl.customMapEnd!, width: 45, height: 45, child: const Column(children: [Icon(Icons.location_on, color: Colors.redAccent, size: 36)])));

    if (navCtrl.navStartPt != null && isNavigating) {
      extraMarkers.add(
        Marker(
          point: navCtrl.navStartPt!, width: 28, height: 28,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
            child: const Text('S', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      );
    }
    if (navCtrl.navEndPt != null && isNavigating) {
      extraMarkers.add(
        Marker(
          point: navCtrl.navEndPt!, width: 28, height: 28,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
            child: const Text('E', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      );
    }

    if (isNavigating && navCtrl.navBusLegsInfo.isNotEmpty && navCtrl.activeBusLegIndex < navCtrl.navBusLegsInfo.length) {
      final RouteLeg currentLeg = navCtrl.navBusLegsInfo[navCtrl.activeBusLegIndex];
      extraMarkers.add(
        Marker(
          point: LatLng(currentLeg.fromLat, currentLeg.fromLon), width: 34, height: 34,
          child: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                RouteLiquidGlassNavStyle.snackBar(
                  context: context,
                  content: Text(
                    currentLeg.boardingStopSeq != null ? '🟢 $boardPointText $stopWordText ${currentLeg.boardingStopSeq} (${currentLeg.fromName})' : '🟢 $boardPointText ${currentLeg.fromName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.green.shade700,
                ),
              );
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.green.shade700, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)]),
              child: Text(context.read<LanguageController>().tr('badge_board'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ),
      );
      extraMarkers.add(
        Marker(
          point: LatLng(currentLeg.toLat, currentLeg.toLon), width: 34, height: 34,
          child: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                RouteLiquidGlassNavStyle.snackBar(
                  context: context,
                  content: Text(
                    currentLeg.alightStopSeq != null ? '🔴 $alightPointText $stopWordText ${currentLeg.alightStopSeq} (${currentLeg.toName})' : '🔴 $alightPointText ${currentLeg.toName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.red.shade700,
                ),
              );
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.red.shade700, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)]),
              child: Text(context.read<LanguageController>().tr('badge_alight'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ),
      );
    }

    final List<Color> busColors = [Colors.orange, Colors.greenAccent, Colors.purpleAccent];

    String stopsDisplay = '${langCtrl.tr('stops_count')}${busCtrl.stopsList.length}';
    if (isNavigating && navCtrl.navBusLegsInfo.isNotEmpty && navCtrl.activeBusLegIndex < navCtrl.navBusLegsInfo.length) {
      final RouteLeg currentLeg = navCtrl.navBusLegsInfo[navCtrl.activeBusLegIndex];
      if (currentLeg.boardingStopSeq != null && currentLeg.alightStopSeq != null) {
        final boardSeq = currentLeg.boardingStopSeq!;
        final alightSeq = currentLeg.alightStopSeq!;
        final rideCount = alightSeq >= boardSeq
            ? alightSeq - boardSeq
            : (busCtrl.stopsList.isNotEmpty
                ? busCtrl.stopsList.length - boardSeq + alightSeq
                : (boardSeq - alightSeq).abs());
        stopsDisplay = '${langCtrl.tr('ride_stops_count')}$rideCount';
      }
    }

    return PopScope(
      canPop: widget.onClose == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleClose(context);
      },
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF5F5F7),
        body: Column(
      children: [
        if (widget.onClose != null && (isPicking || busCtrl.currentRoute.isEmpty))
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black),
                onPressed: () => _handleClose(context),
              ),
            ),
          ),
        if (!isPicking && busCtrl.currentRoute.isNotEmpty)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                  child: Container(
                    height: MediaQuery.of(context).padding.top + kToolbarHeight,
                    color: isDark ? Colors.black.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.7),
                    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, left: 16, right: 8),
                    alignment: Alignment.center, 
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                '${busCtrl.currentRoute} ${langCtrl.tr('direction_to')}' , 
                                style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Expanded(
                                child: FitMarqueeText(
                                  ' $currentTerminal',
                                  style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.swap_calls, color: isDark ? Colors.white : Colors.black),
                              onPressed: () { busCtrl.toggleDirection(); busCtrl.fetchStops(); navCtrl.clearNavigation(); },
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.amber),
                              onPressed: () => busCtrl.fetchBusETA(),
                            ),
                            if (widget.onClose != null)
                              IconButton(
                                icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black),
                                onPressed: () => _handleClose(context),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
            ],
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
                      color: isActive ? tabColor.withValues(alpha: 0.2) : Colors.transparent,
                      border: Border(bottom: BorderSide(color: isActive ? tabColor : Colors.transparent, width: 3)),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      children: [
                        Icon(Icons.directions_bus, size: 16, color: isActive ? tabColor : Colors.grey),
                        const SizedBox(width: 6),
                        Text('$legPrefixText ${index + 1} $legSuffixText $routeName', style: TextStyle(color: isActive ? tabColor : Colors.grey, fontWeight: FontWeight.bold)),
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
                  initialZoom: initialZoom,
                  onMapReady: _onMapReady,
                  onMapEvent: (_) {
                    if (!_mapReady) return;
                    final zoom = _mapController.camera.zoom;
                    final rotation = _mapController.camera.rotation;
                    if (zoom == _labelZoom && rotation == _labelRotation) return;
                    _labelZoom = zoom;
                    _labelRotation = rotation;
                    if (mounted) setState(() {});
                  },
                  onTap: (tapPosition, point) {
                    if (busCtrl.isPickingMapStart) { busCtrl.setCustomMapStart(point); _openRoutingPanel(langCtrl); } 
                    else if (busCtrl.isPickingMapEnd) { busCtrl.setCustomMapEnd(point); _openRoutingPanel(langCtrl); }
                  },
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.macau.bus_app', tileProvider: CachedTileProvider()),
                  if (isDark)
                    const IgnorePointer(
                      child: SizedBox.expand(
                        child: ColoredBox(color: Color(0x73000000)),
                      ),
                    ),
                  if (FeatureFlags.showRouteTrajectory)
                    PolylineLayer(
                      polylines: [
                        if (navCtrl.otpNavigationPolylines.isNotEmpty) ...navCtrl.otpNavigationPolylines
                        else if (!shouldHideOriginalRoute && busCtrl.gpxRoutePoints.isNotEmpty) Polyline(points: busCtrl.gpxRoutePoints, strokeWidth: 5.0, color: const Color.fromARGB(255, 114, 0, 162)),
                      ],
                    ),
                  MarkerLayer(markers: [...stopMarkers, ...busMarkers, ...extraMarkers]),
                ],
              ),
              if (busCtrl.isPickingMapStart || busCtrl.isPickingMapEnd)
                Positioned(
                  top: 16, left: 16, right: 16,
                  child: Material(
                    color: busCtrl.isPickingMapStart ? Colors.amber : Colors.redAccent,
                    borderRadius: BorderRadius.circular(8), elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.touch_app, color: busCtrl.isPickingMapStart ? Colors.black : Colors.white),
                          const SizedBox(width: 12),
                          Expanded(child: Text(busCtrl.isPickingMapStart ? langCtrl.tr('tap_map_start') : langCtrl.tr('tap_map_end'), style: TextStyle(color: busCtrl.isPickingMapStart ? Colors.black : Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                          InkWell(onTap: () { busCtrl.cancelMapPicking(); _openRoutingPanel(langCtrl); }, child: Icon(Icons.close, color: busCtrl.isPickingMapStart ? Colors.black : Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              if (navCtrl.isDrawingNavRoute)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.amber),
                        const SizedBox(height: 12),
                        Text(
                          langCtrl.tr('drawing_route'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              if (busCtrl.isLoadingStops)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.amber), const SizedBox(height: 12),
                        Text(langCtrl.tr('loading_data'), style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              // Chrome sits above floating liquid-glass nav; map still shows through.
              if (!isPicking && navCtrl.routingHistory.isNotEmpty && !busCtrl.isSimpleMode)
                Positioned(
                  bottom: MediaQuery.paddingOf(context).bottom + 44,
                  left: 16,
                  child: FloatingActionButton(
                    heroTag: 'history_fab',
                    backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                    onPressed: () => _openRoutingHistory(navCtrl),
                    child: const Icon(Icons.history, color: Colors.amber),
                  ),
                ),

              Positioned(
                bottom: MediaQuery.paddingOf(context).bottom + 44,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!shouldHideOriginalRoute && busCtrl.selectedStopSeq != null) ...[
                      FloatingActionButton(
                        heroTag: 'go_to_stop_fab',
                        backgroundColor: Colors.white,
                        onPressed: () => _moveToSelectedStop(busCtrl),
                        child: const Icon(Icons.pin_drop, color: Color.fromARGB(255, 114, 0, 162)),
                      ),
                      if (!isPicking && (!navCtrl.isPlanningRoute || isNavigating))
                        const SizedBox(height: 12),
                    ],
                    if (!isPicking && (!navCtrl.isPlanningRoute || isNavigating))
                      FloatingActionButton(
                        heroTag: 'gps_fab',
                        backgroundColor: locCtrl.isFollowingUser ? Colors.green : Colors.amber,
                        onPressed: () => GpsService.toggleGpsAndAutoSelectStop(context, busCtrl, locCtrl),
                        child: locCtrl.isLocating ? const CircularProgressIndicator(color: Colors.black) : Icon(locCtrl.isFollowingUser ? Icons.explore : Icons.my_location, color: locCtrl.isFollowingUser ? Colors.white : Colors.black),
                      ),
                  ],
                ),
              ),
              
              if (!isPicking && (!navCtrl.isPlanningRoute || isNavigating))
                Positioned(
                  // Sit just above the floating nav; map still shows through the bar.
                  bottom: MediaQuery.paddingOf(context).bottom,
                  left: 0,
                  right: 0,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                      child: Container(
                        // ... 保持你原本嘅 Container 設定唔變 ...
                        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: isDark ? [Colors.black.withValues(alpha: 0.7), Colors.black.withValues(alpha: 0.5)] : [Colors.white.withValues(alpha: 0.6), Colors.white.withValues(alpha: 0.4)]), border: Border(top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.8), width: 1.0))),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text(stopsDisplay, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
                            Text('${langCtrl.tr('operating_buses')}${busCtrl.allBusesList.length}${langCtrl.tr('map_showing')}$actualMapBusCount)', style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
                            if (busCtrl.stopsList.isEmpty && !busCtrl.isLoadingStops)
                              InkWell(onTap: () => busCtrl.fetchStops(), child: Text(langCtrl.tr('click_retry'), style: const TextStyle(color: Colors.amber, decoration: TextDecoration.underline))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
              Positioned(
                top: 60, 
                right: 16, 
                child: StreamBuilder(
                  stream: _mapController.mapEventStream, 
                  builder: (context, snapshot) {
                    final double rotation = _mapController.camera.rotation; 
                    if (rotation == 0.0) return const SizedBox.shrink(); 

                    return Material(
                      elevation: 4,
                      shape: const CircleBorder(),
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          _mapController.rotate(0.0);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Transform.rotate(
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
      ],
        ),
      ),
    );
  }

  /// Below this zoom the whole route is on screen, so every bus shows a plate only.
  static const _detailZoom = 13.2;

  List<bool> _expandedCards(List<LatLng> buses, List<LatLng> stops) {
    final zoom = _mapReady ? _mapController.camera.zoom : 14.5;
    if (!_mapReady || buses.isEmpty || zoom < _detailZoom) {
      return List.filled(buses.length, false);
    }
    final allFull = List<bool>.filled(buses.length, true);
    final trial = _layoutCapsuleOffsets(buses, stops, allFull);
    final centers = <Offset>[
      for (var i = 0; i < buses.length; i++) _screenOf(buses[i]) + trial[i],
    ];
    final keep = List<bool>.filled(buses.length, false);
    final order = List<int>.generate(buses.length, (i) => i)
      ..sort((a, b) => centers[a].dy.compareTo(centers[b].dy));
    final accepted = <int>[];
    for (final i in order) {
      final blocked = accepted.any(
        (j) => _capsulesOverlap(
          centers[i],
          centers[j],
          _BusCallout.capsuleWidth,
          _BusCallout.capsuleHeight,
          _BusCallout.capsuleWidth,
          _BusCallout.capsuleHeight,
        ),
      );
      if (!blocked) {
        keep[i] = true;
        accepted.add(i);
      }
    }
    return keep;
  }

  Offset _screenOf(LatLng ll) {
    final p = _mapController.camera.latLngToScreenPoint(ll);
    return Offset(p.x.toDouble(), p.y.toDouble());
  }

  bool _capsulesOverlap(Offset a, Offset b, double wa, double ha, double wb, double hb) {
    const gap = 8.0;
    return (a.dx - b.dx).abs() < (wa + wb) / 2 + gap && (a.dy - b.dy).abs() < (ha + hb) / 2 + gap;
  }

  List<Offset> _layoutCapsuleOffsets(List<LatLng> buses, List<LatLng> stops, List<bool> expanded) {
    final offsets = <Offset>[
      for (var i = 0; i < buses.length; i++)
        expanded[i]
            ? Offset(i.isEven ? 56 : -56, i % 4 < 2 ? -24 : 28)
            : Offset(i.isEven ? 58 : -58, i % 4 < 2 ? -18 : 20),
    ];
    if (!_mapReady || buses.isEmpty) return offsets;

    final busScreens = [for (final ll in buses) _screenOf(ll)];
    final stopScreens = [for (final ll in stops) _screenOf(ll)];
    const stopPad = 20.0;
    double widthOf(int i) => expanded[i] ? _BusCallout.capsuleWidth : _BusCallout.plateWidth;
    double heightOf(int i) => expanded[i] ? _BusCallout.capsuleHeight : _BusCallout.plateHeight;

    for (var iter = 0; iter < 18; iter++) {
      var moved = false;
      for (var i = 0; i < offsets.length; i++) {
        final center = busScreens[i] + offsets[i];
        for (var j = i + 1; j < offsets.length; j++) {
          final other = busScreens[j] + offsets[j];
          if (!_capsulesOverlap(center, other, widthOf(i), heightOf(i), widthOf(j), heightOf(j))) continue;
          final delta = other - center;
          final pushX = (widthOf(i) + widthOf(j)) / 2 + 8 - delta.dx.abs();
          final pushY = (heightOf(i) + heightOf(j)) / 2 + 8 - delta.dy.abs();
          if (pushX < pushY) {
            final sign = delta.dx == 0 ? (i.isEven ? 1.0 : -1.0) : delta.dx.sign;
            final push = pushX / 2 + 1;
            offsets[i] -= Offset(sign * push, 0);
            offsets[j] += Offset(sign * push, 0);
          } else {
            final sign = delta.dy == 0 ? -1.0 : delta.dy.sign;
            final push = pushY / 2 + 1;
            offsets[i] -= Offset(0, sign * push);
            offsets[j] += Offset(0, sign * push);
          }
          moved = true;
        }
        for (final stop in stopScreens) {
          final capsule = busScreens[i] + offsets[i];
          final dx = capsule.dx - stop.dx;
          final dy = capsule.dy - stop.dy;
          final hitX = dx.abs() < widthOf(i) / 2 + stopPad;
          final hitY = dy.abs() < heightOf(i) / 2 + stopPad;
          if (!hitX || !hitY) continue;
          final signX = dx == 0 ? 1.0 : dx.sign;
          final signY = dy == 0 ? -1.0 : dy.sign;
          offsets[i] += Offset(signX * 6, signY * 4);
          moved = true;
        }
        final limit = expanded[i] ? 110.0 : 72.0;
        final dist = offsets[i].distance;
        if (dist > limit) offsets[i] = offsets[i] * (limit / dist);
      }
      if (!moved) break;
    }
    return offsets;
  }
}

String _busHeadingStopName(BusController busCtrl, Bus bus, bool arrived, String lang) {
  if (bus.currentStopSeq <= 0 || busCtrl.stopsList.isEmpty) return '';
  final index = busCtrl.stopsList.indexWhere((s) => s.seq == bus.currentStopSeq);
  if (index < 0) return '';
  final target = arrived || index + 1 >= busCtrl.stopsList.length ? index : index + 1;
  return busCtrl.stopsList[target]
      .getLocalizedName(lang)
      .replaceAll(RegExp(r'[\(（].*?[\)）]'), '')
      .trim();
}

class _BusCallout extends StatelessWidget {
  static const capsuleWidth = 132.0;
  static const capsuleHeight = 48.0;
  static const plateWidth = 76.0;
  static const plateHeight = 22.0;
  static const boxWidth = 360.0;
  static const boxHeight = 280.0;

  final String plate;
  final String heading;
  final String detail;
  final Color detailColor;
  final Color iconColor;
  final Offset capsuleOffset;
  final bool compact;

  const _BusCallout({
    required this.plate,
    required this.heading,
    required this.detail,
    required this.detailColor,
    required this.iconColor,
    required this.capsuleOffset,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    const icon = 22.0;
    final bus = const Offset(boxWidth / 2, boxHeight / 2);
    final capsuleCenter = bus + capsuleOffset;
    final cardWidth = compact ? plateWidth : capsuleWidth;
    final cardHeight = compact ? plateHeight : capsuleHeight;
    final stemFrom = _edgePoint(bus, capsuleCenter, icon / 2, icon / 2);
    final stemTo = _edgePoint(capsuleCenter, bus, cardWidth / 2, cardHeight / 2);
    return SizedBox(
      width: boxWidth,
      height: boxHeight,
      child: Stack(
        children: [
          CustomPaint(
            size: const Size(boxWidth, boxHeight),
            painter: _StemPainter(stemFrom, stemTo),
          ),
          Positioned(
            left: bus.dx - icon / 2,
            top: bus.dy - icon / 2,
            child: Icon(Icons.directions_bus, color: iconColor, size: icon),
          ),
          Positioned(
            left: capsuleCenter.dx - cardWidth / 2,
            top: capsuleCenter.dy - cardHeight / 2,
            width: cardWidth,
            height: cardHeight,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
              ),
              child: compact
                  ? Text(plate, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, height: 1.0, color: Colors.black87))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(plate, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, height: 1.0, color: Colors.black87)),
                        if (heading.isNotEmpty)
                          Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, height: 1.05, color: Colors.black87)),
                        Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, height: 1.05, color: detailColor)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Offset _edgePoint(Offset center, Offset toward, double halfW, double halfH) {
    final delta = toward - center;
    final dist = delta.distance;
    if (dist == 0) return center;
    final ux = delta.dx / dist;
    final uy = delta.dy / dist;
    final tx = ux == 0 ? double.infinity : halfW / ux.abs();
    final ty = uy == 0 ? double.infinity : halfH / uy.abs();
    return center + Offset(ux, uy) * math.min(tx, ty);
  }
}

class _StemPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  const _StemPainter(this.from, this.to);

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, outline);
    canvas.drawLine(from, to, line);
  }

  @override
  bool shouldRepaint(covariant _StemPainter oldDelegate) => oldDelegate.from != from || oldDelegate.to != to;
}

class CachedTileProvider extends TileProvider {
  CachedTileProvider(); 
  @override ImageProvider getImage(TileCoordinates coordinates, TileLayer options) { return CachedNetworkImageProvider(getTileUrl(coordinates, options)); }
}