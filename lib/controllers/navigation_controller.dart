import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../services/places_service.dart';
import '../services/bus_api_service.dart';
import '../utils/coord_transform.dart';
import '../models/itinerary.dart';
import 'bus_controller.dart';

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
      final stopsRes = await http.get(Uri.parse('https://api.macaubus-kat1.com/api/bus-stops?route=$route&dir=$dir'));
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

      final gpxRes = await http.get(Uri.parse('https://api.macaubus-kat1.com/api/bus-gpx?route=$route&dir=$dir'));
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
  int selectedIndex = 1;
  
  bool isPlanningRoute = false;

  List<Polyline> otpNavigationPolylines = [];
  List<String> navBusRoutes = [];
  LatLng? navStartPt;
  LatLng? navEndPt;
  
  List<RouteLeg> navBusLegsInfo = [];
  int activeBusLegIndex = 0;
  
  List<Map<String, dynamic>> routingHistory = [];

  bool isRoutingWithOTP = false;
  final Map<String, dynamic> _routeDataCache = {};

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
  
  void changeTab(int index, {BusController? busCtrl}) {
    selectedIndex = index;
    busCtrl?.cancelMapPicking();
    notifyListeners();
  }

  void clearNavigation() {
    otpNavigationPolylines = [];
    navBusRoutes = [];
    navStartPt = null;
    navEndPt = null;
    navBusLegsInfo = [];
    activeBusLegIndex = 0;
    // 🌟 核心修復：刪除 `isPlanningRoute = false;`，等 UI 自己決定幾時解除隱身！
    notifyListeners();
  }

  void setActiveBusLeg(int index) {
    activeBusLegIndex = index;
    notifyListeners();
  }

  Future<LatLng?> getCoordinate(String text, bool isStart, LatLng? userLoc, LatLng? customStart, LatLng? customEnd, String sessionToken, String? placeId) async {
    if (text.isEmpty) return null;
    if (isStart) {
      if (text == '目前位置 (GPS)') return userLoc;
      if (text == '地圖自選起點 🟢' && customStart != null) return customStart;
    } else {
      if (text == '地圖自選終點 🔴' && customEnd != null) return customEnd;
    }

    if (placeId != null && placeId.isNotEmpty) {
      return await PlacesService.getDetails(placeId, sessionToken);
    } else {
      return await PlacesService.textSearch(text);
    }
  }

  Future<void> enrichLeg(RouteLeg leg) async {
    final route = leg.routeName;
    if (route.isEmpty) return;
    
    final fromLat = leg.fromLat;
    final fromLon = leg.fromLon;
    final toLat = leg.toLat;
    final toLon = leg.toLon;

    try {
      if (!_routeDataCache.containsKey('${route}_stops_0')) {
        final res0 = await BusApiService.fetchStops(route, 0);
        final res1 = await BusApiService.fetchStops(route, 1);
        if (res0['success'] == true) _routeDataCache['${route}_stops_0'] = res0['stops'];
        if (res1['success'] == true) _routeDataCache['${route}_stops_1'] = res1['stops'];
      }

      int bestDir = 0; 
      int? bestStopSeq; 
      int? bestAlightSeq; 
      double absoluteBestScore = double.infinity;
      final Distance distanceCalc = const Distance();

      for (int dir in [0, 1]) {
        final stops = _routeDataCache['${route}_stops_$dir'];
        if (stops != null && (stops as List).isNotEmpty) {
          List<double> fromDists = List.filled(stops.length, double.infinity);
          List<double> toDists = List.filled(stops.length, double.infinity);
          
          for (int i = 0; i < stops.length; i++) {
            final stopI = stops[i];
            double sLat = 0.0;
            double sLng = 0.0;
            
            try { 
              sLat = stopI.lat; 
              sLng = stopI.lng; 
            } catch (_) { 
              try { 
                sLat = double.tryParse(stopI['lat'].toString()) ?? 0.0; 
                sLng = double.tryParse(stopI['lng'].toString()) ?? 0.0; 
              } catch (_) {} 
            }

            if (sLat != 0 && sLng != 0) {
              LatLng stopPt = LatLng(sLat, sLng);
              fromDists[i] = distanceCalc.as(LengthUnit.Meter, LatLng(fromLat, fromLon), stopPt);
              toDists[i] = distanceCalc.as(LengthUnit.Meter, LatLng(toLat, toLon), stopPt);
            }
          }
          
          double minBoardingValue = double.infinity; 
          int bestBoardingIdxSoFar = -1;
          for (int j = 0; j < stops.length; j++) {
            if (fromDists[j] <= 400) {
              double bVal = fromDists[j] - j * 40.0;
              if (bVal < minBoardingValue) { 
                minBoardingValue = bVal; 
                bestBoardingIdxSoFar = j; 
              }
            }
            if (bestBoardingIdxSoFar != -1 && toDists[j] <= 400) {
              double aVal = toDists[j] + j * 40.0; 
              double currentScore = minBoardingValue + aVal;
              if (currentScore < absoluteBestScore) {
                absoluteBestScore = currentScore; 
                bestDir = dir;
                
                try { bestStopSeq = stops[bestBoardingIdxSoFar].seq; } catch (_) { bestStopSeq = stops[bestBoardingIdxSoFar]['seq']; }
                try { bestAlightSeq = stops[j].seq; } catch (_) { bestAlightSeq = stops[j]['seq']; }
              }
            }
          }
        }
      }

      if (bestStopSeq != null) {
        leg.bestDir = bestDir; 
        leg.boardingStopSeq = bestStopSeq; 
        leg.alightStopSeq = bestAlightSeq;
        
        final etaRes = await BusApiService.fetchBusETA(route, bestDir, targetStopSeq: bestStopSeq);
        if (etaRes['success'] == true && etaRes['etaData'] != null) {
          leg.realtimeEta = etaRes['etaData']['status'];
        } else {
          leg.realtimeEta = '未有預計時間';
        }
      }
    } catch (e) {
      leg.realtimeEta = '連線失敗';
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

  double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  Future<List<LatLng>> _fetchAndSliceGpx(
      String route, int dir, LatLng fromPt, LatLng toPt, int? startSeq, int? endSeq) async {
    try {
      final res = await http.get(Uri.parse('https://api.macaubus-kat1.com/api/bus-gpx?route=$route&dir=$dir')).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return [];
      
      final json = jsonDecode(res.body);
      if (json['success'] != true || json['points'] == null) return [];
      
      List<LatLng> gpx = (json['points'] as List)
          .map((p) => LatLng(_parseDouble(p['lat']), _parseDouble(p['lng'])))
          .where((l) => l.latitude != 0 && l.longitude != 0)
          .toList();
      if (gpx.isEmpty) return [];

      if (startSeq != null && endSeq != null && _routeDataCache.containsKey('${route}_stops_$dir')) {
        final stops = _routeDataCache['${route}_stops_$dir'] as List<dynamic>;
        
        int sIdx = stops.indexWhere((s) {
          try { return s.seq == startSeq; } catch(_) { return s['seq'] == startSeq; }
        });
        int eIdx = stops.indexWhere((s) {
          try { return s.seq == endSeq; } catch(_) { return s['seq'] == endSeq; }
        });
        
        if (sIdx != -1 && eIdx != -1 && sIdx <= eIdx) {
          final distanceCalc = const Distance();
          int currentGpxIdx = 0;
          int startGpxIdx = -1;
          int endGpxIdx = -1;

          for (int i = 0; i <= eIdx; i++) {
            double lat = 0;
            double lng = 0;
            try {
              lat = _parseDouble(stops[i].lat);
              lng = _parseDouble(stops[i].lng);
            } catch (_) {
              lat = _parseDouble(stops[i]['lat']);
              lng = _parseDouble(stops[i]['lng']);
            }
            
            if (lat == 0 || lng == 0) continue;
            LatLng stopPt = LatLng(lat, lng);

            double minDist = double.infinity;
            int bestIdx = currentGpxIdx;

            int upperLimit = currentGpxIdx + (gpx.length * 0.4).toInt();
            if (upperLimit > gpx.length) upperLimit = gpx.length;

            for (int j = currentGpxIdx; j < upperLimit; j++) {
              double d = distanceCalc.as(LengthUnit.Meter, stopPt, gpx[j]);
              if (d < minDist) {
                minDist = d;
                bestIdx = j;
              }
              if (minDist < 80 && d > minDist + 150) break;
            }

            currentGpxIdx = bestIdx;

            if (i == sIdx) startGpxIdx = currentGpxIdx;
            if (i == eIdx) endGpxIdx = currentGpxIdx;
          }

          if (startGpxIdx != -1 && endGpxIdx != -1 && startGpxIdx <= endGpxIdx) {
            return gpx.sublist(startGpxIdx, endGpxIdx + 1);
          } else {
            return [fromPt, toPt];
          }
        }
      }

      final distanceCalc = const Distance();
      int startIdx = 0;
      double minStartDist = double.infinity;
      for (int i = 0; i < gpx.length; i++) {
        double d = distanceCalc.as(LengthUnit.Meter, fromPt, gpx[i]);
        if (d < minStartDist) {
          minStartDist = d;
          startIdx = i;
        }
      }

      int endIdx = startIdx;
      double minEndDist = double.infinity;
      bool foundTargetArea = false;
      for (int i = 0; i < gpx.length; i++) {
        int checkIdx = (startIdx + i) % gpx.length; 
        double d = distanceCalc.as(LengthUnit.Meter, toPt, gpx[checkIdx]);
        if (d < minEndDist) {
          minEndDist = d;
          endIdx = checkIdx;
          if (d < 150) foundTargetArea = true; 
        } else if (foundTargetArea && d > minEndDist + 150) {
          break; 
        }
      }

      if (startIdx <= endIdx) {
        return gpx.sublist(startIdx, endIdx + 1);
      } else {
        List<LatLng> res = gpx.sublist(startIdx);
        res.addAll(gpx.sublist(0, endIdx + 1));
        return res;
      }
    } catch (e) {
      debugPrint('GPX Slicing Error: $e');
    }
    return [fromPt, toPt];
  }

  Future<LatLng?> buildPolylinesFromLegs(List<RouteLeg> legs) async {
    List<Polyline> drawLines = [];
    LatLng? centerPt;
    List<String> allBusRoutes = [];
    List<RouteLeg> busLegsInfo = [];
    
    final List<Color> busColors = [Colors.orange, Colors.greenAccent, Colors.purpleAccent];
    int busLegCount = 0;

    for (RouteLeg leg in legs) {
      if (leg.mode == 'WALK') {
        if (leg.geometry.isNotEmpty) {
          final pts = PolylineDecoder.decode(leg.geometry);
          if (pts.isNotEmpty) {
            drawLines.add(Polyline(points: pts, strokeWidth: 5.0, color: Colors.blue));
            centerPt ??= pts.first;
          }
        }
      } else if (leg.mode == 'BUS' || leg.mode == 'TRANSIT') {
        String routeName = leg.routeName.isNotEmpty ? leg.routeName : 'BUS';
        allBusRoutes.add(routeName);
        busLegsInfo.add(leg);

        Color currentBusColor = busColors[busLegCount % busColors.length];
        busLegCount++;

        int dir = leg.bestDir ?? 0;
        LatLng fromPt = LatLng(leg.fromLat, leg.fromLon);
        LatLng toPt = LatLng(leg.toLat, leg.toLon);
        
        List<LatLng> gpxPts = await _fetchAndSliceGpx(
            routeName, dir, fromPt, toPt, leg.boardingStopSeq, leg.alightStopSeq);

        if (gpxPts.isNotEmpty) {
          drawLines.add(Polyline(points: gpxPts, strokeWidth: 6.0, color: currentBusColor));
          centerPt ??= gpxPts.first;
        } else if (leg.geometry.isNotEmpty) {
          final pts = PolylineDecoder.decode(leg.geometry);
          if (pts.isNotEmpty) {
            drawLines.add(Polyline(points: pts, strokeWidth: 6.0, color: currentBusColor));
            centerPt ??= pts.first;
          }
        }
      }
    }

    otpNavigationPolylines = drawLines;
    navBusRoutes = allBusRoutes;
    navBusLegsInfo = busLegsInfo;
    activeBusLegIndex = 0;
    
    if (legs.isNotEmpty) {
      navStartPt = LatLng(legs.first.fromLat, legs.first.fromLon);
      navEndPt = LatLng(legs.last.toLat, legs.last.toLon);
    }
    
    notifyListeners();
    return centerPt;
  }

  Future<String?> launchThirdPartyMap(
    bool isGoogle, String startText, String destText, 
    LatLng? userLoc, LatLng? customStart, LatLng? customEnd, 
    String sessionToken, String? startPlaceId, String? destPlaceId
  ) async {
    if (startText.isEmpty) return '請先輸入起點';
    if (destText.isEmpty) return '請先輸入目的地';
    
    bool isCurrentLocation = startText == '目前位置 (GPS)';
    
    LatLng? startLoc;
    if (!isCurrentLocation) {
      startLoc = await getCoordinate(startText, true, userLoc, customStart, customEnd, sessionToken, startPlaceId);
      if (startLoc == null) return '起點無法轉換為座標';
    }
    
    LatLng? destLoc = await getCoordinate(destText, false, userLoc, customStart, customEnd, sessionToken, destPlaceId);
    if (destLoc == null) return '目的地無法轉換為座標';
    
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
      String encodedDestName = Uri.encodeComponent(destText == '地圖自選終點 🔴' ? '目的地' : destText);
      String toParam = '${destGcj.longitude},${destGcj.latitude},$encodedDestName';

      if (isCurrentLocation) {
        mapUri = Uri.parse('https://uri.amap.com/navigation?to=$toParam&mode=bus&callnative=1');
      } else {
        LatLng startGcj = CoordTransform.wgs84ToGcj02(startLoc!.latitude, startLoc.longitude);
        String encodedStartName = Uri.encodeComponent(startText == '地圖自選起點 🟢' ? '起點' : startText);
        mapUri = Uri.parse('https://uri.amap.com/navigation?from=${startGcj.longitude},${startGcj.latitude},$encodedStartName&to=$toParam&mode=bus&callnative=1');
      }
    }

    if (await canLaunchUrl(mapUri)) {
      await launchUrl(mapUri, mode: LaunchMode.externalApplication);
      return null;
    } else {
      return '無法打開地圖連結';
    }
  }
}