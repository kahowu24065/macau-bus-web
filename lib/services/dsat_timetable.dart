import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// One headway row: a service-time band and a frequency range such as "9 - 11".
class DsatFrequencyBand {
  final String time;
  final String freq;

  const DsatFrequencyBand({required this.time, required this.freq});
}

/// A day-type block (for example 星期一至六（公眾假期除外）).
class DsatTimetableSection {
  final String title;
  final List<DsatFrequencyBand> items;

  const DsatTimetableSection({required this.title, required this.items});
}

/// Official DSAT frequency bands for the route timetable dialog.
///
/// The dialog reads each route's `app_frequency` (day sections, then one row
/// list per direction). DSAT sheets are headway ranges; route 71S is the
/// exception and stores exact clocks. This is separate from LocalTimetable,
/// which only stores first/last service windows for planning filters
/// (`assets/timetable.json` and `/api/timetable.json`). Do not point this
/// refresh at that compact `{date, routes:{ROUTE_DIR:{startTime,endTime}}}`
/// file.
///
/// Load order matches LocalTimetable: the bundled asset is applied first,
/// so opening the dialog never waits on the network. A refresh then replaces
/// the in-memory map when it succeeds.
///
/// Server contract (`GET https://macaubus-kat1.com/api/dsat_timetables.json`):
/// * JSON object, `schema` exactly [schema] (`dsat-app-frequency-v1`).
/// * `routes` is an object. Each value the dialog can show has `app_frequency`
///   (or the older `directions` object keyed `"0"` / `"1"`).
/// * The payload is the full route set. Routes omitted from it leave the
///   dialog after a successful refresh. A new shuttle is a new key in that
///   object, using the same `app_frequency.sections[].directions[].rows[]`
///   shape (`服務時間`, `班次(分鐘)`).
/// * Refresh every [refreshEvery], timeout [fetchTimeout], one attempt at a
///   time. The attempt is stamped when it starts, including when it fails, so
///   a down server is not retried on every dialog open.
/// * Keep the current map on any error, a Cloudflare challenge (403 / 429 /
///   503, or a body that starts with `<`), a schema mismatch, or fewer than
///   [minServerRoutes] usable routes. There is no disk cache: the next process
///   starts from the asset again.
///
/// `server/dsat_timetables.js` serves this file. Its `MIN_ROUTES` and `SCHEMA`
/// must stay equal to [minServerRoutes] and [schema].
///
/// A circular route (one direction in `app_frequency`) is shown for either
/// direction index. An unknown route, or a missing direction on a
/// two-direction route, is empty.
class DsatTimetable {
  static const assetPath = 'assets/dsat_timetables.json';
  static const schema = 'dsat-app-frequency-v1';
  static const minServerRoutes = 50;
  static const refreshEvery = Duration(minutes: 30);
  static const fetchTimeout = Duration(seconds: 5);

  static Uri get frequencyUri =>
      Uri.parse('${ApiConfig.api}/dsat_timetables.json');

  /// Test hook. Production leaves this null and uses [http.get].
  @visibleForTesting
  static Future<http.Response> Function(Uri uri)? debugFetch;

  static final _headway = RegExp(r'^(\d+)\s*[-–]\s*(\d+)$');
  static final List<VoidCallback> _listeners = <VoidCallback>[];

  static Map<String, dynamic> _routes = {};
  static bool _loaded = false;
  static bool _usingServerCopy = false;
  static DateTime? _lastFetch;
  static bool _fetching = false;
  static int _fetchGen = 0;
  static Future<void>? _refreshInFlight;

  /// Routes in the map currently shown (bundled asset, or the last accepted
  /// server file).
  static int get routeCount => _routes.length;

  /// True after a server payload has replaced the bundled map.
  static bool get usingServerCopy => _usingServerCopy;

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Drops the in-memory map so the next [ensureLoaded] reads the asset again.
  /// An in-flight refresh cannot apply after this returns.
  @visibleForTesting
  static void debugReset() {
    _fetchGen++;
    _routes = {};
    _loaded = false;
    _usingServerCopy = false;
    _lastFetch = null;
    _fetching = false;
    _refreshInFlight = null;
  }

  /// Makes the next [ensureLoaded] eligible to refresh before [refreshEvery].
  @visibleForTesting
  static void debugExpire() {
    _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  }

  @visibleForTesting
  static Future<void>? get debugRefreshInFlight => _refreshInFlight;

  static String normalizeRoute(String route) {
    var r = route.trim().toUpperCase();
    if (r.contains(':')) r = r.split(':').last;
    r = r.replaceAll(RegExp(r'\s+'), '');
    r = r.replaceAll('線', '').replaceAll('线', '');
    return r;
  }

  static Future<void> ensureLoaded() async {
    if (!_loaded) {
      try {
        final raw = await rootBundle.loadString(assetPath);
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['routes'] is Map) {
          _routes = Map<String, dynamic>.from(decoded['routes'] as Map);
          _usingServerCopy = false;
        }
      } catch (_) {
        // Keep the previous map if the asset cannot be read.
      }
      _loaded = _routes.isNotEmpty;
    }
    _maybeRefresh();
  }

  /// Fire-and-forget server refresh. Callers, including the timetable dialog,
  /// do not wait on this.
  static void _maybeRefresh() {
    final now = DateTime.now();
    if (_fetching) return;
    if (_lastFetch != null && now.difference(_lastFetch!) < refreshEvery) {
      return;
    }
    _fetching = true;
    _lastFetch = now;
    final gen = ++_fetchGen;
    final run = _fetchServer(gen);
    _refreshInFlight = run;
    unawaited(
      run.whenComplete(() {
        if (gen != _fetchGen) return;
        _fetching = false;
        if (identical(_refreshInFlight, run)) _refreshInFlight = null;
      }),
    );
  }

  static Future<http.Response> _fetch(Uri uri) {
    final override = debugFetch;
    final pending = override != null ? override(uri) : http.get(uri);
    return pending.timeout(fetchTimeout);
  }

  static Future<void> _fetchServer(int gen) async {
    try {
      final res = await _fetch(frequencyUri);
      if (gen != _fetchGen) return;
      if (res.statusCode != 200 || ApiConfig.looksLikeChallenge(res)) return;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (gen != _fetchGen) return;
      final routes = _routesFromPayload(decoded);
      if (routes == null) return;
      _routes = routes;
      _loaded = true;
      _usingServerCopy = true;
      _notify();
    } catch (_) {
      // Offline, timeout, or a body that is not JSON: keep the current map.
    }
  }

  /// Null when [decoded] must not replace the current bands.
  static Map<String, dynamic>? _routesFromPayload(dynamic decoded) {
    if (decoded is! Map) return null;
    if (decoded['schema'] != schema) return null;
    final raw = decoded['routes'];
    if (raw is! Map) return null;
    final routes = Map<String, dynamic>.from(raw);
    var usable = 0;
    for (final value in routes.values) {
      if (_isUsableRoute(value)) usable++;
    }
    if (usable < minServerRoutes) return null;
    return routes;
  }

  static bool _isUsableRoute(dynamic value) {
    if (value is! Map) return false;
    if (value['app_frequency'] is Map) return true;
    final directions = value['directions'];
    return directions is Map && directions.isNotEmpty;
  }

  static void _notify() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  static bool hasRoute(String route) => sectionsFor(route, 0).isNotEmpty;

  /// Headway "9-11" is shown as "9 - 11". Exact clocks and suspended-service
  /// cells are left as published.
  static String displayFreq(String raw) {
    final m = _headway.firstMatch(raw.trim());
    if (m == null) return raw.trim();
    return '${m.group(1)} - ${m.group(2)}';
  }

  static List<DsatTimetableSection> sectionsFor(String route, int direction) {
    final entry = _routes[normalizeRoute(route)];
    if (entry is! Map) return const [];
    final app = entry['app_frequency'];
    if (app is Map && app['sections'] is List) {
      return _fromAppFrequency(app, direction);
    }
    return _fromLegacyDirections(entry['directions'], direction);
  }

  static List<DsatTimetableSection> _fromAppFrequency(Map app, int direction) {
    final sections = app['sections'];
    if (sections is! List || sections.isEmpty) return const [];

    var widest = 0;
    for (final sec in sections) {
      if (sec is Map && sec['directions'] is List) {
        final n = (sec['directions'] as List).length;
        if (n > widest) widest = n;
      }
    }
    if (widest == 0) return const [];
    final index = widest == 1 ? 0 : direction;
    if (index < 0 || index >= widest) return const [];

    final out = <DsatTimetableSection>[];
    for (final sec in sections) {
      if (sec is! Map) continue;
      final dirs = sec['directions'];
      if (dirs is! List || index >= dirs.length) continue;
      final dir = dirs[index];
      if (dir is! Map) continue;
      final rows = dir['rows'];
      if (rows is! List) continue;
      final items = <DsatFrequencyBand>[];
      for (final row in rows) {
        if (row is! Map) continue;
        final time = (row['服務時間'] ?? row['time'] ?? '').toString().trim();
        final freq = displayFreq(
          (row['班次(分鐘)'] ?? row['freq'] ?? '').toString(),
        );
        if (time.isEmpty && freq.isEmpty) continue;
        items.add(DsatFrequencyBand(time: time, freq: freq));
      }
      if (items.isEmpty) continue;
      out.add(
        DsatTimetableSection(
          title: sec['title']?.toString() ?? '',
          items: items,
        ),
      );
    }
    return out;
  }

  /// Earlier seed file: directions keyed "0"/"1" with time/freq items.
  static List<DsatTimetableSection> _fromLegacyDirections(
    dynamic dirs,
    int direction,
  ) {
    if (dirs is! Map || dirs.isEmpty) return const [];
    var node = dirs['$direction'];
    if (node == null && dirs.length == 1) node = dirs.values.first;
    if (node is! Map) return const [];
    final sections = node['sections'];
    if (sections is! List) return const [];

    final out = <DsatTimetableSection>[];
    for (final sec in sections) {
      if (sec is! Map) continue;
      final itemsRaw = sec['items'];
      if (itemsRaw is! List) continue;
      final items = <DsatFrequencyBand>[];
      for (final item in itemsRaw) {
        if (item is! Map) continue;
        final time = item['time']?.toString() ?? '';
        final freq = displayFreq(item['freq']?.toString() ?? '');
        if (time.isEmpty && freq.isEmpty) continue;
        items.add(DsatFrequencyBand(time: time, freq: freq));
      }
      if (items.isEmpty) continue;
      out.add(
        DsatTimetableSection(
          title: sec['title']?.toString() ?? '',
          items: items,
        ),
      );
    }
    return out;
  }
}
