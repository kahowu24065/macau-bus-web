import 'dart:async';
import 'dart:convert'; // 🌟 新增：用於快取 JSON 編碼與解碼
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_stop.dart';
import '../models/bus.dart';
import '../services/bus_api_service.dart';
import '../services/gpx_service.dart';
import '../services/notification_service.dart';
import '../services/background_tracker_service.dart';

class BusController extends ChangeNotifier {
  String currentRoute = '102';
  int currentDirection = 0; 
  String outboundTerminal = '去程';
  String inboundTerminal = '回程';

  List<BusStop> stopsList = [];
  List<Bus> allBusesList = [];
  Map<String, dynamic>? etaData;
  dynamic timetableDetails;
  
  bool isLoadingStops = false;
  bool isLoadingETA = false;
  String? errorMessage;

  int? selectedStopSeq;
  int? boardingStopSeq;
  int? alightingStopSeq;

  String? pendingAlarmTitle;
  String? pendingAlarmBody;

  int countdownSeconds = 5;
  Timer? _autoRefreshTimer;

  List<String> allRoutesWithDir = [];
  bool isLoadingAllRoutes = false;

  List<LatLng> gpxRoutePoints = [];
  List<LatLng> cachedEstimatedCoords = [];

  List<String> favoriteRoutes = [];
  bool isSimpleMode = false;

  bool isPickingMapStart = false;
  bool isPickingMapEnd = false;
  LatLng? customMapStart;
  LatLng? customMapEnd;

  Map<String, LatLng> lastKnownBusLocations = {};

  // 設定新提醒後，第一次 ETA 只用來建立目前巴士位置基準，避免按鈕操作立即觸發通知。
  bool _skipNextBoardingAlarmCheck = false;

  BusController() {
    loadFavorites();
    _restoreTrackingState(); // 🌟 新增：啟動時檢查並還原追蹤狀態
  }

  // 🌟 新增：檢查本地儲存，還原追蹤鈴鐺狀態，或清理幽靈進程
  Future<void> _restoreTrackingState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRoute = prefs.getString('track_route');
    final savedDir = prefs.getInt('track_dir');
    final savedStopSeq = prefs.getInt('track_stop_seq');

    // 只有在當前選定的路線和方向與背景任務一致時，才點亮鈴鐺
    if (savedRoute != null && savedRoute == currentRoute && savedDir == currentDirection && savedStopSeq != null) {
      boardingStopSeq = savedStopSeq;
    } else {
      // 目前畫面不是背景提醒所屬的路線／方向時，只關閉目前畫面的鈴鐺；
      // 不要停止背景服務，否則 App 重開或切換路線時會誤殺仍然有效的提醒。
      boardingStopSeq = null;
    }
    notifyListeners();
  }

  // 🌟 新增：覆寫 setRoute 和 toggleDirection，確保切換路線時同步檢查鈴鐺狀態
  void setRoute(String route) {
    currentRoute = route.toUpperCase();
    _restoreTrackingState(); // 檢查新路線是否有正在進行的追蹤
    notifyListeners();
  }

  void toggleDirection() {
    currentDirection = currentDirection == 0 ? 1 : 0;
    _restoreTrackingState(); // 檢查新方向是否有正在進行的追蹤
    notifyListeners();
  }

  bool get isServiceEnded {
    if (timetableDetails == null) return false;
    try {
      final now = DateTime.now();
      bool isHoliday = now.weekday == DateTime.sunday; 
      
      List<dynamic> items = [];
      if (timetableDetails is List) {
        for (var sec in (timetableDetails as List)) {
          final title = sec['title']?.toString() ?? '';
          if (title.contains('每日')) {
            if (sec['items'] is List) items.addAll(sec['items']);
          } else if (isHoliday && (title.contains('假日') || title.contains('星期日'))) {
            if (sec['items'] is List) items.addAll(sec['items']);
          } else if (!isHoliday && (title.contains('一') || title.contains('工作日'))) {
            if (sec['items'] is List) items.addAll(sec['items']);
          }
        }
        if (items.isEmpty && (timetableDetails as List).isNotEmpty) {
          final firstSec = (timetableDetails as List).first;
          if (firstSec['items'] is List) items.addAll(firstSec['items']);
        }
      } else if (timetableDetails is Map) {
        final details = timetableDetails as Map<String, dynamic>;
        final key = isHoliday ? 'holiday' : 'weekday';
        if (details[key] is List) {
          items.addAll(details[key]);
        } else if (details['sections'] is List) {
          for (var sec in (details['sections'] as List)) {
            if (sec['items'] is List) items.addAll(sec['items']);
          }
        }
      }

      if (items.isEmpty) return false;

      int currentMins = now.hour * 60 + now.minute;
      int compMins = now.hour < 4 ? currentMins + 24 * 60 : currentMins;
      
      bool isRunning = false;
      bool allEnded = true;
      bool hasRange = false;
      int maxMinutes = -1;

      for (var item in items) {
        final timeStr = item['time']?.toString().trim() ?? '';
        final rangeMatch = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})').firstMatch(timeStr);
        
        if (rangeMatch != null) {
          hasRange = true;
          int h1 = int.parse(rangeMatch.group(1)!);
          int m1 = int.parse(rangeMatch.group(2)!);
          int h2 = int.parse(rangeMatch.group(3)!);
          int m2 = int.parse(rangeMatch.group(4)!);
          
          int startMins = h1 * 60 + m1;
          int endMins = h2 * 60 + m2;
          
          if (h1 < 4) startMins += 24 * 60;
          if (h2 < 4) endMins += 24 * 60;
          if (startMins > endMins) endMins += 24 * 60; 

          if (compMins >= startMins && compMins <= endMins) isRunning = true;
          if (compMins <= endMins) allEnded = false;
        } else {
          final timeMatches = RegExp(r'(\d{1,2}):(\d{2})').allMatches(timeStr);
          for (var m in timeMatches) {
            int h = int.parse(m.group(1)!);
            int min = int.parse(m.group(2)!);
            int total = h * 60 + min;
            if (h < 4) total += 24 * 60;
            if (total > maxMinutes) maxMinutes = total;
          }
        }
      }

      if (hasRange) {
        if (isRunning) return false;
        return allEnded;
      } else {
        if (maxMinutes != -1) {
          return compMins > maxMinutes;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  List<LatLng> get routePoints {
    return stopsList.where((s) => s.lat != 0.0 && s.lng != 0.0).map((s) => LatLng(s.lat, s.lng)).toList();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void clearPendingAlarm() {
    pendingAlarmTitle = null;
    pendingAlarmBody = null;
  }

  void startPickingMapStart() {
    isPickingMapStart = true;
    isPickingMapEnd = false;
    notifyListeners();
  }

  void startPickingMapEnd() {
    isPickingMapStart = false;
    isPickingMapEnd = true;
    notifyListeners();
  }

  void setCustomMapStart(LatLng? point) {
    customMapStart = point;
    isPickingMapStart = false;
    notifyListeners();
  }

  void setCustomMapEnd(LatLng? point) {
    customMapEnd = point;
    isPickingMapEnd = false;
    notifyListeners();
  }

  void cancelMapPicking() {
    isPickingMapStart = false;
    isPickingMapEnd = false;
    notifyListeners();
  }

  void clearCustomMapPoints() {
    customMapStart = null;
    customMapEnd = null;
    notifyListeners();
  }

  void toggleSimpleMode(bool value) {
    isSimpleMode = value;
    notifyListeners();
  }

  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    favoriteRoutes = prefs.getStringList('favorite_routes') ?? [];
    notifyListeners();
  }

  Future<void> toggleFavorite(String route) async {
    final cleanRoute = route.trim().toUpperCase();
    if (cleanRoute.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (favoriteRoutes.contains(cleanRoute)) {
      favoriteRoutes.remove(cleanRoute);
    } else {
      favoriteRoutes.add(cleanRoute);
    }
    await prefs.setStringList('favorite_routes', favoriteRoutes);
    notifyListeners();
  }

  Future<void> fetchAllRoutes() async {
    isLoadingAllRoutes = true;
    notifyListeners();
    final routes = await BusApiService.fetchAllRoutes();
    if (routes.isNotEmpty) {
      allRoutesWithDir = routes;
    }
    isLoadingAllRoutes = false;
    notifyListeners();
  }

  void selectStop(int seq) {
    selectedStopSeq = seq;
    notifyListeners();
  }

  Future<void> setBoardingStop(int? seq) async {
    boardingStopSeq = seq;
    _skipNextBoardingAlarmCheck = seq != null;
    final prefs = await SharedPreferences.getInstance();

    if (seq != null) {
      // 先保存，再啟動背景追蹤，避免 App 被重開時只剩背景服務而沒有 UI 狀態。
      await prefs.setString('track_route', currentRoute);
      await prefs.setInt('track_dir', currentDirection);
      await prefs.setInt('track_stop_seq', seq);

      alightingStopSeq = null;
      BackgroundTrackerService.startTracking(
        route: currentRoute,
        direction: currentDirection,
        targetStopSeq: seq,
      );
    } else {
      await prefs.remove('track_route');
      await prefs.remove('track_dir');
      await prefs.remove('track_stop_seq');
      BackgroundTrackerService.stopTracking();
    }
    notifyListeners();
  }

  void setAlightingStop(int? seq) {
    alightingStopSeq = seq;
    if (seq != null) boardingStopSeq = null;
    notifyListeners();
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    notifyListeners();
  }

  void startAutoRefresh() {
    stopAutoRefresh();
    countdownSeconds = 5;
    notifyListeners();

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownSeconds > 1) {
        countdownSeconds--;
        notifyListeners();
      } else {
        countdownSeconds = 5;
        fetchBusETA(isAutoRefresh: true);
      }
    });
  }

  // 🌟 新增：GPX 地圖路線快取機制，秒速繪製地圖紫線
  Future<void> fetchGPXRoute() async {
    if (currentRoute.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    final String cacheKey = 'cache_gpx_${currentRoute}_$currentDirection';
    final String? cachedGpx = prefs.getString(cacheKey);

    if (cachedGpx != null) {
      try {
        final List<dynamic> decoded = jsonDecode(cachedGpx);
        gpxRoutePoints = decoded.map((e) => LatLng(e['lat'], e['lng'])).toList();
        _updateEstimatedCoords();
        notifyListeners(); // 瞬間更新地圖 UI
      } catch (e) {
        debugPrint('讀取GPX快取失敗: $e');
      }
    }

    final points = await GPXService.fetchFullGpx(currentRoute, currentDirection);
    if (points.isNotEmpty) {
      gpxRoutePoints = points;
      _updateEstimatedCoords();
      notifyListeners();
      
      try {
        final jsonList = points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
        await prefs.setString(cacheKey, jsonEncode(jsonList));
      } catch (e) {
        debugPrint('寫入GPX快取失敗: $e');
      }
    }
  }

  void _updateEstimatedCoords() {
    if (gpxRoutePoints.isEmpty || stopsList.isEmpty) {
      cachedEstimatedCoords = [];
      return;
    }
    List<LatLng> estimated = [];
    final Distance distanceCalc = const Distance();
    double totalDistance = 0.0;
    List<double> cumulativeDistances = [0.0];
    for (int i = 0; i < gpxRoutePoints.length - 1; i++) {
      double dist = distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i], gpxRoutePoints[i + 1]);
      totalDistance += dist;
      cumulativeDistances.add(totalDistance);
    }
    int numStops = stopsList.length;
    double segmentLength = totalDistance / (numStops > 1 ? numStops - 1 : 1);
    for (int i = 0; i < numStops; i++) {
      if (i == 0) { estimated.add(gpxRoutePoints.first); continue; }
      if (i == numStops - 1) { estimated.add(gpxRoutePoints.last); continue; }
      double targetDistance = i * segmentLength;
      for (int j = 0; j < cumulativeDistances.length - 1; j++) {
        if (targetDistance >= cumulativeDistances[j] && targetDistance <= cumulativeDistances[j + 1]) {
          double segmentStartDist = cumulativeDistances[j];
          double segmentEndDist = cumulativeDistances[j + 1];
          double ratio = (segmentEndDist - segmentStartDist) == 0 ? 0 : (targetDistance - segmentStartDist) / (segmentEndDist - segmentStartDist);
          LatLng startPt = gpxRoutePoints[j]; LatLng endPt = gpxRoutePoints[j + 1];
          double lat = startPt.latitude + (endPt.latitude - startPt.latitude) * ratio;
          double lng = startPt.longitude + (endPt.longitude - startPt.longitude) * ratio;
          estimated.add(LatLng(lat, lng)); break;
        }
      }
    }
    while (estimated.length < numStops) { estimated.add(gpxRoutePoints.last); }
    cachedEstimatedCoords = estimated;
  }

  // 🌟 新增：站點資料快取機制，零延遲切換路線
  Future<void> fetchStops({bool keepNavigation = false}) async {
    if (currentRoute.isEmpty) return;
    stopAutoRefresh();
    
    final prefs = await SharedPreferences.getInstance();
    final String cacheKey = 'cache_stops_${currentRoute}_$currentDirection';
    final String? cachedData = prefs.getString(cacheKey);
    bool hasCache = false;

    if (cachedData != null) {
      try {
        final List<dynamic> decoded = jsonDecode(cachedData);
        stopsList = decoded.map((e) => BusStop.fromJson(e)).toList();
        if (stopsList.isNotEmpty) {
          selectedStopSeq = stopsList[0].seq;
          outboundTerminal = _formatStopName(stopsList.last.name);
          inboundTerminal = _formatStopName(stopsList.first.name);
          hasCache = true;
          notifyListeners(); // 瞬間繪製站點列表
        }
      } catch (e) {
        debugPrint('讀取站點快取失敗: $e');
      }
    }

    isLoadingStops = !hasCache; // 如果無快取，先出轉圈圈 Loading
    
    if (!hasCache) {
      stopsList = [];
      allBusesList = [];
      gpxRoutePoints = [];
      cachedEstimatedCoords = [];
      selectedStopSeq = null;
    }
    
    lastKnownBusLocations.clear();
    alightingStopSeq = null;
    errorMessage = null;

    // fetchStops 可能在啟動時清除 UI 狀態；在資料載入流程中重新恢復提醒，
    // 避免 _restoreTrackingState 與 fetchStops 的非同步執行順序造成鈴鐺變灰。
    await _restoreTrackingState();
    etaData = null;
    if (!hasCache) notifyListeners();

    // 背景繼續向 API 獲取最新資料
    final result = await BusApiService.fetchStops(currentRoute, currentDirection);
    
    if (result['success'] == true) {
      stopsList = result['stops'];
      if (stopsList.isNotEmpty) {
        selectedStopSeq = stopsList[0].seq;
        outboundTerminal = _formatStopName(stopsList.last.name);
        inboundTerminal = _formatStopName(stopsList.first.name);
        
        try {
          final jsonList = stopsList.map((e) => e.toJson()).toList();
          await prefs.setString(cacheKey, jsonEncode(jsonList));
        } catch (e) {
          debugPrint('寫入站點快取失敗: $e');
        }
      }
      isLoadingStops = false;
      notifyListeners();
      
      await fetchBusETA();
      await fetchGPXRoute(); 
    } else {
      if (!hasCache) {
        isLoadingStops = false;
        errorMessage = result['message'];
        notifyListeners();
      }
    }
  }

  Future<void> _checkBoardingAlarm() async {
    if (boardingStopSeq == null || allBusesList.isEmpty) return;
    for (var bus in allBusesList) {
      int currentSeq = bus.currentStopSeq;
      if (currentSeq > 0) {
        int stopsAway = boardingStopSeq! - currentSeq;
        if (stopsAway >= 0 && stopsAway <= 2) {
          pendingAlarmTitle = '🚌 準備上車！';
          pendingAlarmBody = '您設定的巴士即將抵達第 $boardingStopSeq 站，請準備前往站點。';
          NotificationService.showAlarm(pendingAlarmTitle!, pendingAlarmBody!);
          boardingStopSeq = null;

          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('track_route');
          await prefs.remove('track_dir');
          await prefs.remove('track_stop_seq');
          BackgroundTrackerService.stopTracking();
          
          notifyListeners();
          break;
        }
      }
    }
  }

  void checkAlightingAlarm(LatLng? userLocation) {
    if (alightingStopSeq == null || userLocation == null || stopsList.isEmpty) return;

    int stopIdx = stopsList.indexWhere((s) => s.seq == alightingStopSeq);
    if (stopIdx == -1) return;

    double lat = stopsList[stopIdx].lat;
    double lng = stopsList[stopIdx].lng;

    if (gpxRoutePoints.isNotEmpty) {
      if (stopIdx == 0) {
        lat = gpxRoutePoints.first.latitude;
        lng = gpxRoutePoints.first.longitude;
      } else if (stopIdx == stopsList.length - 1) {
        lat = gpxRoutePoints.last.latitude;
        lng = gpxRoutePoints.last.longitude;
      }
    }

    if ((lat == 0.0 || lng == 0.0 || lat < 10) && cachedEstimatedCoords.isNotEmpty && stopIdx < cachedEstimatedCoords.length) {
      lat = cachedEstimatedCoords[stopIdx].latitude;
      lng = cachedEstimatedCoords[stopIdx].longitude;
    }

    if (lat != 0.0 && lng != 0.0) {
      final Distance distanceCalc = const Distance();
      double dist = distanceCalc.as(LengthUnit.Meter, userLocation, LatLng(lat, lng));

      if (dist <= 300) {
        pendingAlarmTitle = '📍 準備下車！';
        pendingAlarmBody = '您距離第 $alightingStopSeq 站已不足 300 公尺，請準備下車。';
        NotificationService.showAlarm(pendingAlarmTitle!, pendingAlarmBody!);
        alightingStopSeq = null; 
        notifyListeners();
      }
    }
  }

  Future<void> fetchBusETA({bool isAutoRefresh = false}) async {
    if (currentRoute.isEmpty) return;
    if (stopsList.isEmpty && !isAutoRefresh) return fetchStops();
    
    if (!isAutoRefresh) {
      isLoadingETA = true;
      notifyListeners();
    }

    final result = await BusApiService.fetchBusETA(currentRoute, currentDirection, targetStopSeq: selectedStopSeq);
    
    isLoadingETA = false;
    if (result['success'] == true) {
      etaData = result['etaData'];
      allBusesList = result['allBuses'];
      
      for (var bus in allBusesList) {
        if (bus.lat != 0.0 && bus.lng != 0.0) {
          lastKnownBusLocations[bus.busLicense.trim()] = LatLng(bus.lat, bus.lng);
        }
      }

      timetableDetails = result['timetableDetails'];
      errorMessage = null; 
      
      // 設定提醒後的第一次非自動更新只建立基準，不作通知判斷。
      // 否則使用者一撳鈴鐺，該次 fetchBusETA 就可能直接符合 <= 2 站而彈通知。
      if (_skipNextBoardingAlarmCheck) {
        _skipNextBoardingAlarmCheck = false;
      } else {
        await _checkBoardingAlarm();
      }

      if (!isAutoRefresh) startAutoRefresh();
    } else {
      if (stopsList.isEmpty) {
        errorMessage = result['message'];
      }
      stopAutoRefresh();
    }
    notifyListeners();
  }

  String _formatStopName(String raw) {
    final cleanName = raw.replaceAll(RegExp(r'^[A-Z0-9/_\-\s]+'), '').trim();
    return cleanName.isNotEmpty ? cleanName : raw;
  }

  Map<String, dynamic>? findNearestStop(LatLng userLatLng) {
    if (stopsList.isEmpty) return null;
    double minDistance = double.infinity; int? nearestSeq; String? nearestName;
    final Distance distanceCalc = const Distance();

    for (int i = 0; i < stopsList.length; i++) {
      var stop = stopsList[i]; double lat = stop.lat; double lng = stop.lng;
      if (gpxRoutePoints.isNotEmpty) {
        if (i == 0) { lat = gpxRoutePoints.first.latitude; lng = gpxRoutePoints.first.longitude; } 
        else if (i == stopsList.length - 1) { lat = gpxRoutePoints.last.latitude; lng = gpxRoutePoints.last.longitude; }
      }
      if ((lat == 0.0 || lng == 0.0 || lat < 10) && cachedEstimatedCoords.isNotEmpty && i < cachedEstimatedCoords.length) {
        lat = cachedEstimatedCoords[i].latitude; lng = cachedEstimatedCoords[i].longitude;
      }
      if (lat != 0.0 && lng != 0.0) {
        double dist = distanceCalc.as(LengthUnit.Meter, userLatLng, LatLng(lat, lng));
        if (dist < minDistance) { minDistance = dist; nearestSeq = stop.seq; nearestName = stop.name; }
      }
    }
    if (nearestSeq != null) return {'seq': nearestSeq, 'name': nearestName, 'distance': minDistance.toInt()};
    return null;
  }

  LatLng? getSelectedStopCoordinate() {
    if (selectedStopSeq == null || stopsList.isEmpty) return null;
    int targetIndex = stopsList.indexWhere((s) => s.seq == selectedStopSeq);
    if (targetIndex == -1) return null;
    
    double lat = stopsList[targetIndex].lat; double lng = stopsList[targetIndex].lng;
    if (gpxRoutePoints.isNotEmpty) {
      if (targetIndex == 0) { lat = gpxRoutePoints.first.latitude; lng = gpxRoutePoints.first.longitude; } 
      else if (targetIndex == stopsList.length - 1) { lat = gpxRoutePoints.last.latitude; lng = gpxRoutePoints.last.longitude; }
    }
    if ((lat == 0.0 || lng == 0.0 || lat < 10) && cachedEstimatedCoords.isNotEmpty && targetIndex < cachedEstimatedCoords.length) {
      lat = cachedEstimatedCoords[targetIndex].latitude; lng = cachedEstimatedCoords[targetIndex].longitude;
    }
    if (lat != 0.0 && lng != 0.0) return LatLng(lat, lng);
    return null;
  }

  LatLng? snapBusToStop(Bus bus) {
    if (bus.lat != 0.0 && bus.lng != 0.0) {
      return LatLng(bus.lat, bus.lng);
    }
    
    String plate = bus.busLicense.trim();
    if (lastKnownBusLocations.containsKey(plate)) {
      return lastKnownBusLocations[plate];
    }
    
    return null;
  }
}