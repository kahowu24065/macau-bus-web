import 'package:flutter/foundation.dart';

import 'bus_api_service.dart';

/// Decides whether live DSAT arrivals are shown.
///
/// `/api/config` is the app-wide switch. A missing or failed config leaves
/// the mode unknown, and the latest response `realtimeAvailable` is used
/// instead. If that flag is also absent, live UI stays on so an older server
/// keeps working. A response flag always wins over a cached config value, so
/// the server can turn realtime back on without an app update.
class RealtimeGate {
  static bool showLive({bool? configRealtime, bool? etaRealtime}) {
    if (etaRealtime != null) return etaRealtime;
    if (configRealtime != null) return configRealtime;
    return true;
  }

  static bool showRouteNotices({
    bool? configRealtime,
    bool? configRouteNotices,
    bool? noticesRealtime,
  }) {
    if (noticesRealtime != null) return noticesRealtime;
    if (configRouteNotices != null) return configRouteNotices;
    if (configRealtime == false) return false;
    return true;
  }

  static const fallbackAttribution = '資料來源：澳門特別行政區政府數據開放平台';

  /// Platform credit plus the date the data was obtained, on separate lines.
  static String attributionBlock({
    required String lang,
    String? attribution,
    String? attributionEn,
    String? attributionPt,
    String? dataDate,
  }) {
    final server = switch (lang) {
      'en' => attributionEn,
      'pt' => attributionPt,
      _ => attribution,
    };
    final source = (server != null && server.trim().isNotEmpty)
        ? server.trim()
        : fallbackAttribution;
    final date = dataDate?.trim() ?? '';
    if (date.isEmpty) return source;
    final label = switch (lang) {
      'en' => 'Date obtained',
      'pt' => 'Data obtida',
      _ => '取得日期',
    };
    final sep = (lang == 'en' || lang == 'pt') ? ': ' : '：';
    return '$source\n$label$sep$date';
  }
}

/// Last known open-data / realtime switch from the live server.
class OpenDataConfig extends ChangeNotifier {
  OpenDataConfig._();
  static final OpenDataConfig instance = OpenDataConfig._();

  bool? configRealtime;
  bool? configRouteNotices;
  bool? etaRealtime;
  bool? noticesRealtime;

  String? attribution;
  String? attributionEn;
  String? attributionPt;
  String? dataDate;

  bool _configLoaded = false;
  DateTime? _lastAttempt;
  Future<void>? _loading;

  bool get showLiveArrivals => RealtimeGate.showLive(
        configRealtime: configRealtime,
        etaRealtime: etaRealtime,
      );

  bool get showRouteNotices => RealtimeGate.showRouteNotices(
        configRealtime: configRealtime,
        configRouteNotices: configRouteNotices,
        noticesRealtime: noticesRealtime,
      );

  String attributionBlock(String lang) => RealtimeGate.attributionBlock(
        lang: lang,
        attribution: attribution,
        attributionEn: attributionEn,
        attributionPt: attributionPt,
        dataDate: dataDate,
      );

  Future<void> ensureLoaded({bool force = false}) {
    if (!force && _configLoaded) return Future<void>.value();
    final attempted = _lastAttempt;
    if (!force &&
        attempted != null &&
        DateTime.now().difference(attempted) < const Duration(minutes: 2)) {
      return Future<void>.value();
    }
    final current = _loading;
    if (current != null && !force) return current;
    final run = _load();
    _loading = run;
    return run.whenComplete(() {
      if (identical(_loading, run)) _loading = null;
    });
  }

  Future<void> _load() async {
    _lastAttempt = DateTime.now();
    final json = await BusApiService.fetchAppConfig();
    if (json == null) return;
    if (json['realtime'] is bool) configRealtime = json['realtime'] as bool;
    if (json['routeChangeNotices'] is bool) {
      configRouteNotices = json['routeChangeNotices'] as bool;
    }
    attribution = _clean(json['attribution']);
    attributionEn = _clean(json['attributionEn']);
    attributionPt = _clean(json['attributionPt']);
    dataDate = _clean(json['dataDate']);
    _configLoaded = true;
    notifyListeners();
  }

  void applyEtaFlag(bool value) {
    if (etaRealtime == value) return;
    etaRealtime = value;
    notifyListeners();
  }

  void applyNoticesFlag(bool value) {
    if (noticesRealtime == value) return;
    noticesRealtime = value;
    notifyListeners();
  }

  static String? _clean(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// Pins the switch for tests and skips the next unforced config fetch.
  @visibleForTesting
  void debugApply({
    bool? configRealtime,
    bool? configRouteNotices,
    bool? etaRealtime,
    bool? noticesRealtime,
    String? attribution,
    String? attributionEn,
    String? attributionPt,
    String? dataDate,
  }) {
    this.configRealtime = configRealtime;
    this.configRouteNotices = configRouteNotices;
    this.etaRealtime = etaRealtime;
    this.noticesRealtime = noticesRealtime;
    this.attribution = attribution;
    this.attributionEn = attributionEn;
    this.attributionPt = attributionPt;
    this.dataDate = dataDate;
    _configLoaded = true;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    configRealtime = null;
    configRouteNotices = null;
    etaRealtime = null;
    noticesRealtime = null;
    attribution = null;
    attributionEn = null;
    attributionPt = null;
    dataDate = null;
    _configLoaded = false;
    _lastAttempt = null;
    _loading = null;
  }
}
