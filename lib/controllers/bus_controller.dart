import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_stop.dart';
import '../models/bus.dart';
import '../services/bus_api_service.dart';
import '../services/open_data_config.dart';
import '../constants/feature_flags.dart';
import '../services/gpx_service.dart';
import '../services/notification_service.dart';
import '../services/background_tracker_service.dart';
import '../services/boarding_reminder_client.dart';
import '../services/live_activity_bridge.dart';
import '../utils/boarding_bus_choice.dart';
import '../data/local_route_catalog.dart';


class BusController extends ChangeNotifier {
  String currentRoute = '';
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

  /// Seconds between automatic `/bus-eta` polls while a route stays open.
  /// The server reuses one transport-bureau snapshot for about this long,
  /// so auto-refresh should not ask more often than that. A manual refresh
  /// still calls [fetchBusETA] immediately.
  static const int etaAutoRefreshSeconds = 10;

  int countdownSeconds = etaAutoRefreshSeconds;
  Timer? _autoRefreshTimer;
  bool _etaInFlight = false;
  int _etaRequestId = 0;
  String _etaShownRoute = '';
  int _etaShownDir = -1;

  List<String> allRoutesWithDir = [];
  /// Festival / special-service routes (節日特別班次), from the server's
  /// specialRoutes (bundled list until the first successful fetch).
  List<String> specialRoutes = List<String>.from(LocalRouteCatalog.special);
  bool isLoadingAllRoutes = false;

  List<LatLng> gpxRoutePoints = [];
  List<List<LatLng>> gpxRouteLines = [];
  List<LatLng> cachedEstimatedCoords = [];
  final Set<int> _stopsMissingOfficialCoords = {};
  final Map<String, _BusLegMotion> _legMotion = {};
  final Map<String, double> _segmentMetersCache = {};
  List<int>? _stopGpxIndex;

  String _currentRoutesLang = 'zh';
  Future<void>? _allRoutesInFlight;
  String? _allRoutesInFlightLang;
  String? _catalogNetworkLang;
  
  // 🌟 核心變數：儲存當前語言，由 UI 即時更新，供所有 API 請求使用
  String currentLang = 'zh';

  // 🌟 新增：翻譯函數接口，等 UI 將翻譯機傳入嚟
  String Function(String key)? tr;

  List<String> favoriteRoutes = [];
  bool isSimpleMode = false;

  bool isPickingMapStart = false;
  bool isPickingMapEnd = false;
  LatLng? customMapStart;
  LatLng? customMapEnd;

  final Map<String, BoardingPoint> _lastBusFix = {};
  String? _boardingReminderId;
  bool _boardingRestorePosted = false;

  static const String _reminderIdKey = 'boarding_reminder_id';
  static const String _reminderRouteKey = 'boarding_reminder_route';
  static const String _reminderDirKey = 'boarding_reminder_dir';
  static const String _reminderStopKey = 'boarding_reminder_stop';
  static const String _reminderLicenseKey = 'boarding_reminder_license';
  static const String _reminderLatKey = 'boarding_reminder_lat';
  static const String _reminderLngKey = 'boarding_reminder_lng';
  static const String _reminderNameKey = 'boarding_reminder_stop_name';
  static const String _reminderStartedKey = 'boarding_reminder_started_at';
  static const String _reminderTokenKey = 'boarding_reminder_activity_token';
  static const String _reminderPushStartKey = 'boarding_reminder_push_to_start';
  static const String _reminderStopsKey = 'boarding_reminder_stops';
  static const String _reminderLangKey = 'boarding_reminder_lang';

  static const Duration _stopsDiskTtl = Duration(days: 1);
  static const Duration _gpxDiskTtl = Duration(days: 30);
  static const Duration _routesDiskTtl = Duration(days: 1);

  /// v2: open-data pole codes (`M198/2`). v1 (`cache_stops_...`) may still hold
  /// DSAT-era codes such as bare `M198` and is left unread.
  /// Favourites are route ids (`favorite_routes`), and boarding alarms are
  /// route + direction + stop sequence, so a pole-code change does not drop them.
  static const String _stopsCacheKeyPrefix = 'cache_stops_v2';

  /// v2: bridge decks stay in the polyline. v1 (`cache_route_shape_$route_$dir`)
  /// stored the pre-1.0.27 split, which dropped Lotus Bridge and Ponte Macau.
  /// Those entries are left unread so a 30-day cache cannot redraw the gap.
  static const String _gpxCacheKeyPrefix = 'cache_route_shape_v2';

  bool _isDiskCacheFresh(SharedPreferences prefs, String key, Duration ttl) {
    final ts = prefs.getInt('${key}_ts');
    if (ts == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)) < ttl;
  }

  Future<void> _writeDiskCache(SharedPreferences prefs, String key, String value) async {
    await prefs.setString(key, value);
    await prefs.setInt('${key}_ts', DateTime.now().millisecondsSinceEpoch);
  }

  List<BusStop> _stopsFromDiskJson(String cachedData) {
    final List<dynamic> decoded = jsonDecode(cachedData);
    return decoded.map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      map['hasAlert'] = false;
      map.remove('alertUrl');
      map.remove('suspendState');
      return BusStop.fromJson(map);
    }).toList();
  }

  BusController() {
    allRoutesWithDir = List<String>.from(LocalRouteCatalog.zh);
    loadFavorites();
    _restoreTrackingState(); 
    _loadSimpleModePreference();
    OpenDataConfig.instance.addListener(_onOpenDataConfig);
    unawaited(OpenDataConfig.instance.ensureLoaded());
  }

  bool get showLiveArrivals => OpenDataConfig.instance.showLiveArrivals;
  bool get showRouteNotices => OpenDataConfig.instance.showRouteNotices;

  void _onOpenDataConfig() {
    if (!showLiveArrivals && (allBusesList.isNotEmpty || _legMotion.isNotEmpty)) {
      allBusesList = [];
      _legMotion.clear();
    }
    notifyListeners();
  }

  Future<void> _loadSimpleModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    isSimpleMode = prefs.getBool('is_simple_mode') ?? false;
    notifyListeners();
  }

  Future<void> _restoreTrackingState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRoute = prefs.getString(_reminderRouteKey);
    final savedDir = prefs.getInt(_reminderDirKey);
    final savedStopSeq = prefs.getInt(_reminderStopKey);

    if (savedRoute != null && savedRoute == currentRoute && savedDir == currentDirection && savedStopSeq != null) {
      boardingStopSeq = savedStopSeq;
      _boardingReminderId = prefs.getString(_reminderIdKey);
      if (!_boardingRestorePosted && _boardingReminderId != null) {
        _boardingRestorePosted = true;
        unawaited(_repostBoardingReminder());
      }
    } else {
      boardingStopSeq = null;
    }
    notifyListeners();
  }

  void setRoute(String route) {
    currentRoute = route.toUpperCase();
    _restoreTrackingState(); 
    notifyListeners();
    
    SharedPreferences.getInstance().then((prefs) {
      if (currentRoute.isNotEmpty) {
        prefs.setString('last_searched_route', currentRoute);
      }
    });
  }

  void toggleDirection() {
    currentDirection = currentDirection == 0 ? 1 : 0;
    _restoreTrackingState(); 
    notifyListeners();
  }

  List<dynamic> _getTodayTimetableItems() {
    if (timetableDetails == null) return [];
    try {
      final now = DateTime.now();
      bool isHoliday = now.weekday == DateTime.sunday;
      bool isSaturday = now.weekday == DateTime.saturday;

      List<dynamic> items = [];
      
      void extractItemsFromSections(List sections) {
        for (var sec in sections) {
          final title = sec['title']?.toString() ?? '';
          bool addThis = false;
          if (title.contains('每日')) {
            addThis = true;
          } else if (isHoliday && (title.contains('假日') || title.contains('日'))) {
            addThis = true;
          } else if (isSaturday && (title.contains('六') || title.contains('假日'))) {
            addThis = true;
          } else if (!isHoliday && !isSaturday && (title.contains('一') || title.contains('工作日'))) {
            addThis = true;
          }
          
          if (addThis && sec['items'] is List) {
            items.addAll(sec['items']);
          }
        }
        if (items.isEmpty && sections.isNotEmpty) {
          final firstSec = sections.first;
          if (firstSec['items'] is List) items.addAll(firstSec['items']);
        }
      }

      if (timetableDetails is List) {
        extractItemsFromSections(timetableDetails as List);
      } else if (timetableDetails is Map) {
        final details = timetableDetails as Map<String, dynamic>;
        final key = (isHoliday || isSaturday) ? 'holiday' : 'weekday';
        if (details[key] is List) {
          items.addAll(details[key]);
        } else if (details['sections'] is List) {
          extractItemsFromSections(details['sections'] as List);
        }
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  int _getServiceState() {
    try {
      List<dynamic> items = _getTodayTimetableItems();
      if (items.isEmpty) return 0; 

      final now = DateTime.now();
      int currentMins = now.hour * 60 + now.minute;

      bool isRunning = false;
      bool hasFutureBlock = false;
      bool hasPastBlock = false;
      bool hasValidTime = false; 

      for (var item in items) {
        final timeStr = item['time']?.toString().trim() ?? '';
        
        if (timeStr.contains('不設服務')) continue; 
        
        hasValidTime = true; 

        final rangeMatch = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})').firstMatch(timeStr);
        
        if (rangeMatch != null) {
          int h1 = int.parse(rangeMatch.group(1)!);
          int m1 = int.parse(rangeMatch.group(2)!);
          int h2 = int.parse(rangeMatch.group(3)!);
          int m2 = int.parse(rangeMatch.group(4)!);
          
          int startMins = h1 * 60 + m1;
          int endMins = h2 * 60 + m2;
          
          if (startMins <= endMins) {
            if (currentMins >= startMins && currentMins <= endMins) isRunning = true;
            if (currentMins < startMins) hasFutureBlock = true;
            if (currentMins > endMins) hasPastBlock = true;
          } else {
            // Overnight window (e.g. 22:00-06:00).
            if (currentMins >= startMins || currentMins <= endMins) {
              isRunning = true;
            } else {
              hasPastBlock = true;
              hasFutureBlock = true;
            }
          }
        } else {
          final timeMatches = RegExp(r'(\d{1,2}):(\d{2})').allMatches(timeStr);
          for (var m in timeMatches) {
            int h = int.parse(m.group(1)!);
            int min = int.parse(m.group(2)!);
            int timeMins = h * 60 + min;
            
            if ((currentMins - timeMins).abs() <= 2) isRunning = true;
            if (timeMins > currentMins) hasFutureBlock = true;
            if (timeMins < currentMins) hasPastBlock = true;
          }
        }
      }

      if (!hasValidTime && items.isNotEmpty) return 3;

      if (isRunning) return 0;
      // Midday gap between peaks still has later trips — not "ended" and not "not started".
      if (hasFutureBlock && hasPastBlock) return 0;
      if (hasFutureBlock) return 2;
      return 1; 
    } catch (e) {
      return 0;
    }
  }

  bool get isServiceEnded => _getServiceState() == 1;
  bool get isServiceNotStarted => _getServiceState() == 2;
  bool get isNoServiceToday => _getServiceState() == 3; 

  List<LatLng> get routePoints {
    return stopsList.where((s) => s.lat != 0.0 && s.lng != 0.0).map((s) => LatLng(s.lat, s.lng)).toList();
  }

  @override
  void dispose() {
    OpenDataConfig.instance.removeListener(_onOpenDataConfig);
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

  Future<void> toggleSimpleMode(bool value) async {
    isSimpleMode = value;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_simple_mode', value);
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

  Future<void> fetchAllRoutes({String lang = 'zh'}) async {
    if (allRoutesWithDir.isEmpty || _currentRoutesLang != lang) {
      allRoutesWithDir = List<String>.from(LocalRouteCatalog.forLang(lang));
      _currentRoutesLang = lang;
      isLoadingAllRoutes = false;
      notifyListeners();
    }

    if (_catalogNetworkLang == lang) return;
    if (_allRoutesInFlight != null && _allRoutesInFlightLang == lang) return;

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cache_all_routes_$lang';
    unawaited(_refreshAllRoutes(lang, prefs, cacheKey));
  }

  Future<void> _refreshAllRoutes(
    String lang,
    SharedPreferences prefs,
    String cacheKey,
  ) async {
    if (_allRoutesInFlight != null && _allRoutesInFlightLang == lang) {
      return;
    }

    final future = () async {
      final routes = await BusApiService.fetchAllRoutes(lang: lang);
      if (routes.isNotEmpty) {
        allRoutesWithDir = routes;
        _currentRoutesLang = lang;
        _catalogNetworkLang = lang;
        final special = BusApiService.lastSpecialRoutes;
        if (special != null) specialRoutes = special;
        try {
          if (special != null) await prefs.setStringList('cache_special_routes', special);
          await prefs.setStringList(cacheKey, routes);
          await prefs.setInt('${cacheKey}_ts', DateTime.now().millisecondsSinceEpoch);
        } catch (e) {
          debugPrint('寫入路線清單快取失敗: $e');
        }
        notifyListeners();
      } else {
        final cached = prefs.getStringList(cacheKey);
        if (cached != null &&
            cached.isNotEmpty &&
            _isDiskCacheFresh(prefs, cacheKey, _routesDiskTtl)) {
          allRoutesWithDir = cached;
          specialRoutes = prefs.getStringList('cache_special_routes') ?? specialRoutes;
          _currentRoutesLang = lang;
          notifyListeners();
        }
      }
      isLoadingAllRoutes = false;
    }();
    _allRoutesInFlightLang = lang;
    _allRoutesInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_allRoutesInFlight, future)) {
        _allRoutesInFlight = null;
        _allRoutesInFlightLang = null;
      }
    }
  }
  
  void selectStop(int seq) {
    selectedStopSeq = seq;
    notifyListeners();
  }

  /// Arms one server-side estimate for the nearest bus, or clears it.
  ///
  /// The phone does not poll and does not estimate minutes. A failure leaves
  /// the reminder off and returns a translation key for the screen to show.
  Future<BoardingReminderOutcome> setBoardingStop(int? seq) async {
    if (seq == null) {
      await _clearBoardingReminder();
      return const BoardingReminderOutcome.cleared();
    }

    final stop = _stopBySeq(seq);
    final choice = chooseBoardingBus(
      buses: [
        for (final bus in allBusesList)
          BoardingBusInput(
            license: bus.busLicense,
            lat: bus.lat,
            lng: bus.lng,
            currentStopSeq: bus.currentStopSeq,
            atStop: bus.atStop,
          ),
      ],
      targetSeq: seq,
      target: stop == null ? null : BoardingPoint(stop.lat, stop.lng, seq: stop.seq),
      stops: [
        for (final item in stopsList)
          BoardingPoint(item.lat, item.lng, seq: item.seq),
      ],
      routePoints: [
        for (final point in gpxRoutePoints)
          BoardingPoint(point.latitude, point.longitude),
      ],
      lastRecorded: _lastBusFix,
    );
    if (!choice.ok) {
      return BoardingReminderOutcome.failed(
        boardingChoiceMessageKey(choice.failure ?? BoardingChoiceFailure.noApproachingBus),
      );
    }

    final stopName = stop == null ? '' : stop.getLocalizedName(currentLang);
    final pushToStart = await LiveActivityBridge.pushToStartToken();
    String? activityToken;
    if (pushToStart == null) {
      activityToken = await LiveActivityBridge.startActivity(
        route: currentRoute,
        stopName: stopName,
        minutes: 0,
        text: stopName,
      );
    }

    final reminderId = 'br-${DateTime.now().microsecondsSinceEpoch}';
    final stopsPayload = [
      for (final item in stopsList) {'seq': item.seq, 'lat': item.lat, 'lng': item.lng},
    ];
    final response = await BoardingReminderClient.register({
      'reminderId': reminderId,
      'route': currentRoute,
      'dir': currentDirection,
      'targetSeq': seq,
      'stopName': stopName,
      'busLicense': choice.license,
      'lat': choice.lat,
      'lng': choice.lng,
      'lang': currentLang,
      if (activityToken != null) 'activityToken': activityToken,
      if (pushToStart != null) 'pushToStartToken': pushToStart,
      'stops': stopsPayload,
    });
    if (!response.ok) {
      await LiveActivityBridge.end();
      return BoardingReminderOutcome.failed(boardingServerMessageKey(response.code));
    }

    if (activityToken != null && response.text != null) {
      await LiveActivityBridge.update(
        minutes: response.minutes ?? 0,
        text: response.text!,
      );
    }

    _boardingRestorePosted = true;
    _boardingReminderId = reminderId;
    boardingStopSeq = seq;
    alightingStopSeq = null;
    _listenForActivityToken(reminderId);
    await _saveBoardingReminder(
      reminderId: reminderId,
      seq: seq,
      license: choice.license!,
      lat: choice.lat!,
      lng: choice.lng!,
      stopName: stopName,
      startedAt: response.startedAt,
      activityToken: activityToken,
      pushToStart: pushToStart,
      stopsPayload: stopsPayload,
    );
    await _stopLegacyBoardingPoll();
    notifyListeners();
    return const BoardingReminderOutcome.started();
  }

  BusStop? _stopBySeq(int seq) {
    for (final stop in stopsList) {
      if (stop.seq == seq) return stop;
    }
    return null;
  }

  void _rememberBusFixes(List<Bus> buses) {
    for (final bus in buses) {
      if (bus.busLicense.isEmpty) continue;
      if (!boardingCoordsUsable(bus.lat, bus.lng)) continue;
      _lastBusFix[bus.busLicense] = BoardingPoint(bus.lat, bus.lng);
    }
  }

  void _listenForActivityToken(String reminderId) {
    LiveActivityBridge.onActivityToken = (token) {
      if (_boardingReminderId != reminderId || token.isEmpty) return;
      unawaited(BoardingReminderClient.register({
        'reminderId': reminderId,
        'activityToken': token,
      }));
    };
  }

  Future<void> _saveBoardingReminder({
    required String reminderId,
    required int seq,
    required String license,
    required double lat,
    required double lng,
    required String stopName,
    required int? startedAt,
    required String? activityToken,
    required String? pushToStart,
    required List<Map<String, dynamic>> stopsPayload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reminderIdKey, reminderId);
    await prefs.setString(_reminderRouteKey, currentRoute);
    await prefs.setInt(_reminderDirKey, currentDirection);
    await prefs.setInt(_reminderStopKey, seq);
    await prefs.setString(_reminderLicenseKey, license);
    await prefs.setDouble(_reminderLatKey, lat);
    await prefs.setDouble(_reminderLngKey, lng);
    await prefs.setString(_reminderNameKey, stopName);
    await prefs.setInt(_reminderStartedKey, startedAt ?? DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(_reminderLangKey, currentLang);
    await prefs.setString(_reminderStopsKey, jsonEncode(stopsPayload));
    if (activityToken != null) {
      await prefs.setString(_reminderTokenKey, activityToken);
    } else {
      await prefs.remove(_reminderTokenKey);
    }
    if (pushToStart != null) {
      await prefs.setString(_reminderPushStartKey, pushToStart);
    } else {
      await prefs.remove(_reminderPushStartKey);
    }
  }

  Future<void> _repostBoardingReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final body = _reminderBodyFromPrefs(prefs);
    if (body == null) return;
    _boardingReminderId = body['reminderId'] as String?;
    _listenForActivityToken(_boardingReminderId ?? '');
    final response = await BoardingReminderClient.register(body);
    if (response.code == 'passed' || response.code == 'segment_times_missing') {
      await _clearBoardingReminder();
    }
  }

  Map<String, dynamic>? _reminderBodyFromPrefs(SharedPreferences prefs) {
    final id = prefs.getString(_reminderIdKey);
    final lat = prefs.getDouble(_reminderLatKey);
    final lng = prefs.getDouble(_reminderLngKey);
    final seq = prefs.getInt(_reminderStopKey);
    if (id == null || lat == null || lng == null || seq == null) return null;
    List<dynamic> stops = const [];
    final rawStops = prefs.getString(_reminderStopsKey);
    if (rawStops != null) {
      try {
        final decoded = jsonDecode(rawStops);
        if (decoded is List) stops = decoded;
      } catch (_) {}
    }
    return {
      'reminderId': id,
      'route': prefs.getString(_reminderRouteKey) ?? currentRoute,
      'dir': prefs.getInt(_reminderDirKey) ?? currentDirection,
      'targetSeq': seq,
      'stopName': prefs.getString(_reminderNameKey) ?? '',
      'busLicense': prefs.getString(_reminderLicenseKey) ?? '',
      'lat': lat,
      'lng': lng,
      'lang': prefs.getString(_reminderLangKey) ?? currentLang,
      'startedAt': prefs.getInt(_reminderStartedKey),
      if ((prefs.getString(_reminderTokenKey) ?? '').isNotEmpty)
        'activityToken': prefs.getString(_reminderTokenKey),
      if ((prefs.getString(_reminderPushStartKey) ?? '').isNotEmpty)
        'pushToStartToken': prefs.getString(_reminderPushStartKey),
      'stops': stops,
    };
  }

  Future<void> _clearBoardingReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final id = _boardingReminderId ?? prefs.getString(_reminderIdKey);
    boardingStopSeq = null;
    _boardingReminderId = null;
    LiveActivityBridge.onActivityToken = null;
    await LiveActivityBridge.end();
    if (id != null && id.isNotEmpty) {
      await BoardingReminderClient.cancel(id);
    }
    await prefs.remove(_reminderIdKey);
    await prefs.remove(_reminderRouteKey);
    await prefs.remove(_reminderDirKey);
    await prefs.remove(_reminderStopKey);
    await prefs.remove(_reminderLicenseKey);
    await prefs.remove(_reminderLatKey);
    await prefs.remove(_reminderLngKey);
    await prefs.remove(_reminderNameKey);
    await prefs.remove(_reminderStartedKey);
    await prefs.remove(_reminderTokenKey);
    await prefs.remove(_reminderPushStartKey);
    await prefs.remove(_reminderStopsKey);
    await prefs.remove(_reminderLangKey);
    await _stopLegacyBoardingPoll();
    notifyListeners();
  }

  Future<void> _stopLegacyBoardingPoll() async {
    try {
      await BackgroundTrackerService.stopTracking();
    } catch (e) {
      debugPrint('stop boarding poll: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('track_route');
      await prefs.remove('track_dir');
      await prefs.remove('track_stop_seq');
    }
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
    countdownSeconds = etaAutoRefreshSeconds;
    notifyListeners();

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      advanceBusMotion();
      if (_etaInFlight) return;
      if (countdownSeconds > 1) {
        countdownSeconds--;
        notifyListeners();
      } else {
        countdownSeconds = etaAutoRefreshSeconds;
        fetchBusETA(isAutoRefresh: true);
      }
    });
  }

  Future<void> fetchGPXRoute() async {
    if (!FeatureFlags.showRouteTrajectory) {
      if (gpxRoutePoints.isNotEmpty || gpxRouteLines.isNotEmpty || cachedEstimatedCoords.isNotEmpty) {
        gpxRoutePoints = [];
        gpxRouteLines = [];
        cachedEstimatedCoords = [];
        _stopGpxIndex = null;
        notifyListeners();
      }
      return;
    }
    if (currentRoute.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final String cacheKey = '${_gpxCacheKeyPrefix}_${currentRoute}_$currentDirection';
    final String? cachedGpx = prefs.getString(cacheKey);
    final bool gpxFresh = cachedGpx != null && _isDiskCacheFresh(prefs, cacheKey, _gpxDiskTtl);

    if (gpxFresh) {
      try {
        _applyRouteLines(GPXService.linesFromCached(jsonDecode(cachedGpx)));
        _updateEstimatedCoords();
        notifyListeners();
      } catch (e) {
        debugPrint('讀取GPX快取失敗: $e');
      }
    }

    final lines = await GPXService.fetchRouteLines(currentRoute, currentDirection);
    if (lines.isNotEmpty) {
      _applyRouteLines(lines);
      _updateEstimatedCoords();
      notifyListeners();

      try {
        final jsonList = [
          for (final line in gpxRouteLines)
            [
              for (final p in line) {'lat': p.latitude, 'lng': p.longitude},
            ],
        ];
        await _writeDiskCache(prefs, cacheKey, jsonEncode(jsonList));
      } catch (e) {
        debugPrint('寫入GPX快取失敗: $e');
      }
    } else if (!gpxFresh && cachedGpx != null) {
      try {
        _applyRouteLines(GPXService.linesFromCached(jsonDecode(cachedGpx)));
        _updateEstimatedCoords();
        notifyListeners();
      } catch (e) {
        debugPrint('讀取過期GPX快取失敗: $e');
      }
    }
  }

  void _applyRouteLines(List<List<LatLng>> lines) {
    final drawable = [
      for (final line in lines)
        if (line.length >= 2) line,
    ];
    gpxRouteLines = drawable;
    if (drawable.isEmpty) {
      gpxRoutePoints = [];
      return;
    }
    gpxRoutePoints = drawable.reduce((a, b) => a.length >= b.length ? a : b);
  }

  void _updateEstimatedCoords() {
    _segmentMetersCache.clear();
    if (gpxRoutePoints.isEmpty || stopsList.isEmpty) {
      cachedEstimatedCoords = [];
      _stopGpxIndex = null;
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
    _fillMissingStopCoordinates();
    // 暫時關閉：頭尾站唔再 snap 去路線端點
    // _snapTerminalStopsToRouteEnds();
    _rebuildStopGpxIndex();
  }

  /*
  /// 每條線嘅第一站同最後一站固定放喺紫色路線嘅起點同終點。
  /// 暫時關閉：頭尾站唔再 snap 去路線端點
  void _snapTerminalStopsToRouteEnds() {
    if (gpxRoutePoints.length < 2 || stopsList.length < 2) return;
    final start = gpxRoutePoints.first;
    final end = gpxRoutePoints.last;
    final next = List<BusStop>.from(stopsList);
    next[0] = next[0].copyWith(lat: start.latitude, lng: start.longitude);
    next[next.length - 1] = next[next.length - 1].copyWith(lat: end.latitude, lng: end.longitude);
    stopsList = next;
    _segmentMetersCache.clear();
    _rebuildStopGpxIndex();
  }
  */

  /// 每一站都鎖喺上一站之後：1→2→3→4→5…直到最後一站。唔准跳去更後嘅回程。
  void _rebuildStopGpxIndex() {
    _stopGpxIndex = null;
    final points = gpxRoutePoints;
    final stops = stopsList;
    if (points.length < 2 || stops.length < 2) return;
    final last = points.length - 1;
    final indices = List<int>.filled(stops.length, -1);
    indices[0] = 0;
    indices[stops.length - 1] = last;
    var cursor = 0;
    for (int s = 1; s < stops.length - 1; s++) {
      final stop = stops[s];
      if (stop.lat == 0.0 || stop.lng == 0.0) continue;
      final matched = _matchNextGpxIndex(cursor, LatLng(stop.lat, stop.lng));
      if (matched == null || matched <= cursor || matched >= last) continue;
      indices[s] = matched;
      cursor = matched;
    }
    var prev = 0;
    for (int s = 1; s < indices.length; s++) {
      if (indices[s] < 0) continue;
      if (indices[s] <= indices[prev]) {
        indices[s] = -1;
      } else {
        prev = s;
      }
    }
    for (int s = 1; s < indices.length - 1; s++) {
      if (indices[s] >= 0) continue;
      var left = s - 1;
      while (left > 0 && indices[left] < 0) {
        left--;
      }
      var right = s + 1;
      while (right < indices.length - 1 && indices[right] < 0) {
        right++;
      }
      final gap = right - left;
      final raw = indices[left] + ((indices[right] - indices[left]) * (s - left) / gap).round();
      final lo = indices[left] + 1;
      final hi = indices[right];
      indices[s] = hi <= lo ? hi : raw.clamp(lo, hi);
    }
    for (int s = 1; s < indices.length - 1; s++) {
      if (indices[s] <= indices[s - 1]) {
        indices[s] = (indices[s - 1] + 1).clamp(0, last);
      }
      if (indices[s] >= last) indices[s] = last - 1;
    }
    indices[0] = 0;
    indices[indices.length - 1] = last;
    _stopGpxIndex = indices;
  }

  /// 由上一站之後向前行，貼到呢一站就停，唔再睇更後、更貼嘅回程。
  int? _matchNextGpxIndex(int cursor, LatLng target) {
    const nearMeters = 120.0;
    const leaveMeters = 250.0;
    const distanceCalc = Distance();
    var best = double.infinity;
    var bestI = -1;
    var sinceBest = 0.0;
    for (int i = cursor + 1; i < gpxRoutePoints.length - 1; i++) {
      final d = distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i], target);
      final step = distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i - 1], gpxRoutePoints[i]);
      if (d < best) {
        best = d;
        bestI = i;
        sinceBest = 0;
      } else {
        sinceBest += step;
        if (best <= nearMeters && sinceBest >= leaveMeters) break;
      }
    }
    if (bestI < 0) return null;
    for (int i = cursor + 1; i <= bestI; i++) {
      final d = distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i], target);
      if (d <= best + 45) return i;
    }
    return bestI;
  }

  bool _hasOfficialCoords(BusStop stop) {
    return !_stopsMissingOfficialCoords.contains(stop.seq) &&
        stop.lat != 0.0 &&
        stop.lng != 0.0;
  }

  void _rememberMissingOfficialCoords() {
    _stopsMissingOfficialCoords
      ..clear()
      ..addAll(
        stopsList
            .where((s) => s.lat == 0.0 || s.lng == 0.0)
            .map((s) => s.seq),
      );
  }

  /// 官方冇座標嘅站（任何路線）用前後站沿路線補位。
  /// 頭尾站冇鄰站可夾時，改用路線比例位置，車站圓點同架車先會同一點。
  void _fillMissingStopCoordinates() {
    if (stopsList.isEmpty || _stopsMissingOfficialCoords.isEmpty) return;
    final filled = List<BusStop>.from(stopsList);
    bool changed = false;
    for (int i = 0; i < filled.length; i++) {
      if (!_stopsMissingOfficialCoords.contains(filled[i].seq)) continue;
      final pt = _estimateMissingStop(filled, i);
      if (pt == null) continue;
      filled[i] = filled[i].copyWith(lat: pt.latitude, lng: pt.longitude);
      changed = true;
    }
    if (changed) stopsList = filled;
  }

  LatLng? _estimateMissingStop(List<BusStop> filled, int i) {
    int prev = i - 1;
    while (prev >= 0 && !_hasOfficialCoords(filled[prev])) {
      prev--;
    }
    int next = i + 1;
    while (next < filled.length && !_hasOfficialCoords(filled[next])) {
      next++;
    }
    if (prev >= 0 && next < filled.length) {
      final t = (i - prev) / (next - prev);
      return _pointBetweenStops(filled[prev], filled[next], t);
    }
    if (i < cachedEstimatedCoords.length) {
      final estimated = cachedEstimatedCoords[i];
      if (estimated.latitude != 0.0 && estimated.longitude != 0.0) return estimated;
    }
    if (gpxRoutePoints.length >= 2 && filled.length > 1) {
      final t = i / (filled.length - 1);
      final idx = (t * (gpxRoutePoints.length - 1)).round().clamp(0, gpxRoutePoints.length - 1);
      return gpxRoutePoints[idx];
    }
    if (prev >= 0 && filled[prev].lat != 0.0 && filled[prev].lng != 0.0) {
      return LatLng(filled[prev].lat, filled[prev].lng);
    }
    if (next < filled.length && filled[next].lat != 0.0 && filled[next].lng != 0.0) {
      return LatLng(filled[next].lat, filled[next].lng);
    }
    return null;
  }

  LatLng _pointBetweenStops(BusStop a, BusStop b, double t) {
    final from = LatLng(a.lat, a.lng);
    final to = LatLng(b.lat, b.lng);
    final span = _orderedSpan(a, b) ?? _gpxSpan(from, to);
    if (span != null) {
      final along = _alongIndexed(span[0], span[1], t);
      if (along != null) return along;
    }
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  List<int>? _orderedSpan(BusStop a, BusStop b) {
    final idx = _stopGpxIndex;
    if (idx == null) return null;
    final ia = stopsList.indexWhere((s) => s.seq == a.seq);
    final ib = stopsList.indexWhere((s) => s.seq == b.seq);
    if (ia < 0 || ib < 0 || ia >= idx.length || ib >= idx.length) return null;
    if (idx[ib] <= idx[ia]) return null;
    return [idx[ia], idx[ib]];
  }

  LatLng? _alongIndexed(int iFrom, int iTo, double t) {
    const distanceCalc = Distance();
    double total = 0;
    final segs = <double>[0];
    for (int i = iFrom; i < iTo; i++) {
      total += distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i], gpxRoutePoints[i + 1]);
      segs.add(total);
    }
    if (total <= 0) return gpxRoutePoints[iFrom];
    final target = total * t.clamp(0.0, 1.0);
    for (int k = 0; k < segs.length - 1; k++) {
      if (target >= segs[k] && target <= segs[k + 1]) {
        final spanLen = segs[k + 1] - segs[k];
        final r = spanLen == 0 ? 0.0 : (target - segs[k]) / spanLen;
        final p0 = gpxRoutePoints[iFrom + k];
        final p1 = gpxRoutePoints[iFrom + k + 1];
        return LatLng(
          p0.latitude + (p1.latitude - p0.latitude) * r,
          p0.longitude + (p1.longitude - p0.longitude) * r,
        );
      }
    }
    return gpxRoutePoints[iTo];
  }

  /// 路線打圈時，去程同回程會好近。揀最貼嘅點會跳去回程，架車就行相反方向。
  /// 起點同終點都用「差不多一樣近、但係沿路線較早」嗰點，而且終點必須喺起點後面。
  List<int>? _gpxSpan(LatLng from, LatLng to) {
    if (gpxRoutePoints.length < 2) return null;
    const distanceCalc = Distance();
    const slackMeters = 45.0;
    var bestFrom = double.infinity;
    final fromDist = List<double>.filled(gpxRoutePoints.length, 0);
    for (int i = 0; i < gpxRoutePoints.length; i++) {
      final d = distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i], from);
      fromDist[i] = d;
      if (d < bestFrom) bestFrom = d;
    }
    var iFrom = -1;
    for (int i = 0; i < gpxRoutePoints.length; i++) {
      if (fromDist[i] <= bestFrom + slackMeters) {
        iFrom = i;
        break;
      }
    }
    if (iFrom < 0 || iFrom >= gpxRoutePoints.length - 1) return null;
    var bestTo = double.infinity;
    final toDist = List<double>.filled(gpxRoutePoints.length, double.infinity);
    for (int i = iFrom + 1; i < gpxRoutePoints.length; i++) {
      final d = distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i], to);
      toDist[i] = d;
      if (d < bestTo) bestTo = d;
    }
    var iTo = -1;
    for (int i = iFrom + 1; i < gpxRoutePoints.length; i++) {
      if (toDist[i] <= bestTo + slackMeters) {
        iTo = i;
        break;
      }
    }
    if (iTo <= iFrom) return null;
    return [iFrom, iTo];
  }

  Future<void> fetchStops({bool keepNavigation = false}) async {
    if (currentRoute.isEmpty) return;
    stopAutoRefresh();
    _etaRequestId++;
    _etaInFlight = false;
    final sameTrip = _etaShownRoute == currentRoute && _etaShownDir == currentDirection;
    if (!sameTrip) {
      etaData = null;
      allBusesList = [];
      _legMotion.clear();
      _segmentMetersCache.clear();
    }
    unawaited(fetchBusETA());
    final keepSeq = selectedStopSeq;
    
    final prefs = await SharedPreferences.getInstance();
    // 🌟 採用記憶體中嘅 currentLang 確保同步精準
    final lang = currentLang;
    
    final String cacheKey = '${_stopsCacheKeyPrefix}_${currentRoute}_${currentDirection}_$lang';
    final String? cachedData = prefs.getString(cacheKey);
    final bool stopsFresh = cachedData != null && _isDiskCacheFresh(prefs, cacheKey, _stopsDiskTtl);
    bool hasCache = false;

    if (stopsFresh) {
      try {
        stopsList = _stopsFromDiskJson(cachedData);
        if (stopsList.isNotEmpty) {
          _keepSelectedStopIfPossible(keepSeq);
          outboundTerminal = _formatStopName(stopsList.last.name);
          inboundTerminal = _formatStopName(stopsList.first.name);
          _rememberMissingOfficialCoords();
          _fillMissingStopCoordinates();
          hasCache = true;
          notifyListeners(); 
        }
      } catch (e) {
        debugPrint('讀取站點快取失敗: $e');
      }
    }

    isLoadingStops = !hasCache; 
    
    gpxRoutePoints = [];
    gpxRouteLines = [];
    _stopGpxIndex = null;
    cachedEstimatedCoords = [];
    if (!hasCache) {
      stopsList = [];
      allBusesList = [];
      selectedStopSeq = null;
    }
    
    alightingStopSeq = null;
    errorMessage = null;

    await _restoreTrackingState();
    if (!hasCache) notifyListeners();

    final result = await BusApiService.fetchStops(currentRoute, currentDirection, lang: lang); 
    
    if (result['success'] == true) {
      stopsList = result['stops'];
      if (stopsList.isNotEmpty) {
        _keepSelectedStopIfPossible(keepSeq);
        outboundTerminal = _formatStopName(stopsList.last.name);
        inboundTerminal = _formatStopName(stopsList.first.name);
        
        try {
          final jsonList = stopsList.map((e) {
            final map = e.toJson();
            map['hasAlert'] = false;
            map.remove('alertUrl');
            return map;
          }).toList();
          await _writeDiskCache(prefs, cacheKey, jsonEncode(jsonList));
        } catch (e) {
          debugPrint('寫入站點快取失敗: $e');
        }
        _rememberMissingOfficialCoords();
        _fillMissingStopCoordinates();
      }
      isLoadingStops = false;
      notifyListeners();

      unawaited(fetchGPXRoute()); 
    } else {
      isLoadingStops = false;
      if (!hasCache && cachedData != null) {
        try {
          stopsList = _stopsFromDiskJson(cachedData);
          if (stopsList.isNotEmpty) {
            _keepSelectedStopIfPossible(keepSeq);
            outboundTerminal = _formatStopName(stopsList.last.name);
            inboundTerminal = _formatStopName(stopsList.first.name);
            _rememberMissingOfficialCoords();
            _fillMissingStopCoordinates();
            hasCache = true;
          }
        } catch (e) {
          debugPrint('讀取過期站點快取失敗: $e');
        }
      }
      if (!hasCache) {
        errorMessage = result['message'];
      }
      notifyListeners();
    }
  }

  void checkAlightingAlarm(LatLng? userLocation) {
    if (alightingStopSeq == null || userLocation == null || stopsList.isEmpty) return;

    int stopIdx = stopsList.indexWhere((s) => s.seq == alightingStopSeq);
    if (stopIdx == -1) return;

    double lat = stopsList[stopIdx].lat;
    double lng = stopsList[stopIdx].lng;

    // 暫時關閉：頭尾站唔再 snap 去路線端點
    // if (gpxRoutePoints.isNotEmpty) {
    //   if (stopIdx == 0) {
    //     lat = gpxRoutePoints.first.latitude;
    //     lng = gpxRoutePoints.first.longitude;
    //   } else if (stopIdx == stopsList.length - 1) {
    //     lat = gpxRoutePoints.last.latitude;
    //     lng = gpxRoutePoints.last.longitude;
    //   }
    // }

    if ((lat == 0.0 || lng == 0.0 || lat < 10) && cachedEstimatedCoords.isNotEmpty && stopIdx < cachedEstimatedCoords.length) {
      lat = cachedEstimatedCoords[stopIdx].latitude;
      lng = cachedEstimatedCoords[stopIdx].longitude;
    }

    if (lat != 0.0 && lng != 0.0) {
      final Distance distanceCalc = const Distance();
      double dist = distanceCalc.as(LengthUnit.Meter, userLocation, LatLng(lat, lng));

      if (dist <= 300) {
        pendingAlarmTitle = tr?.call('alight_ready_title') ?? '📍 準備下車！';
        
        // 🌟 同樣拆開寫
        String rawBody = tr?.call('alight_ready_body') ?? '您距離第 @stop 站已不足 300 公尺，請準備下車。';
        pendingAlarmBody = rawBody
            .replaceAll('@stop', alightingStopSeq.toString())
            .replaceAll('@route', currentRoute);

        NotificationService.showAlarm(pendingAlarmTitle!, pendingAlarmBody!);
        alightingStopSeq = null; 
        notifyListeners();
      }
    }
  }

  Future<void> fetchBusETA({bool isAutoRefresh = false}) async {
    if (currentRoute.isEmpty) return;
    if (_etaInFlight && isAutoRefresh) return;

    final requestId = ++_etaRequestId;
    final route = currentRoute;
    final dir = currentDirection;
    final seq = selectedStopSeq;
    _etaInFlight = true;
    if (!isAutoRefresh && etaData == null) {
      isLoadingETA = true;
      notifyListeners();
    }

    try {
      final lang = currentLang;
      final result = await BusApiService.fetchBusETA(
        route,
        dir,
        targetStopSeq: seq,
        lang: lang,
      );
      if (requestId != _etaRequestId || currentRoute != route) return;

      isLoadingETA = false;
      if (result['success'] == true) {
        if (result['realtimeFlagKnown'] == true) {
          OpenDataConfig.instance.applyEtaFlag(result['realtimeAvailable'] == true);
        }
        etaData = result['etaData'];
        timetableDetails = result['timetableDetails'];
        _etaShownRoute = route;
        _etaShownDir = dir;
        errorMessage = null;

        if (showLiveArrivals) {
          allBusesList = result['allBuses'];
          _rememberBusFixes(allBusesList);
          advanceBusMotion();
        } else {
          allBusesList = [];
          _legMotion.clear();
        }

        if (!isAutoRefresh || _autoRefreshTimer == null) startAutoRefresh();
        unawaited(OpenDataConfig.instance.ensureLoaded());
      } else {
        if (stopsList.isEmpty) {
          errorMessage = result['message'];
        }
        if (_autoRefreshTimer == null) startAutoRefresh();
      }
    } finally {
      if (requestId == _etaRequestId) _etaInFlight = false;
      notifyListeners();
    }
  }

  void _keepSelectedStopIfPossible(int? previousSeq) {
    if (stopsList.isEmpty) {
      selectedStopSeq = null;
      return;
    }
    if (previousSeq != null && stopsList.any((s) => s.seq == previousSeq)) {
      selectedStopSeq = previousSeq;
    } else {
      selectedStopSeq = stopsList[0].seq;
    }
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
      // 暫時關閉：頭尾站唔再 snap 去路線端點
      // if (gpxRoutePoints.isNotEmpty) {
      //   if (i == 0) { lat = gpxRoutePoints.first.latitude; lng = gpxRoutePoints.first.longitude; }
      //   else if (i == stopsList.length - 1) { lat = gpxRoutePoints.last.latitude; lng = gpxRoutePoints.last.longitude; }
      // }
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
    // 暫時關閉：頭尾站唔再 snap 去路線端點
    // if (gpxRoutePoints.isNotEmpty) {
    //   if (targetIndex == 0) { lat = gpxRoutePoints.first.latitude; lng = gpxRoutePoints.first.longitude; }
    //   else if (targetIndex == stopsList.length - 1) { lat = gpxRoutePoints.last.latitude; lng = gpxRoutePoints.last.longitude; }
    // }
    if ((lat == 0.0 || lng == 0.0 || lat < 10) && cachedEstimatedCoords.isNotEmpty && targetIndex < cachedEstimatedCoords.length) {
      lat = cachedEstimatedCoords[targetIndex].latitude; lng = cachedEstimatedCoords[targetIndex].longitude;
    }
    if (lat != 0.0 && lng != 0.0) return LatLng(lat, lng);
    return null;
  }

  /// 跟最新 GPS。車速 0（或低過約 2km/h）就停低；
  /// 只有車郁緊先由嗰個 GPS 位再推前，最多一個輪詢間隔。
  /// 超過 10 秒冇新資料就停，唔好再沿用舊車速。
  /// [now] 畀測試固定個鐘；平時用而家。
  bool advanceBusMotion([DateTime? now]) {
    final clock = now ?? DateTime.now();
    final live = <String>{};
    var changed = false;
    for (final bus in allBusesList) {
      final key = bus.busLicense;
      if (bus.currentStopSeq <= 0) {
        if (_legMotion.remove(key) != null) changed = true;
        continue;
      }
      if (bus.atStop) {
        final terminal = _advanceTerminalArrival(bus, clock, live);
        if (terminal == null) {
          if (_legMotion.remove(key) != null) changed = true;
        } else if (terminal) {
          changed = true;
        }
        continue;
      }
      final index = stopsList.indexWhere((s) => s.seq == bus.currentStopSeq);
      if (index == -1 || index + 1 >= stopsList.length) {
        if (_legMotion.remove(key) != null) changed = true;
        continue;
      }
      final here = stopsList[index];
      final next = stopsList[index + 1];
      if (here.lat == 0.0 || here.lng == 0.0 || next.lat == 0.0 || next.lng == 0.0) {
        continue;
      }
      live.add(key);
      final length = _segmentMeters(here, next);
      final cap = _legCap(length, nextIsTerminal: index + 1 == stopsList.length - 1);
      final stepped = _stepLeg(
        bus: bus,
        now: clock,
        from: here,
        to: next,
        motionStopSeq: bus.currentStopSeq,
        cap: cap,
        prev: _legMotion[key],
      );
      _legMotion[key] = stepped.motion;
      if (stepped.moved) changed = true;
    }
    final before = _legMotion.length;
    _legMotion.removeWhere((key, _) => !live.contains(key));
    if (_legMotion.length != before) changed = true;
    return changed;
  }

  /// 去總站嘅車要行到紫色線終點，先算視覺上已到站。
  /// 回傳 null 代表唔係總站；true 代表個位置有郁；false 代表已經喺終點。
  bool? _advanceTerminalArrival(Bus bus, DateTime now, Set<String> live) {
    final index = stopsList.indexWhere((s) => s.seq == bus.currentStopSeq);
    if (index != stopsList.length - 1 || index <= 0) return null;
    final here = stopsList[index - 1];
    final next = stopsList[index];
    if (here.lat == 0.0 || here.lng == 0.0 || next.lat == 0.0 || next.lng == 0.0) return null;
    live.add(bus.busLicense);
    final length = _segmentMeters(here, next);
    final stepped = _stepLeg(
      bus: bus,
      now: now,
      from: here,
      to: next,
      motionStopSeq: here.seq,
      cap: length,
      prev: _legMotion[bus.busLicense],
    );
    _legMotion[bus.busLicense] = stepped.motion;
    return stepped.moved;
  }

  /// 下一站未由資料話已到之前，圖示唔好衝過個站。
  double _legCap(double length, {required bool nextIsTerminal}) {
    if (nextIsTerminal) return length;
    return length > 40 ? length - 25 : length * 0.85;
  }

  /// 新一次 GPS：投影到呢段路線，約 1 秒滑過去。
  /// 之後車速 > 2km/h 先由嗰點再推，最多 6 秒；車停就停。
  ({_BusLegMotion motion, bool moved}) _stepLeg({
    required Bus bus,
    required DateTime now,
    required BusStop from,
    required BusStop to,
    required int motionStopSeq,
    required double cap,
    required _BusLegMotion? prev,
  }) {
    const stopKmh = 2.0;
    const easeSeconds = 1.0;
    const extrapolateSeconds = 6.0;
    const staleSeconds = 10.0;

    final fresh = prev == null || !prev.matchesFix(bus);
    final double gpsMeters;
    final double fixLat;
    final double fixLng;
    final double fixSpeed;
    final int fixStopSeq;
    final bool fixAtStop;
    final DateTime fixAt;
    final bool easedIn;
    final double easeFromLat;
    final double easeFromLng;
    final double easeToLat;
    final double easeToLng;
    final double easeFromMeters;

    if (!fresh) {
      final held = prev;
      gpsMeters = held.gpsMeters;
      fixLat = held.fixLat;
      fixLng = held.fixLng;
      fixSpeed = held.fixSpeed;
      fixStopSeq = held.fixStopSeq;
      fixAtStop = held.fixAtStop;
      fixAt = held.fixAt;
      easedIn = held.easedIn;
      easeFromLat = held.easeFromLat;
      easeFromLng = held.easeFromLng;
      easeToLat = held.easeToLat;
      easeToLng = held.easeToLng;
      easeFromMeters = held.easeFromMeters;
    } else {
      final raw = _metersAlong(from, to, bus.lat, bus.lng);
      gpsMeters = raw > cap ? cap : (raw < 0 ? 0.0 : raw);
      fixLat = bus.lat;
      fixLng = bus.lng;
      fixSpeed = bus.speed;
      fixStopSeq = bus.currentStopSeq;
      fixAtStop = bus.atStop;
      fixAt = now;
      final target = _pointAtMeters(from, to, gpsMeters);
      if (prev == null) {
        easedIn = false;
        easeFromLat = target.latitude;
        easeFromLng = target.longitude;
        easeToLat = target.latitude;
        easeToLng = target.longitude;
        easeFromMeters = gpsMeters;
      } else {
        easedIn = true;
        easeFromLat = prev.renderLat;
        easeFromLng = prev.renderLng;
        easeToLat = target.latitude;
        easeToLng = target.longitude;
        easeFromMeters = prev.stopSeq == motionStopSeq ? prev.traveledMeters : gpsMeters;
      }
    }

    final ageMs = now.difference(fixAt).inMilliseconds;
    final age = ageMs <= 0 ? 0.0 : ageMs / 1000.0;
    final stopped = fixSpeed <= stopKmh;

    final double traveled;
    final double renderLat;
    final double renderLng;

    if (!fresh && !stopped && age > staleSeconds) {
      final held = prev;
      traveled = held.traveledMeters;
      renderLat = held.renderLat;
      renderLng = held.renderLng;
    } else if (easedIn && age < easeSeconds) {
      final t = age / easeSeconds;
      renderLat = easeFromLat + (easeToLat - easeFromLat) * t;
      renderLng = easeFromLng + (easeToLng - easeFromLng) * t;
      traveled = easeFromMeters + (gpsMeters - easeFromMeters) * t;
    } else if (stopped) {
      traveled = gpsMeters;
      final point = _pointAtMeters(from, to, traveled);
      renderLat = point.latitude;
      renderLng = point.longitude;
    } else {
      final delay = easedIn ? easeSeconds : 0.0;
      final window = age > extrapolateSeconds ? extrapolateSeconds : age;
      var predict = window - delay;
      if (predict < 0) predict = 0;
      var meters = gpsMeters + fixSpeed * 1000 / 3600 * predict;
      if (meters > cap) meters = cap;
      if (meters < 0) meters = 0;
      traveled = meters;
      final point = _pointAtMeters(from, to, traveled);
      renderLat = point.latitude;
      renderLng = point.longitude;
    }

    final clamped = traveled > cap ? cap : (traveled < 0 ? 0.0 : traveled);
    final motion = _BusLegMotion(
      stopSeq: motionStopSeq,
      traveledMeters: clamped,
      at: now,
      speedKmh: fixSpeed,
      fixLat: fixLat,
      fixLng: fixLng,
      fixSpeed: fixSpeed,
      fixStopSeq: fixStopSeq,
      fixAtStop: fixAtStop,
      fixAt: fixAt,
      gpsMeters: gpsMeters,
      renderLat: renderLat,
      renderLng: renderLng,
      easeFromLat: easeFromLat,
      easeFromLng: easeFromLng,
      easeToLat: easeToLat,
      easeToLng: easeToLng,
      easeFromMeters: easeFromMeters,
      easedIn: easedIn,
    );
    return (motion: motion, moved: _motionMoved(prev, motion));
  }

  bool _motionMoved(_BusLegMotion? prev, _BusLegMotion next) {
    if (prev == null) return true;
    if ((prev.traveledMeters - next.traveledMeters).abs() >= 0.4) return true;
    final meters = const Distance().as(
      LengthUnit.Meter,
      LatLng(prev.renderLat, prev.renderLng),
      LatLng(next.renderLat, next.renderLng),
    );
    return meters >= 0.4;
  }

  LatLng _pointAtMeters(BusStop from, BusStop to, double meters) {
    final length = _segmentMeters(from, to);
    var t = length <= 0 ? 0.0 : meters / length;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    return _pointBetweenStops(from, to, t);
  }

  double _metersAlong(BusStop from, BusStop to, double lat, double lng) {
    final length = _segmentMeters(from, to);
    if (lat == 0.0 || lng == 0.0) return 0;
    final span = _orderedSpan(from, to);
    final meters = span == null
        ? const Distance().as(LengthUnit.Meter, LatLng(from.lat, from.lng), LatLng(lat, lng))
        : _projectMeters(span[0], span[1], lat, lng);
    if (meters < 0) return 0;
    if (meters > length) return length;
    return meters;
  }

  bool hasVisuallyArrived(Bus bus) {
    if (!bus.atStop) return false;
    final index = stopsList.indexWhere((s) => s.seq == bus.currentStopSeq);
    if (index != stopsList.length - 1 || stopsList.length < 2) return true;
    final here = stopsList[index - 1];
    final motion = _legMotion[bus.busLicense];
    if (motion == null || motion.stopSeq != here.seq) return false;
    final length = _segmentMeters(here, stopsList[index]);
    return motion.traveledMeters >= length - 12;
  }

  double displaySpeedKmh(Bus bus) {
    if (bus.speed <= 2) return 0;
    return bus.speed;
  }

  double _segmentMeters(BusStop a, BusStop b) {
    final key = '$currentRoute|$currentDirection|${gpxRoutePoints.length}|${a.seq}|${b.seq}|${a.lat}|${a.lng}|${b.lat}|${b.lng}';
    final cached = _segmentMetersCache[key];
    if (cached != null) return cached;
    final from = LatLng(a.lat, a.lng);
    final to = LatLng(b.lat, b.lng);
    const distanceCalc = Distance();
    final ordered = _orderedSpan(a, b);
    final along = ordered != null
        ? _indexedMeters(ordered[0], ordered[1])
        : (gpxRoutePoints.length >= 2 ? _gpxMetersBetween(from, to) : null);
    var meters = along ?? distanceCalc.as(LengthUnit.Meter, from, to);
    if (meters < 1) meters = 1;
    _segmentMetersCache[key] = meters;
    return meters;
  }

  double? _indexedMeters(int iFrom, int iTo) {
    if (iTo <= iFrom) return null;
    const distanceCalc = Distance();
    double total = 0;
    for (int i = iFrom; i < iTo; i++) {
      total += distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i], gpxRoutePoints[i + 1]);
    }
    return total > 0 ? total : null;
  }

  double _projectMeters(int iFrom, int iTo, double lat, double lng) {
    const distanceCalc = Distance();
    final point = LatLng(lat, lng);
    var best = double.infinity;
    var bestAt = 0.0;
    var walked = 0.0;
    for (int i = iFrom; i < iTo; i++) {
      final d = distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i], point);
      if (d < best) {
        best = d;
        bestAt = walked;
      }
      walked += distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i], gpxRoutePoints[i + 1]);
    }
    final endD = distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[iTo], point);
    if (endD < best) bestAt = walked;
    return bestAt;
  }

  double? _gpxMetersBetween(LatLng from, LatLng to) {
    final span = _gpxSpan(from, to);
    if (span == null) return null;
    const distanceCalc = Distance();
    double total = 0;
    for (int i = span[0]; i < span[1]; i++) {
      total += distanceCalc.as(LengthUnit.Meter, gpxRoutePoints[i], gpxRoutePoints[i + 1]);
    }
    return total > 0 ? total : null;
  }

  LatLng? snapBusToStop(Bus bus) {
    final index = bus.currentStopSeq > 0
        ? stopsList.indexWhere((s) => s.seq == bus.currentStopSeq)
        : -1;
    if (bus.atStop && index == stopsList.length - 1 && index > 0 && !hasVisuallyArrived(bus)) {
      final here = stopsList[index - 1];
      final next = stopsList[index];
      if (here.lat != 0.0 && here.lng != 0.0 && next.lat != 0.0 && next.lng != 0.0) {
        final length = _segmentMeters(here, next);
        final motion = _legMotion[bus.busLicense];
        if (motion != null && motion.stopSeq == here.seq) {
          return LatLng(motion.renderLat, motion.renderLng);
        }
        final traveled = _metersAlong(here, next, bus.lat, bus.lng);
        final t = (traveled / length).clamp(0.0, 1.0);
        return _pointBetweenStops(here, next, t);
      }
    }
    if (!bus.atStop && index != -1 && index + 1 < stopsList.length) {
      final here = stopsList[index];
      final next = stopsList[index + 1];
      if (here.lat != 0.0 && here.lng != 0.0 && next.lat != 0.0 && next.lng != 0.0) {
        final length = _segmentMeters(here, next);
        final motion = _legMotion[bus.busLicense];
        if (motion != null && motion.stopSeq == bus.currentStopSeq) {
          return LatLng(motion.renderLat, motion.renderLng);
        }
        final cap = _legCap(length, nextIsTerminal: index + 1 == stopsList.length - 1);
        var traveled = _metersAlong(here, next, bus.lat, bus.lng);
        if (traveled > cap) traveled = cap;
        if (traveled < 0) traveled = 0;
        return _pointAtMeters(here, next, traveled);
      }
    }
    if (bus.atStop && index != -1) {
      final stop = stopsList[index];
      if (stop.lat != 0.0 && stop.lng != 0.0) return LatLng(stop.lat, stop.lng);
    }
    if (bus.lat != 0.0 && bus.lng != 0.0) {
      return LatLng(bus.lat, bus.lng);
    }
    if (index != -1) {
      final stop = stopsList[index];
      if (stop.lat != 0.0 && stop.lng != 0.0) {
        return LatLng(stop.lat, stop.lng);
      }
      if (index < cachedEstimatedCoords.length) {
        final estimated = cachedEstimatedCoords[index];
        if (estimated.latitude != 0.0 && estimated.longitude != 0.0) return estimated;
      }
    }
    return _nearestDrawnPoint(index);
  }

  LatLng? _nearestDrawnPoint(int preferIndex) {
    if (stopsList.isNotEmpty) {
      final start = preferIndex >= 0 ? preferIndex : 0;
      for (int distance = 0; distance < stopsList.length; distance++) {
        final candidates = distance == 0 ? [start] : [start - distance, start + distance];
        for (final j in candidates) {
          if (j < 0 || j >= stopsList.length) continue;
          final stop = stopsList[j];
          if (stop.lat != 0.0 && stop.lng != 0.0) {
            return LatLng(stop.lat, stop.lng);
          }
        }
      }
    }
    if (gpxRoutePoints.isNotEmpty) return gpxRoutePoints.first;
    return null;
  }
}

class _BusLegMotion {
  final int stopSeq;
  final double traveledMeters;
  final DateTime at;
  final double speedKmh;
  final double fixLat;
  final double fixLng;
  final double fixSpeed;
  final int fixStopSeq;
  final bool fixAtStop;
  final DateTime fixAt;
  final double gpsMeters;
  final double renderLat;
  final double renderLng;
  final double easeFromLat;
  final double easeFromLng;
  final double easeToLat;
  final double easeToLng;
  final double easeFromMeters;
  final bool easedIn;

  const _BusLegMotion({
    required this.stopSeq,
    required this.traveledMeters,
    required this.at,
    required this.speedKmh,
    required this.fixLat,
    required this.fixLng,
    required this.fixSpeed,
    required this.fixStopSeq,
    required this.fixAtStop,
    required this.fixAt,
    required this.gpsMeters,
    required this.renderLat,
    required this.renderLng,
    required this.easeFromLat,
    required this.easeFromLng,
    required this.easeToLat,
    required this.easeToLng,
    required this.easeFromMeters,
    required this.easedIn,
  });

  bool matchesFix(Bus bus) {
    return fixLat == bus.lat &&
        fixLng == bus.lng &&
        fixSpeed == bus.speed &&
        fixStopSeq == bus.currentStopSeq &&
        fixAtStop == bus.atStop;
  }
}