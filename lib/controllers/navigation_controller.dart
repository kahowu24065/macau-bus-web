import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

import '../services/places_service.dart';
import '../services/bus_api_service.dart';
import '../utils/coord_transform.dart';
import '../models/itinerary.dart';
import '../models/bus_stop.dart';
import '../services/otp_service.dart';
import '../config/api_config.dart';
import '../services/gpx_service.dart';
import '../services/local_timetable.dart';
import 'bus_controller.dart';
import 'language_controller.dart'; // 🌟 引入語言控制器

class PolylineDecoder {
  static List<LatLng> decode(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result += (b & 0x1f) * math.pow(2, shift).toInt();
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? -(result ~/ 2) - 1 : (result ~/ 2);
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result += (b & 0x1f) * math.pow(2, shift).toInt();
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? -(result ~/ 2) - 1 : (result ~/ 2);
      lng += dlng;
      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polyline;
  }
}

class GPXBreadcrumbService {
  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static Future<List<LatLng>> getPreciseRoute(String route, int dir, LatLng fromPt, LatLng toPt) async {
    try {
      final stopsRes = await http.get(Uri.parse('${ApiConfig.api}/bus-stops?route=$route&dir=$dir'));
      List<LatLng> guideStops = [];
      if (stopsRes.statusCode == 200) {
        final json = jsonDecode(stopsRes.body);
        if (json['success'] == true) {
          List<dynamic> stops = json['stops'];
          int startIdx = -1;
          double minStart = double.infinity;
          for (int i = 0; i < stops.length; i++) {
            double d = const Distance().as(LengthUnit.Meter, fromPt, LatLng(_parseDouble(stops[i]['lat']), _parseDouble(stops[i]['lng'])));
            if (d < minStart) {
              minStart = d;
              startIdx = i;
            }
          }
          int endIdx = startIdx;
          double minEnd = double.infinity;
          for (int i = startIdx; i < stops.length; i++) {
            double d = const Distance().as(LengthUnit.Meter, toPt, LatLng(_parseDouble(stops[i]['lat']), _parseDouble(stops[i]['lng'])));
            if (d < minEnd) {
              minEnd = d;
              endIdx = i;
            }
          }
          for (int i = startIdx; i <= endIdx; i++) {
            guideStops.add(LatLng(_parseDouble(stops[i]['lat']), _parseDouble(stops[i]['lng'])));
          }
        }
      }

      final gpxRes = await http.get(Uri.parse('${ApiConfig.api}/bus-gpx?route=$route&dir=$dir'));
      if (gpxRes.statusCode == 200) {
        final json = jsonDecode(gpxRes.body);
        if (json['success'] == true && json['points'] != null) {
          List<LatLng> allGpx = (json['points'] as List)
              .map((p) => LatLng(_parseDouble(p['lat']), _parseDouble(p['lng'])))
              .where((l) => l.latitude != 0)
              .toList();
          if (allGpx.isEmpty) return [];
          if (guideStops.isEmpty) guideStops = [fromPt, toPt];

          List<LatLng> resultLine = [];
          int currentGpxIdx = 0;
          double minD = double.infinity;
          for (int i = 0; i < allGpx.length; i++) {
            double d = const Distance().as(LengthUnit.Meter, guideStops.first, allGpx[i]);
            if (d < minD) {
              minD = d;
              currentGpxIdx = i;
            }
          }
          resultLine.add(allGpx[currentGpxIdx]);

          for (int i = 1; i < guideStops.length; i++) {
            LatLng target = guideStops[i];
            int bestIdx = currentGpxIdx;
            double bestDist = const Distance().as(LengthUnit.Meter, target, allGpx[currentGpxIdx]);
            for (int step = 1; step < allGpx.length; step++) {
              int checkIdx = (currentGpxIdx + step) % allGpx.length;
              double d = const Distance().as(LengthUnit.Meter, target, allGpx[checkIdx]);
              if (d < bestDist) {
                bestDist = d;
                bestIdx = checkIdx;
              }
              if (bestDist < 50 && d > bestDist + 100) break;
            }
            int curr = currentGpxIdx;
            while (curr != bestIdx) {
              curr = (curr + 1) % allGpx.length;
              resultLine.add(allGpx[curr]);
            }
            currentGpxIdx = bestIdx;
          }
          return resultLine;
        }
      }
    } catch (_) {}
    return [];
  }
}

class NavigationController extends ChangeNotifier {
  int selectedIndex = 0;
  
  bool isPlanningRoute = false;
  bool isDrawingNavRoute = false;

  List<Polyline> otpNavigationPolylines = [];
  List<String> navBusRoutes = [];
  LatLng? navStartPt;
  LatLng? navEndPt;
  
  List<RouteLeg> navBusLegsInfo = [];
  int activeBusLegIndex = 0;
  
  List<Map<String, dynamic>> routingHistory = [];

  bool isRoutingWithOTP = false;
  final Map<String, dynamic> _routeDataCache = {};
  /// Dedupes concurrent stop-table fetches for the same route+lang.
  final Map<String, Future<void>> _routeStopsInFlight = {};

  void setPlanningRoute(bool value) {
    isPlanningRoute = value;
    notifyListeners();
  }

  void addHistory(List<Itinerary> itineraries, String destination, bool onlyGhostsLeft) {
    if (itineraries.isEmpty) return;

    final newRecord = {
      'destination': destination,
      'onlyGhostsLeft': onlyGhostsLeft,
      'timestamp': DateTime.now().toIso8601String(), 
      'itineraries': itineraries, 
    };

    routingHistory.insert(0, newRecord);

    if (routingHistory.length > 15) {
      routingHistory = routingHistory.sublist(0, 15);
    }

    notifyListeners(); 
  }
  
  bool showMapView = false;
  String? _routeBeforeMapOverlay;

  void captureRouteForRestore(String route) {
    if ((_routeBeforeMapOverlay == null || _routeBeforeMapOverlay!.isEmpty) &&
        route.isNotEmpty) {
      _routeBeforeMapOverlay = route;
    }
  }

  void openMap() {
    showMapView = true;
    notifyListeners();
  }

  /// Close transfer-nav map and open 車站 for the currently selected leg tab.
  /// Uses [navBusRoutes]/activeBusLegIndex], falling back to [busCtrl.currentRoute].
  void closeNavMapToStationPage({required BusController busCtrl}) {
    String route = '';
    if (navBusRoutes.isNotEmpty) {
      final i = activeBusLegIndex.clamp(0, navBusRoutes.length - 1);
      route = navBusRoutes[i];
    }
    if (route.isEmpty) {
      route = busCtrl.currentRoute;
    }

    showMapView = false;
    isPlanningRoute = false;
    busCtrl.cancelMapPicking();

    otpNavigationPolylines = [];
    navBusRoutes = [];
    navStartPt = null;
    navEndPt = null;
    navBusLegsInfo = [];
    activeBusLegIndex = 0;
    isDrawingNavRoute = false;
    _routeBeforeMapOverlay = null;

    selectedIndex = 2; // 車站 tab

    if (route.isNotEmpty) {
      busCtrl.setRoute(route);
      busCtrl.fetchStops();
    }

    notifyListeners();
  }

  void closeMap({BusController? busCtrl, bool notify = true}) {
    final hadNav = otpNavigationPolylines.isNotEmpty ||
        isPlanningRoute ||
        navBusRoutes.isNotEmpty;

    showMapView = false;
    isPlanningRoute = false;
    busCtrl?.cancelMapPicking();

    if (hadNav) {
      otpNavigationPolylines = [];
      navBusRoutes = [];
      navStartPt = null;
      navEndPt = null;
      navBusLegsInfo = [];
      activeBusLegIndex = 0;
      isDrawingNavRoute = false;

      final restore = _routeBeforeMapOverlay;
      _routeBeforeMapOverlay = null;
      if (busCtrl != null) {
        if (restore != null && restore.isNotEmpty) {
          busCtrl.setRoute(restore);
        }
        if (busCtrl.currentRoute.isNotEmpty) {
          busCtrl.fetchStops();
        }
      }
    } else {
      _routeBeforeMapOverlay = null;
    }

    if (notify) notifyListeners();
  }

  void changeTab(int index, {BusController? busCtrl}) {
    selectedIndex = index;
    closeMap(busCtrl: busCtrl, notify: false);
    notifyListeners();
  }

  void clearNavigation() {
    otpNavigationPolylines = [];
    navBusRoutes = [];
    navStartPt = null;
    navEndPt = null;
    navBusLegsInfo = [];
    activeBusLegIndex = 0;
    isDrawingNavRoute = false;
    notifyListeners();
  }

  void setActiveBusLeg(int index) {
    activeBusLegIndex = index;
    notifyListeners();
  }

  // 🌟 使用字典判斷座標獲取邏輯
  Future<LatLng?> getCoordinate(String text, bool isStart, LatLng? userLoc, LatLng? customStart, LatLng? customEnd, String sessionToken, String? placeId, LanguageController langCtrl) async {
    if (text.isEmpty) return null;
    
    if (isStart) {
      if (text == langCtrl.tr('current_gps_location') || text.contains('GPS') || text.contains('目前位置')) return userLoc;
      if (text == langCtrl.tr('custom_start') || text.contains('地圖自選起點') || text.contains('Custom Start') || text.contains('Início')) {
        if (customStart != null) return customStart;
      }
    } else {
      if (text == langCtrl.tr('custom_end') || text.contains('地圖自選終點') || text.contains('Custom End') || text.contains('Fim')) {
        if (customEnd != null) return customEnd;
      }
    }

    if (placeId != null && placeId.isNotEmpty) {
      return await PlacesService.getDetails(placeId, sessionToken);
    } else {
      return await PlacesService.textSearch(text);
    }
  }

  Future<void> _ensureRouteDirStops(String route, int dir, String lang) async {
    final cacheKey = '${route}_stops_$dir';
    if (_routeDataCache.containsKey(cacheKey)) return;

    final flightKey = '${route}_${dir}_$lang';
    final existing = _routeStopsInFlight[flightKey];
    if (existing != null) {
      await existing;
      return;
    }

    final future = () async {
      final res = await BusApiService.fetchStops(route, dir, lang: lang);
      if (res['success'] == true) {
        _routeDataCache[cacheKey] = res['stops'];
      }
      // Timeouts are not cached as empty tables — that poisoned matching.
    }();
    _routeStopsInFlight[flightKey] = future;
    try {
      await future;
    } finally {
      _routeStopsInFlight.remove(flightKey);
    }
  }

  Future<void> prefetchRouteStops(String route, String lang) =>
      _ensureRouteStopsCached(route, lang);

  Future<void> _ensureRouteStopsCached(String route, String lang) async {
    await Future.wait([
      _ensureRouteDirStops(route, 0, lang),
      _ensureRouteDirStops(route, 1, lang),
    ]);
  }

  BusStop? _asBusStop(dynamic stop) {
    if (stop is BusStop) return stop;
    if (stop is Map<String, dynamic>) return BusStop.fromJson(stop);
    try {
      return BusStop.fromJson(Map<String, dynamic>.from(stop as Map));
    } catch (_) {
      return null;
    }
  }

  static const double _officialStopMatchMeters = 800;

  /// OTP leg endpoints → nearest official stop within this radius.
  static const double otpLegStopMatchMeters = 150;

  String _normStopName(String raw) =>
      raw.replaceAll(RegExp(r'[\s\u3000]'), '').replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();

  bool _samePhysicalStop(BusStop a, BusStop b, Distance distanceCalc) {
    final aName = _normStopName(a.nameZh.isNotEmpty ? a.nameZh : a.name);
    final bName = _normStopName(b.nameZh.isNotEmpty ? b.nameZh : b.name);
    if (aName.isNotEmpty && aName == bName) return true;
    if (a.lat == 0.0 || a.lng == 0.0 || b.lat == 0.0 || b.lng == 0.0) return false;
    return distanceCalc.as(
          LengthUnit.Meter,
          LatLng(a.lat, a.lng),
          LatLng(b.lat, b.lng),
        ) <
        80;
  }

  double? _scoreForwardRide({
    required List<BusStop> stops,
    required int boardIdx,
    required int alightIdx,
    required bool circular,
    required double boardDist,
    required double alightDist,
    required Distance distanceCalc,
    required double maxEndpointDist,
  }) {
    if (boardIdx == alightIdx) return null;
    if (_samePhysicalStop(stops[boardIdx], stops[alightIdx], distanceCalc)) {
      return null;
    }
    final int hops;
    if (alightIdx > boardIdx) {
      hops = alightIdx - boardIdx;
    } else if (circular) {
      hops = stops.length - boardIdx + alightIdx;
    } else {
      return null;
    }
    if (hops < 1) return null;
    final boardOk = boardDist.isFinite && boardDist <= maxEndpointDist;
    final alightOk = alightDist.isFinite && alightDist <= maxEndpointDist;
    if (!boardOk || !alightOk) return null;
    return hops * 100000 + boardDist + alightDist;
  }

  ({BusStop board, BusStop alight})? _shortestDuplicateRide(
    List<BusStop> stops,
    BusStop board,
    BusStop alight,
    bool circular,
  ) {
    const distanceCalc = Distance();
    final boardIdxs = <int>[];
    final alightIdxs = <int>[];
    for (int i = 0; i < stops.length; i++) {
      if (_samePhysicalStop(stops[i], board, distanceCalc)) boardIdxs.add(i);
      if (_samePhysicalStop(stops[i], alight, distanceCalc)) alightIdxs.add(i);
    }
    if (boardIdxs.isEmpty || alightIdxs.isEmpty) return null;

    double best = double.infinity;
    BusStop? bestBoard;
    BusStop? bestAlight;
    for (final bi in boardIdxs) {
      for (final ai in alightIdxs) {
        final scored = _scoreForwardRide(
          stops: stops,
          boardIdx: bi,
          alightIdx: ai,
          circular: circular,
          boardDist: 0,
          alightDist: 0,
          distanceCalc: distanceCalc,
          maxEndpointDist: 2500,
        );
        if (scored == null || scored >= best) continue;
        best = scored;
        bestBoard = stops[bi];
        bestAlight = stops[ai];
      }
    }
    if (bestBoard == null || bestAlight == null) return null;
    return (board: bestBoard, alight: bestAlight);
  }

  /// Match board/alight coordinates to official DSAT stops on [route].
  /// Used for OTP legs and for official direct-bus fallback.
  Future<({int dir, BusStop board, BusStop alight})?> matchEndpointsToOfficialRoute({
    required String route,
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String lang,
    String? otpFromName,
    String? otpToName,
    double? nearestWithinMeters,
    DateTime? at,
  }) async {
    if (route.isEmpty) return null;
    await LocalTimetable.ensureLoaded();
    if (LocalTimetable.unavailableForPlanning(route, at: at)) return null;
    await _ensureRouteStopsCached(route, lang);

    const distanceCalc = Distance();
    int? bestDir;
    BusStop? bestBoard;
    BusStop? bestAlight;
    double bestScore = double.infinity;

    // Nearest-stop pass for OTP legs: OTP already chose real board/alight
    // points, so take the official stops closest to them (within
    // [nearestWithinMeters]) instead of the fewest-hops stop up to 800 m away.
    int? nearDir;
    BusStop? nearBoard;
    BusStop? nearAlight;
    double nearScore = double.infinity;

    final fromNameKey = otpFromName == null ? '' : _normStopName(otpFromName);
    final toNameKey = otpToName == null ? '' : _normStopName(otpToName);

    for (final dir in [0, 1]) {
      final rawStops = _routeDataCache['${route}_stops_$dir'];
      if (rawStops == null || (rawStops as List).isEmpty) continue;

      final stops = <BusStop>[];
      for (final s in rawStops) {
        final stop = _asBusStop(s);
        if (stop != null) stops.add(stop);
      }
      if (stops.length < 2) continue;
      stops.sort((a, b) => a.seq.compareTo(b.seq));

      final first = stops.first;
      final last = stops.last;
      final circular = _normStopName(first.nameZh.isNotEmpty ? first.nameZh : first.name) ==
          _normStopName(last.nameZh.isNotEmpty ? last.nameZh : last.name);

      final fromDists = List<double>.filled(stops.length, double.infinity);
      final toDists = List<double>.filled(stops.length, double.infinity);
      final boardCands = <int>[];
      final alightCands = <int>[];

      for (int i = 0; i < stops.length; i++) {
        final stop = stops[i];
        if (stop.lat == 0.0 || stop.lng == 0.0) continue;
        final stopPt = LatLng(stop.lat, stop.lng);
        final dFrom = distanceCalc.as(
          LengthUnit.Meter,
          LatLng(fromLat, fromLon),
          stopPt,
        );
        final dTo = distanceCalc.as(
          LengthUnit.Meter,
          LatLng(toLat, toLon),
          stopPt,
        );
        fromDists[i] = dFrom;
        toDists[i] = dTo;

        final nameKey = _normStopName(stop.nameZh.isNotEmpty ? stop.nameZh : stop.name);
        final nameHitFrom = fromNameKey.isNotEmpty &&
            (nameKey == fromNameKey ||
                nameKey.contains(fromNameKey) ||
                fromNameKey.contains(nameKey));
        final nameHitTo = toNameKey.isNotEmpty &&
            (nameKey == toNameKey ||
                nameKey.contains(toNameKey) ||
                toNameKey.contains(nameKey));

        if (dFrom <= _officialStopMatchMeters || nameHitFrom) {
          boardCands.add(i);
        }
        if (dTo <= _officialStopMatchMeters || nameHitTo) {
          alightCands.add(i);
        }
      }

      if (nearestWithinMeters != null) {
        final nearB = <int>[];
        final nearA = <int>[];
        for (int i = 0; i < stops.length; i++) {
          if (fromDists[i] <= nearestWithinMeters) nearB.add(i);
          if (toDists[i] <= nearestWithinMeters) nearA.add(i);
        }
        for (final b in nearB) {
          for (final a in nearA) {
            final scored = _scoreForwardRide(
              stops: stops,
              boardIdx: b,
              alightIdx: a,
              circular: circular,
              boardDist: fromDists[b],
              alightDist: toDists[a],
              distanceCalc: distanceCalc,
              maxEndpointDist: nearestWithinMeters,
            );
            if (scored == null) continue;
            final hops =
                ((scored - fromDists[b] - toDists[a]) / 100000).round();
            // Distance first; 1 m per hop only breaks ties between duplicate
            // stops (out-and-back routes visiting the same stop twice).
            final score = fromDists[b] + toDists[a] + hops;
            if (score < nearScore) {
              nearScore = score;
              nearDir = dir;
              nearBoard = stops[b];
              nearAlight = stops[a];
            }
          }
        }
      }

      if (boardCands.isEmpty || alightCands.isEmpty) continue;

      void expandDuplicateStops(List<int> cands) {
        final extra = <int>{};
        for (final i in cands) {
          final origin = stops[i];
          final originName =
              _normStopName(origin.nameZh.isNotEmpty ? origin.nameZh : origin.name);
          final originPt = LatLng(origin.lat, origin.lng);
          for (int j = 0; j < stops.length; j++) {
            if (j == i) continue;
            final other = stops[j];
            if (other.lat == 0.0 || other.lng == 0.0) continue;
            final otherName =
                _normStopName(other.nameZh.isNotEmpty ? other.nameZh : other.name);
            final near = distanceCalc.as(
                  LengthUnit.Meter,
                  originPt,
                  LatLng(other.lat, other.lng),
                ) <
                80;
            if (near || (originName.isNotEmpty && originName == otherName)) {
              extra.add(j);
            }
          }
        }
        for (final j in extra) {
          if (!cands.contains(j)) cands.add(j);
        }
      }

      expandDuplicateStops(boardCands);
      expandDuplicateStops(alightCands);

      // Same physical stop appears twice on out-and-back routes (103:
      // 邊檢大樓 seq 2 and 12). Fewest forward hops wins, e.g. 12→13 not 2→13.
      for (final boardIdx in boardCands) {
        for (final alightIdx in alightCands) {
          final scored = _scoreForwardRide(
            stops: stops,
            boardIdx: boardIdx,
            alightIdx: alightIdx,
            circular: circular,
            boardDist: fromDists[boardIdx],
            alightDist: toDists[alightIdx],
            distanceCalc: distanceCalc,
            maxEndpointDist: 2500,
          );
          if (scored == null) continue;
          if (scored < bestScore) {
            bestScore = scored;
            bestDir = dir;
            bestBoard = stops[boardIdx];
            bestAlight = stops[alightIdx];
          }
        }
      }

      if (bestDir == dir && bestBoard != null && bestAlight != null) {
        final snapped = _shortestDuplicateRide(stops, bestBoard, bestAlight, circular);
        if (snapped != null) {
          bestBoard = snapped.board;
          bestAlight = snapped.alight;
        }
      }
    }

    if (nearDir != null && nearBoard != null && nearAlight != null) {
      return (dir: nearDir, board: nearBoard, alight: nearAlight);
    }
    if (bestDir == null || bestBoard == null || bestAlight == null) return null;
    return (dir: bestDir, board: bestBoard, alight: bestAlight);
  }

  /// Match OTP board/alight to official DSAT stops on [leg.routeName].
  Future<bool> matchLegToOfficialStops(
    RouteLeg leg,
    LanguageController langCtrl,
  ) async {
    final route = leg.routeName;
    if (route.isEmpty) return false;

    try {
      final matched = await matchEndpointsToOfficialRoute(
        route: route,
        fromLat: leg.fromLat,
        fromLon: leg.fromLon,
        toLat: leg.toLat,
        toLon: leg.toLon,
        lang: langCtrl.currentLanguage,
        otpFromName: leg.fromName,
        otpToName: leg.toName,
        nearestWithinMeters: otpLegStopMatchMeters,
        at: leg.boardingTimeMacau,
      );
      if (matched == null) return false;

      final boardStop = matched.board;
      final alightStop = matched.alight;
      leg.bestDir = matched.dir;
      leg.boardingStopSeq = boardStop.seq;
      leg.alightStopSeq = alightStop.seq;

      leg.displayFromName =
          boardStop.nameZh.isNotEmpty ? boardStop.nameZh : boardStop.name;
      leg.displayFromNameEn = boardStop.nameEn;
      leg.displayFromNamePt = boardStop.namePt;
      leg.displayToName =
          alightStop.nameZh.isNotEmpty ? alightStop.nameZh : alightStop.name;
      leg.displayToNameEn = alightStop.nameEn;
      leg.displayToNamePt = alightStop.namePt;

      // Snap leg endpoints to official stops so map/ETA stay consistent.
      // (fromLat/toLat are final — display names + seqs are enough for UI.)

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Official DSAT itineraries: direct buses first, then 1-transfer, then
  /// 2-transfer via origin terminals. Merged with OTP by the planner UI.
  Future<List<Itinerary>> suggestOfficialDirectBuses({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    required LanguageController langCtrl,
    bool includeTwoTransfers = false,
  }) async {
    final lang = langCtrl.currentLanguage;
    final nearby = await Future.wait([
      OTPService.fetchNearbyStops(
        lat: fromLat,
        lng: fromLng,
        maxDistance: 900,
        limit: 15,
      ),
      OTPService.fetchNearbyStops(
        lat: toLat,
        lng: toLng,
        maxDistance: 900,
        limit: 15,
      ),
    ]);
    final nearFrom = nearby[0];
    final nearTo = nearby[1];

    // Union (not intersection): OTP nearby at one end may omit a valid
    // route (e.g. start misses 26A while Hac Sá lists it). Official stop
    // matching below is the real gate.
    final candidates = <String>{};
    for (final s in [...nearFrom, ...nearTo]) {
      for (final r in (s['routes'] as List? ?? const [])) {
        final name = r.toString().trim();
        if (name.isNotEmpty) candidates.add(name);
      }
    }

    final originRoutes = <String>{};
    for (final s in nearFrom) {
      for (final r in (s['routes'] as List? ?? const [])) {
        final name = r.toString().trim();
        if (name.isNotEmpty) originRoutes.add(name);
      }
    }
    final destRoutes = <String>{};
    for (final s in nearTo) {
      for (final r in (s['routes'] as List? ?? const [])) {
        final name = r.toString().trim();
        if (name.isNotEmpty) destRoutes.add(name);
      }
    }

    await LocalTimetable.ensureLoaded();
    candidates.removeWhere(LocalTimetable.unavailableForPlanning);
    originRoutes.removeWhere(LocalTimetable.unavailableForPlanning);
    destRoutes.removeWhere(LocalTimetable.unavailableForPlanning);

    final common = candidates.toList()..sort();
    if (common.isEmpty && originRoutes.isEmpty && destRoutes.isEmpty) {
      return [];
    }

    const distanceCalc = Distance();
    final matchResults = await Future.wait([
      for (final route in common)
        matchEndpointsToOfficialRoute(
          route: route,
          fromLat: fromLat,
          fromLon: fromLng,
          toLat: toLat,
          toLon: toLng,
          lang: lang,
        ),
    ]);

    final out = <Itinerary>[];
    for (var i = 0; i < common.length; i++) {
      final matched = matchResults[i];
      if (matched == null) continue;
      final route = common[i];

      final board = matched.board;
      final alight = matched.alight;
      final walkToBoardM = distanceCalc.as(
        LengthUnit.Meter,
        LatLng(fromLat, fromLng),
        LatLng(board.lat, board.lng),
      );
      final walkFromAlightM = distanceCalc.as(
        LengthUnit.Meter,
        LatLng(alight.lat, alight.lng),
        LatLng(toLat, toLng),
      );
      final busM = distanceCalc.as(
        LengthUnit.Meter,
        LatLng(board.lat, board.lng),
        LatLng(alight.lat, alight.lng),
      );

      final walk1Sec = (walkToBoardM / 1.2).round().clamp(60, 1800);
      final busSec = (busM / 5.5).round().clamp(120, 7200);
      final walk2Sec = (walkFromAlightM / 1.2).round().clamp(60, 1800);

      final boardName = board.nameZh.isNotEmpty ? board.nameZh : board.name;
      final alightName = alight.nameZh.isNotEmpty ? alight.nameZh : alight.name;

      final walk1 = RouteLeg(
        mode: 'WALK',
        duration: walk1Sec,
        fromName: 'Origin',
        fromLat: fromLat,
        fromLon: fromLng,
        toName: boardName,
        toNameEn: board.nameEn,
        toNamePt: board.namePt,
        toLat: board.lat,
        toLon: board.lng,
        geometry: '',
        routeName: '',
        distance: walkToBoardM,
      );
      final bus = RouteLeg(
        mode: 'BUS',
        duration: busSec,
        fromName: boardName,
        fromNameEn: board.nameEn,
        fromNamePt: board.namePt,
        fromLat: board.lat,
        fromLon: board.lng,
        toName: alightName,
        toNameEn: alight.nameEn,
        toNamePt: alight.namePt,
        toLat: alight.lat,
        toLon: alight.lng,
        geometry: '',
        routeName: route,
        distance: busM,
        bestDir: matched.dir,
        boardingStopSeq: board.seq,
        alightStopSeq: alight.seq,
      );
      bus.displayFromName = boardName;
      bus.displayFromNameEn = board.nameEn;
      bus.displayFromNamePt = board.namePt;
      bus.displayToName = alightName;
      bus.displayToNameEn = alight.nameEn;
      bus.displayToNamePt = alight.namePt;
      final walk2 = RouteLeg(
        mode: 'WALK',
        duration: walk2Sec,
        fromName: alightName,
        fromNameEn: alight.nameEn,
        fromNamePt: alight.namePt,
        fromLat: alight.lat,
        fromLon: alight.lng,
        toName: 'Destination',
        toLat: toLat,
        toLon: toLng,
        geometry: '',
        routeName: '',
        distance: walkFromAlightM,
      );

      out.add(Itinerary(
        duration: walk1Sec + busSec + walk2Sec,
        legs: [walk1, bus, walk2],
      ));
    }

    out.addAll(await _officialTransfers(
      originRoutes: originRoutes,
      destRoutes: destRoutes,
      fromLat: fromLat,
      fromLng: fromLng,
      toLat: toLat,
      toLng: toLng,
      distanceCalc: distanceCalc,
      lang: lang,
      includeTwoTransfers: includeTwoTransfers,
    ));

    out.sort((a, b) {
      int busCount(Itinerary it) =>
          it.legs.where((l) => l.mode == 'BUS').length;
      final c = busCount(a).compareTo(busCount(b));
      if (c != 0) return c;
      return a.duration.compareTo(b.duration);
    });
    if (out.length > 8) return out.sublist(0, 8);
    return out;
  }

  List<BusStop> _officialStops(String route, int dir) {
    final raw = _routeDataCache['${route}_stops_$dir'];
    if (raw is! List || raw.isEmpty) return const [];
    final out = <BusStop>[];
    for (final s in raw) {
      final stop = _asBusStop(s);
      if (stop != null && stop.lat != 0.0 && stop.lng != 0.0) out.add(stop);
    }
    out.sort((a, b) => a.seq.compareTo(b.seq));
    return out;
  }

  String _hubName(BusStop s) =>
      _normStopName(s.nameZh.isNotEmpty ? s.nameZh : s.name);

  Future<List<Itinerary>> _officialTransfers({
    required Set<String> originRoutes,
    required Set<String> destRoutes,
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    required Distance distanceCalc,
    required String lang,
    bool includeTwoTransfers = false,
  }) async {
    const boardM = 900.0;
    const xferM = 180.0;
    final fromPt = LatLng(fromLat, fromLng);
    final toPt = LatLng(toLat, toLng);
    final scored = <({double score, Itinerary it})>[];

    void consider(List<({String route, int dir, BusStop board, BusStop alight})> rides) {
      if (rides.isEmpty) return;
      final legs = <RouteLeg>[];
      var duration = 0;
      var walkStart = true;
      BusStop? prevAlight;
      for (final ride in rides) {
        final board = ride.board;
        final alight = ride.alight;
        if (walkStart) {
          final m = distanceCalc.as(LengthUnit.Meter, fromPt, LatLng(board.lat, board.lng));
          final sec = (m / 1.2).round().clamp(60, 1800);
          duration += sec;
          legs.add(_walkLeg(
            fromName: 'Origin',
            fromLat: fromLat,
            fromLng: fromLng,
            to: board,
            meters: m,
            sec: sec,
          ));
          walkStart = false;
        } else if (prevAlight != null) {
          final m = distanceCalc.as(
            LengthUnit.Meter,
            LatLng(prevAlight.lat, prevAlight.lng),
            LatLng(board.lat, board.lng),
          );
          final sec = (m / 1.2).round().clamp(30, 900);
          duration += sec;
          legs.add(_walkLeg(
            fromName: prevAlight.nameZh.isNotEmpty ? prevAlight.nameZh : prevAlight.name,
            fromLat: prevAlight.lat,
            fromLng: prevAlight.lng,
            to: board,
            meters: m,
            sec: sec,
            fromEn: prevAlight.nameEn,
            fromPt: prevAlight.namePt,
          ));
        }
        final busM = distanceCalc.as(
          LengthUnit.Meter,
          LatLng(board.lat, board.lng),
          LatLng(alight.lat, alight.lng),
        );
        final busSec = (busM / 5.5).round().clamp(120, 7200);
        duration += busSec;
        legs.add(_busLeg(ride.route, ride.dir, board, alight, busM, busSec));
        prevAlight = alight;
      }
      if (prevAlight == null) return;
      final m = distanceCalc.as(LengthUnit.Meter, LatLng(prevAlight.lat, prevAlight.lng), toPt);
      final sec = (m / 1.2).round().clamp(60, 1800);
      duration += sec;
      legs.add(_walkLeg(
        fromName: prevAlight.nameZh.isNotEmpty ? prevAlight.nameZh : prevAlight.name,
        fromLat: prevAlight.lat,
        fromLng: prevAlight.lng,
        toName: 'Destination',
        toLat: toLat,
        toLng: toLng,
        meters: m,
        sec: sec,
        fromEn: prevAlight.nameEn,
        fromPt: prevAlight.namePt,
      ));
      final hops = rides.length;
      final score = duration.toDouble() + hops * 400;
      scored.add((score: score, it: Itinerary(duration: duration, legs: legs)));
    }

    final oList = originRoutes.toList()..sort();
    final dList = destRoutes.toList()..sort();

    for (final r1 in oList.take(10)) {
      for (final r2 in dList.take(10)) {
        if (r1 == r2) continue;
        final pair = _bestNamedTransfer(
          r1: r1,
          r2: r2,
          fromPt: fromPt,
          toPt: toPt,
          boardM: boardM,
          xferM: xferM,
          distanceCalc: distanceCalc,
        );
        if (pair != null) consider(pair);
      }
    }

    // 2 transfers via origin terminals — extra nearby calls; only when OTP missed.
    if (includeTwoTransfers) {
    final hubPts = <String, LatLng>{};
    for (final r1 in oList.take(8)) {
      for (final dir in [0, 1]) {
        final s1 = _officialStops(r1, dir);
        if (s1.length < 2) continue;
        final last = s1.last;
        final key =
            '${last.lat.toStringAsFixed(4)},${last.lng.toStringAsFixed(4)}';
        hubPts.putIfAbsent(key, () => LatLng(last.lat, last.lng));
      }
    }
    final midRoutes = <String>{};
    if (hubPts.isNotEmpty) {
      final hubNear = await Future.wait([
        for (final pt in hubPts.values.take(4))
          OTPService.fetchNearbyStops(
            lat: pt.latitude,
            lng: pt.longitude,
            maxDistance: 280,
            limit: 12,
          ),
      ]);
      for (final list in hubNear) {
        for (final s in list) {
          for (final r in (s['routes'] as List? ?? const [])) {
            final name = r.toString().trim();
            if (name.isEmpty) continue;
            if (originRoutes.contains(name) || destRoutes.contains(name)) {
              continue;
            }
            midRoutes.add(name);
          }
        }
      }
      final mids = midRoutes.take(12).toList();
      if (mids.isNotEmpty) {
        await Future.wait([
          for (final r in mids) _ensureRouteStopsCached(r, lang),
        ]);
        for (final r1 in oList.take(6)) {
          for (final rMid in mids) {
            for (final r2 in dList.take(6)) {
              final hop = _bestTwoTransfer(
                r1: r1,
                rMid: rMid,
                r2: r2,
                fromPt: fromPt,
                toPt: toPt,
                boardM: boardM,
                xferM: xferM,
                distanceCalc: distanceCalc,
              );
              if (hop != null) consider(hop);
            }
          }
        }
      }
    }
    }

    scored.sort((a, b) => a.score.compareTo(b.score));
    final seen = <String>{};
    final out = <Itinerary>[];
    for (final s in scored) {
      final names = s.it.legs
          .where((l) => l.mode == 'BUS')
          .map((l) => l.routeName)
          .join('->');
      if (!seen.add(names)) continue;
      out.add(s.it);
      if (out.length >= 6) break;
    }
    return out;
  }

  List<({String route, int dir, BusStop board, BusStop alight})>? _bestNamedTransfer({
    required String r1,
    required String r2,
    required LatLng fromPt,
    required LatLng toPt,
    required double boardM,
    required double xferM,
    required Distance distanceCalc,
  }) {
    List<({String route, int dir, BusStop board, BusStop alight})>? best;
    var bestScore = double.infinity;

    for (final dir1 in [0, 1]) {
      final s1 = _officialStops(r1, dir1);
      if (s1.length < 2) continue;
      final boards = <int>[];
      for (var i = 0; i < s1.length - 1; i++) {
        final d = distanceCalc.as(
          LengthUnit.Meter,
          fromPt,
          LatLng(s1[i].lat, s1[i].lng),
        );
        if (d <= boardM) boards.add(i);
      }
      if (boards.isEmpty) continue;

      for (final dir2 in [0, 1]) {
        final s2 = _officialStops(r2, dir2);
        if (s2.length < 2) continue;
        final alights = <int>[];
        for (var j = 1; j < s2.length; j++) {
          final d = distanceCalc.as(
            LengthUnit.Meter,
            LatLng(s2[j].lat, s2[j].lng),
            toPt,
          );
          if (d <= boardM) alights.add(j);
        }
        if (alights.isEmpty) continue;

        for (final bi in boards) {
          final after = <String, int>{};
          for (var t1 = bi + 1; t1 < s1.length; t1++) {
            final k = _hubName(s1[t1]);
            if (k.isNotEmpty) after.putIfAbsent(k, () => t1);
          }
          if (after.isEmpty) continue;
          final dBoard = distanceCalc.as(
            LengthUnit.Meter,
            fromPt,
            LatLng(s1[bi].lat, s1[bi].lng),
          );

          for (final aj in alights) {
            final before = <String, int>{};
            for (var t2 = 0; t2 < aj; t2++) {
              final k = _hubName(s2[t2]);
              if (k.isNotEmpty) before[k] = t2;
            }
            var t1Idx = -1;
            var t2Idx = -1;
            for (final k in after.keys) {
              final t2 = before[k];
              if (t2 == null) continue;
              t1Idx = after[k]!;
              t2Idx = t2;
              break;
            }
            if (t1Idx < 0) {
              var minD = xferM + 1;
              for (var i = bi + 1; i < s1.length; i++) {
                for (var t2 = 0; t2 < aj; t2++) {
                  final d = distanceCalc.as(
                    LengthUnit.Meter,
                    LatLng(s1[i].lat, s1[i].lng),
                    LatLng(s2[t2].lat, s2[t2].lng),
                  );
                  if (d < minD) {
                    minD = d;
                    t1Idx = i;
                    t2Idx = t2;
                  }
                }
              }
              if (t1Idx < 0) continue;
            }
            final dAlight = distanceCalc.as(
              LengthUnit.Meter,
              LatLng(s2[aj].lat, s2[aj].lng),
              toPt,
            );
            final xfer = distanceCalc.as(
              LengthUnit.Meter,
              LatLng(s1[t1Idx].lat, s1[t1Idx].lng),
              LatLng(s2[t2Idx].lat, s2[t2Idx].lng),
            );
            final hops = (t1Idx - bi) + (aj - t2Idx);
            if (hops < 2) continue;
            final score = dBoard + dAlight + xfer + hops * 80;
            if (score < bestScore) {
              bestScore = score;
              best = [
                (route: r1, dir: dir1, board: s1[bi], alight: s1[t1Idx]),
                (route: r2, dir: dir2, board: s2[t2Idx], alight: s2[aj]),
              ];
            }
          }
        }
      }
    }
    return best;
  }

  List<({String route, int dir, BusStop board, BusStop alight})>? _bestTwoTransfer({
    required String r1,
    required String rMid,
    required String r2,
    required LatLng fromPt,
    required LatLng toPt,
    required double boardM,
    required double xferM,
    required Distance distanceCalc,
  }) {
    List<({String route, int dir, BusStop board, BusStop alight})>? best;
    var bestScore = double.infinity;

    for (final dir1 in [0, 1]) {
      final s1 = _officialStops(r1, dir1);
      if (s1.length < 2) continue;
      var board1 = -1;
      var board1D = boardM + 1;
      for (var i = 0; i < s1.length - 1; i++) {
        final d = distanceCalc.as(
          LengthUnit.Meter,
          fromPt,
          LatLng(s1[i].lat, s1[i].lng),
        );
        if (d < board1D) {
          board1D = d;
          board1 = i;
        }
      }
      if (board1 < 0) continue;
      final alight1 = s1.length - 1;
      if (alight1 <= board1) continue;

      for (final dirM in [0, 1]) {
        final sm = _officialStops(rMid, dirM);
        if (sm.length < 2) continue;
        var midBoard = -1;
        var midBoardD = xferM + 1;
        for (var i = 0; i < sm.length - 1; i++) {
          final d = distanceCalc.as(
            LengthUnit.Meter,
            LatLng(s1[alight1].lat, s1[alight1].lng),
            LatLng(sm[i].lat, sm[i].lng),
          );
          if (d < midBoardD) {
            midBoardD = d;
            midBoard = i;
          }
        }
        if (midBoard < 0) continue;

        final afterMid = <String, int>{};
        for (var i = midBoard + 1; i < sm.length; i++) {
          final k = _hubName(sm[i]);
          if (k.isNotEmpty) afterMid.putIfAbsent(k, () => i);
        }
        if (afterMid.isEmpty) continue;

        for (final dir2 in [0, 1]) {
          final s2 = _officialStops(r2, dir2);
          if (s2.length < 2) continue;
          var alight2 = -1;
          var alight2D = boardM + 1;
          for (var j = 1; j < s2.length; j++) {
            final d = distanceCalc.as(
              LengthUnit.Meter,
              LatLng(s2[j].lat, s2[j].lng),
              toPt,
            );
            if (d < alight2D) {
              alight2D = d;
              alight2 = j;
            }
          }
          if (alight2 < 0) continue;

          var midAlight = -1;
          var board2 = -1;
          for (var t2 = 0; t2 < alight2; t2++) {
            final k = _hubName(s2[t2]);
            final tMid = afterMid[k];
            if (tMid == null) continue;
            midAlight = tMid;
            board2 = t2;
            break;
          }
          if (midAlight < 0) {
            var minD = xferM + 1;
            for (var i = midBoard + 1; i < sm.length; i++) {
              for (var t2 = 0; t2 < alight2; t2++) {
                final d = distanceCalc.as(
                  LengthUnit.Meter,
                  LatLng(sm[i].lat, sm[i].lng),
                  LatLng(s2[t2].lat, s2[t2].lng),
                );
                if (d < minD) {
                  minD = d;
                  midAlight = i;
                  board2 = t2;
                }
              }
            }
          }
          if (midAlight < 0 || board2 < 0) continue;

          final score = board1D + midBoardD + alight2D + 900;
          if (score < bestScore) {
            bestScore = score;
            best = [
              (route: r1, dir: dir1, board: s1[board1], alight: s1[alight1]),
              (
                route: rMid,
                dir: dirM,
                board: sm[midBoard],
                alight: sm[midAlight],
              ),
              (route: r2, dir: dir2, board: s2[board2], alight: s2[alight2]),
            ];
          }
        }
      }
    }
    return best;
  }

  RouteLeg _walkLeg({
    required String fromName,
    required double fromLat,
    required double fromLng,
    BusStop? to,
    String? toName,
    double? toLat,
    double? toLng,
    required double meters,
    required int sec,
    String? fromEn,
    String? fromPt,
  }) {
    return RouteLeg(
      mode: 'WALK',
      duration: sec,
      fromName: fromName,
      fromNameEn: fromEn,
      fromNamePt: fromPt,
      fromLat: fromLat,
      fromLon: fromLng,
      toName: toName ?? (to!.nameZh.isNotEmpty ? to.nameZh : to.name),
      toNameEn: to?.nameEn,
      toNamePt: to?.namePt,
      toLat: toLat ?? to!.lat,
      toLon: toLng ?? to!.lng,
      geometry: '',
      routeName: '',
      distance: meters,
    );
  }

  RouteLeg _busLeg(
    String route,
    int dir,
    BusStop board,
    BusStop alight,
    double meters,
    int sec,
  ) {
    final boardName = board.nameZh.isNotEmpty ? board.nameZh : board.name;
    final alightName = alight.nameZh.isNotEmpty ? alight.nameZh : alight.name;
    final bus = RouteLeg(
      mode: 'BUS',
      duration: sec,
      fromName: boardName,
      fromNameEn: board.nameEn,
      fromNamePt: board.namePt,
      fromLat: board.lat,
      fromLon: board.lng,
      toName: alightName,
      toNameEn: alight.nameEn,
      toNamePt: alight.namePt,
      toLat: alight.lat,
      toLon: alight.lng,
      geometry: '',
      routeName: route,
      distance: meters,
      bestDir: dir,
      boardingStopSeq: board.seq,
      alightStopSeq: alight.seq,
    );
    bus.displayFromName = boardName;
    bus.displayFromNameEn = board.nameEn;
    bus.displayFromNamePt = board.namePt;
    bus.displayToName = alightName;
    bus.displayToNameEn = alight.nameEn;
    bus.displayToNamePt = alight.namePt;
    return bus;
  }

  // 🌟 動態字典翻譯 ETA 與錯誤狀態
  Future<void> enrichLeg(
    RouteLeg leg,
    LanguageController langCtrl, {
    bool includeEta = true,
  }) async {
    final route = leg.routeName;
    if (route.isEmpty) return;

    final lang = langCtrl.currentLanguage;
    await LocalTimetable.ensureLoaded();
    final at = leg.boardingTimeMacau;
    // OTP legs (boarding time known) are trusted: the GTFS has per-stop
    // times. The bundled terminal windows only gate official fallback legs.
    if (at == null) {
      if (LocalTimetable.noServiceToday(route)) {
        leg.realtimeEta = langCtrl.tr('no_service_today');
        return;
      }
      if (LocalTimetable.serviceNotStarted(route)) {
        leg.realtimeEta = langCtrl.tr('service_not_started');
        return;
      }
      if (LocalTimetable.serviceEnded(route)) {
        leg.realtimeEta = langCtrl.tr('service_ended');
        return;
      }
    }

    try {
      final matched = await matchEndpointsToOfficialRoute(
        route: route,
        fromLat: leg.fromLat,
        fromLon: leg.fromLon,
        toLat: leg.toLat,
        toLon: leg.toLon,
        lang: lang,
        otpFromName: leg.fromName,
        otpToName: leg.toName,
        nearestWithinMeters: otpLegStopMatchMeters,
        at: at,
      );

      if (matched == null) {
        // Not on official stop list (e.g. seasonal N3→黑沙) — leave seqs null
        // so the UI can skip this itinerary.
        return;
      }

      final board = matched.board;
      final alight = matched.alight;
      leg.bestDir = matched.dir;
      leg.boardingStopSeq = board.seq;
      leg.alightStopSeq = alight.seq;
      leg.displayFromName = board.nameZh.isNotEmpty ? board.nameZh : board.name;
      leg.displayFromNameEn = board.nameEn;
      leg.displayFromNamePt = board.namePt;
      leg.displayToName = alight.nameZh.isNotEmpty ? alight.nameZh : alight.name;
      leg.displayToNameEn = alight.nameEn;
      leg.displayToNamePt = alight.namePt;

      if (!includeEta) return;
      await _fillLegEta(leg, langCtrl);
    } catch (e) {
      if (includeEta) leg.realtimeEta = langCtrl.tr('conn_failed');
    }
  }

  Future<void> fillItinerariesEta(
    List<Itinerary> itineraries,
    LanguageController langCtrl,
  ) async {
    final tasks = <Future<void>>[];
    for (final it in itineraries) {
      for (final leg in it.legs) {
        if (leg.mode != 'BUS' && leg.mode != 'TRANSIT') continue;
        if (leg.realtimeEta != null && leg.realtimeEta!.isNotEmpty) continue;
        tasks.add(_fillLegEta(leg, langCtrl));
      }
    }
    if (tasks.isEmpty) return;
    await Future.wait(tasks);
    notifyListeners();
  }

  Future<void> _fillLegEta(RouteLeg leg, LanguageController langCtrl) async {
    final route = leg.routeName;
    final dir = leg.bestDir;
    final seq = leg.boardingStopSeq;
    if (route.isEmpty || dir == null || seq == null) return;
    try {
      final etaRes = await BusApiService.fetchBusETA(
        route,
        dir,
        targetStopSeq: seq,
        lang: langCtrl.currentLanguage,
      );
      if (etaRes['success'] == true && etaRes['etaData'] != null) {
        leg.realtimeEta = etaRes['etaData']['status'];
        _applyLastTripCheck(leg, etaRes, langCtrl);
      } else {
        leg.realtimeEta = langCtrl.tr('no_eta');
      }
    } catch (e) {
      leg.realtimeEta = langCtrl.tr('conn_failed');
    }
  }


  /// Near a route's last trip, use the same live ETA response to confirm a
  /// bus is still on the way to the boarding stop, or warn that the last bus
  /// may have passed. Only annotates; never hides the plan. OTP legs only.
  void _applyLastTripCheck(
    RouteLeg leg,
    Map<String, dynamic> etaRes,
    LanguageController langCtrl,
  ) {
    final at = leg.boardingTimeMacau;
    if (at == null) return;
    // Only when boarding is soon (the live feed says nothing about later).
    final mins = DateTime.fromMillisecondsSinceEpoch(leg.startTime!)
        .difference(DateTime.now())
        .inMinutes;
    if (mins > 45) return;
    if (!LocalTimetable.nearLastTrip(leg.routeName, at)) return;
    final approaching = (etaRes['approachingCount'] as int?) ?? 0;
    if (approaching > 0) {
      leg.liveCheck = 'confirmed';
      return;
    }
    if (etaRes['lastBusWindow'] == true || etaRes['serviceEnded'] == true) {
      leg.liveCheck = 'maybe_ended';
      // OTP still schedules this trip: show a warning, not "service ended".
      leg.realtimeEta = langCtrl.tr('last_bus_maybe_passed');
    }
  }

  List<LatLng> decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do { b = encoded.codeUnitAt(index++) - 63; result += (b & 0x1f) * math.pow(2, shift).toInt(); shift += 5; } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? -(result ~/ 2) - 1 : (result ~/ 2); lat += dlat;
      shift = 0; result = 0;
      do { b = encoded.codeUnitAt(index++) - 63; result += (b & 0x1f) * math.pow(2, shift).toInt(); shift += 5; } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? -(result ~/ 2) - 1 : (result ~/ 2); lng += dlng;
      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polyline;
  }

  Future<List<LatLng>> _fetchAndSliceGpx(
    String route,
    int dir,
    LatLng fromPt,
    LatLng toPt, {
    int? startSeq,
    int? endSeq,
  }) async {
    try {
      var gpx = await GPXService.fetchFullGpx(route, dir);
      var usedDir = dir;
      if (gpx.length < 2) {
        usedDir = dir == 0 ? 1 : 0;
        gpx = await GPXService.fetchFullGpx(route, usedDir);
      }
      if (gpx.length < 2) return [];

      final wrap = startSeq != null && endSeq != null && endSeq < startSeq;
      const dc = Distance();
      final duplicateEndpoints =
          dc.as(LengthUnit.Meter, fromPt, toPt) < 80;

      // 上/落 pins use OTP lat/lng. Cut GPX to those points so the line
      // reaches both ends. Seq mapping is only for duplicate coords (103).
      if (!duplicateEndpoints) {
        final sliced = _sliceGpxShortestForward(
          gpx,
          fromPt,
          toPt,
          allowWrap: wrap,
        );
        if (sliced.length >= 2) return sliced;
      }

      final bySeq = _sliceGpxByStopSeq(
        route,
        usedDir,
        gpx,
        startSeq,
        endSeq,
      );
      if (bySeq != null && bySeq.length >= 2) return bySeq;

      return _sliceGpxShortestForward(
        gpx,
        fromPt,
        toPt,
        allowWrap: wrap,
      );
    } catch (e) {
      debugPrint('GPX Slicing Error: $e');
    }
    return [];
  }

  /// Map official stops onto GPX in riding order, then cut board→alight.
  /// Needed when two stops share coordinates (103 seq 2 and seq 12).
  List<LatLng>? _sliceGpxByStopSeq(
    String route,
    int dir,
    List<LatLng> gpx,
    int? startSeq,
    int? endSeq,
  ) {
    if (startSeq == null || endSeq == null) return null;
    final stops = _officialStops(route, dir);
    if (stops.length < 2) return null;
    final boardI = stops.indexWhere((s) => s.seq == startSeq);
    final alightI = stops.indexWhere((s) => s.seq == endSeq);
    if (boardI < 0 || alightI < 0) return null;

    const dc = Distance();
    var current = 0;
    final gpxAt = List<int>.filled(stops.length, -1);
    for (var i = 0; i < stops.length; i++) {
      final stop = stops[i];
      if (stop.lat == 0.0 && stop.lng == 0.0) continue;
      final pt = LatLng(stop.lat, stop.lng);
      var best = current;
      var minD = double.infinity;
      for (var j = current; j < gpx.length; j++) {
        final d = dc.as(LengthUnit.Meter, pt, gpx[j]);
        if (d < minD) {
          minD = d;
          best = j;
        }
        if (minD < 80 && d > minD + 120) break;
      }
      gpxAt[i] = best;
      current = best;
    }

    final a = gpxAt[boardI];
    final b = gpxAt[alightI];
    if (a < 0 || b < 0) return null;

    if (boardI <= alightI) {
      if (a > b) {
        var end = a;
        var minEnd = double.infinity;
        for (var j = a; j < gpx.length; j++) {
          final d = dc.as(LengthUnit.Meter, LatLng(stops[alightI].lat, stops[alightI].lng), gpx[j]);
          if (d < minEnd) {
            minEnd = d;
            end = j;
          }
        }
        if (minEnd > 250 || end < a) return null;
        return gpx.sublist(a, end + 1);
      }
      return gpx.sublist(a, b + 1);
    }
    return [...gpx.sublist(a), ...gpx.sublist(0, b + 1)];
  }

  /// If a stop appears twice on a loop, pick the board hit that yields the
  /// shortest forward ride to the alight point.
  List<LatLng> _sliceGpxShortestForward(
    List<LatLng> gpx,
    LatLng fromPt,
    LatLng toPt, {
    bool allowWrap = false,
  }) {
    const dc = Distance();
    var minStart = double.infinity;
    for (final p in gpx) {
      final d = dc.as(LengthUnit.Meter, fromPt, p);
      if (d < minStart) minStart = d;
    }
    if (minStart > 400) minStart = 400;

    final starts = <int>[];
    var lastKept = -9999;
    for (var i = 0; i < gpx.length; i++) {
      final d = dc.as(LengthUnit.Meter, fromPt, gpx[i]);
      if (d > minStart + 40) continue;
      if (i - lastKept < 40) continue;
      starts.add(i);
      lastKept = i;
    }
    var nearest = 0;
    var nearestD = double.infinity;
    for (var i = 0; i < gpx.length; i++) {
      final d = dc.as(LengthUnit.Meter, fromPt, gpx[i]);
      if (d < nearestD) {
        nearestD = d;
        nearest = i;
      }
    }
    if (starts.isEmpty) starts.add(nearest);

    List<LatLng> best = const [];
    var bestLen = 1 << 30;
    for (final startIdx in starts) {
      var endIdx = startIdx;
      var minEnd = double.infinity;
      final limit = allowWrap ? gpx.length : (gpx.length - startIdx);
      for (var i = 0; i < limit; i++) {
        final checkIdx = allowWrap
            ? (startIdx + i) % gpx.length
            : startIdx + i;
        final d = dc.as(LengthUnit.Meter, toPt, gpx[checkIdx]);
        if (d < minEnd) {
          minEnd = d;
          endIdx = checkIdx;
        }
        if (minEnd < 80 && d > minEnd + 150) break;
      }
      if (minEnd > 250) continue;

      final List<LatLng> slice;
      if (startIdx <= endIdx) {
        slice = gpx.sublist(startIdx, endIdx + 1);
      } else if (allowWrap) {
        slice = [...gpx.sublist(startIdx), ...gpx.sublist(0, endIdx + 1)];
      } else {
        continue;
      }
      if (slice.length < 2) continue;
      if (slice.length < bestLen) {
        bestLen = slice.length;
        best = slice;
      }
    }
    return best;
  }

  bool _isUsableRouteShape(List<LatLng> pts) {
    return pts.length >= 2;
  }

  Future<LatLng?> buildPolylinesFromLegs(List<RouteLeg> legs) async {
    final List<Color> busColors = [
      Colors.orange,
      Colors.greenAccent,
      Colors.purpleAccent,
    ];

    isDrawingNavRoute = true;
    otpNavigationPolylines = [];
    navBusRoutes = [
      for (final leg in legs)
        if (leg.mode == 'BUS' || leg.mode == 'TRANSIT')
          (leg.routeName.isNotEmpty ? leg.routeName : 'BUS'),
    ];
    navBusLegsInfo = [
      for (final leg in legs)
        if (leg.mode == 'BUS' || leg.mode == 'TRANSIT') leg,
    ];
    activeBusLegIndex = 0;
    if (legs.isNotEmpty) {
      navStartPt = LatLng(legs.first.fromLat, legs.first.fromLon);
      navEndPt = LatLng(legs.last.toLat, legs.last.toLon);
    }
    notifyListeners();

    try {
    LatLng? centerPt;
    final busLegs = List<RouteLeg>.from(navBusLegsInfo);
    final gpxResults = busLegs.isEmpty
        ? <List<LatLng>>[]
        : await Future.wait([
            for (final leg in busLegs)
              _fetchAndSliceGpx(
                leg.routeName.isNotEmpty ? leg.routeName : 'BUS',
                leg.bestDir ?? 0,
                LatLng(leg.fromLat, leg.fromLon),
                LatLng(leg.toLat, leg.toLon),
                startSeq: leg.boardingStopSeq,
                endSeq: leg.alightStopSeq,
              ),
          ]);

    final drawLines = <Polyline>[];
    var busIdx = 0;
    for (final leg in legs) {
      if (leg.mode == 'WALK') {
        if (leg.geometry.isEmpty) continue;
        final pts = PolylineDecoder.decode(leg.geometry);
        if (pts.length < 2) continue;
        drawLines.add(
          Polyline(points: pts, strokeWidth: 5.0, color: Colors.blue),
        );
        centerPt ??= pts.first;
        continue;
      }
      if (leg.mode != 'BUS' && leg.mode != 'TRANSIT') continue;

      final color = busColors[busIdx % busColors.length];
      List<LatLng> pts = const [];
      if (busIdx < gpxResults.length &&
          _isUsableRouteShape(gpxResults[busIdx])) {
        pts = gpxResults[busIdx];
      } else if (leg.geometry.isNotEmpty) {
        final decoded = PolylineDecoder.decode(leg.geometry);
        if (_isUsableRouteShape(decoded)) pts = decoded;
      }
      busIdx++;
      if (!_isUsableRouteShape(pts)) continue;
      drawLines.add(
        Polyline(points: pts, strokeWidth: 6.0, color: color),
      );
      centerPt ??= pts.first;
    }

    otpNavigationPolylines = drawLines;
    return centerPt;
    } finally {
      isDrawingNavRoute = false;
      notifyListeners();
    }
  }

  // 🌟 使用字典判斷及翻譯錯誤字眼
  Future<String?> launchThirdPartyMap(
    bool isGoogle, String startText, String destText, 
    LatLng? userLoc, LatLng? customStart, LatLng? customEnd, 
    String sessionToken, String? startPlaceId, String? destPlaceId,
    LanguageController langCtrl
  ) async {
    if (startText.isEmpty) return langCtrl.tr('pls_enter_start'); 
    if (destText.isEmpty) return langCtrl.tr('pls_enter_dest'); 
    
    bool isCurrentLocation = startText == langCtrl.tr('current_gps_location') || startText.contains('GPS') || startText.contains('目前位置');
    
    LatLng? startLoc;
    if (!isCurrentLocation) {
      startLoc = await getCoordinate(startText, true, userLoc, customStart, customEnd, sessionToken, startPlaceId, langCtrl);
      if (startLoc == null) return langCtrl.tr('start_loc_invalid'); 
    }
    
    LatLng? destLoc = await getCoordinate(destText, false, userLoc, customStart, customEnd, sessionToken, destPlaceId, langCtrl);
    if (destLoc == null) return langCtrl.tr('dest_loc_invalid'); 
    
    Uri mapUri;
    
    if (isGoogle) {
      String destParam = '${destLoc.latitude},${destLoc.longitude}';
      
      if (isCurrentLocation) {
        mapUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$destParam&travelmode=transit');
      } else {
        String originParam = '${startLoc!.latitude},${startLoc.longitude}';
        mapUri = Uri.parse('https://www.google.com/maps/dir/?api=1&origin=$originParam&destination=$destParam&travelmode=transit');
      }
    } else {
      LatLng destGcj = CoordTransform.wgs84ToGcj02(destLoc.latitude, destLoc.longitude);
      
      bool isCustomEnd = destText == langCtrl.tr('custom_end') || destText.contains('地圖自選終點') || destText.contains('Custom End') || destText.contains('Fim');
      bool isCustomStart = startText == langCtrl.tr('custom_start') || startText.contains('地圖自選起點') || startText.contains('Custom Start') || startText.contains('Início');

      String encodedDestName = Uri.encodeComponent(isCustomEnd ? langCtrl.tr('map_dest_name') : destText);
      String toParam = '${destGcj.longitude},${destGcj.latitude},$encodedDestName';

      if (isCurrentLocation) {
        mapUri = Uri.parse('https://uri.amap.com/navigation?to=$toParam&mode=bus&callnative=1');
      } else {
        LatLng startGcj = CoordTransform.wgs84ToGcj02(startLoc!.latitude, startLoc.longitude);
        String encodedStartName = Uri.encodeComponent(isCustomStart ? langCtrl.tr('map_start_name') : startText);
        mapUri = Uri.parse('https://uri.amap.com/navigation?from=${startGcj.longitude},${startGcj.latitude},$encodedStartName&to=$toParam&mode=bus&callnative=1');
      }
    }

    if (await canLaunchUrl(mapUri)) {
      await launchUrl(mapUri, mode: LaunchMode.externalApplication);
      return null;
    } else {
      return langCtrl.tr('cannot_open_map'); 
    }
  }
}
