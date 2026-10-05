import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../constants/feature_flags.dart';
import '../utils/parse_utils.dart';
import '../config/api_config.dart';

/// Loads a route polyline from the same-origin open-data endpoint.
///
/// The Oracle server reads DSAT `ROUTE_NETWORK` geometries ordered by
/// `BUS_ROUTE_SEQ` (`ROUTE_NOS` + `NETWORK_ID`). This client only requests
/// `/api/route-shape` on the app origin.
class GPXService {
  static String get baseUrl => ApiConfig.origin;
  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json',
  };

  /// Test hook. Production leaves this null and uses [http.get].
  static Future<http.Response> Function(Uri uri)? debugFetch;

  static Uri routeShapeUri(String route, int dir) {
    return Uri.parse('$baseUrl/api/route-shape').replace(
      queryParameters: {'route': route, 'dir': '$dir'},
    );
  }

  static Future<List<LatLng>> fetchFullGpx(String route, int dir) async {
    final lines = await fetchRouteLines(route, dir);
    if (lines.isEmpty) return [];
    return lines.reduce((a, b) => a.length >= b.length ? a : b);
  }

  /// Every drawable piece of the route. Disconnected edges stay separate
  /// so the map does not stroke across the gap.
  static Future<List<List<LatLng>>> fetchRouteLines(String route, int dir) async {
    if (!FeatureFlags.showRouteTrajectory) return [];
    try {
      var lines = await _linesFor(route, dir);
      if (lines.isEmpty) {
        final base = _expressParent(route);
        if (base != null) lines = await _linesFor(base, dir);
      }
      return lines;
    } catch (_) {
      return [];
    }
  }

  static Future<List<List<LatLng>>> _linesFor(String route, int dir) async {
    final res = await _fetch(routeShapeUri(route, dir));
    if (res.statusCode != 200 || res.body.isEmpty) return [];
    return linesFromShapeBody(res.body);
  }

  /// `102X` with no open-data row is the same trajectory as `102`.
  static String? _expressParent(String route) {
    final match = RegExp(r'^(\d+)X$', caseSensitive: false).firstMatch(route.trim());
    if (match == null) return null;
    final base = match.group(1);
    if (base == null || base.isEmpty) return null;
    return base;
  }

  static Future<http.Response> _fetch(Uri uri) {
    final override = debugFetch;
    if (override != null) return override(uri);
    return http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
  }

  static List<LatLng> pointsFromShapeBody(String body) {
    final lines = linesFromShapeBody(body);
    if (lines.isEmpty) return [];
    return lines.reduce((a, b) => a.length >= b.length ? a : b);
  }

  static List<List<LatLng>> linesFromShapeBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['success'] != true) return [];
    final rawLines = decoded['lines'];
    if (rawLines is List && rawLines.isNotEmpty) {
      final lines = <List<LatLng>>[
        for (final line in rawLines)
          if (line is List) ...splitDiscontinuous(_pointsFromList(line)),
      ];
      if (lines.isNotEmpty) return lines;
    }
    if (decoded['points'] is! List) return [];
    return splitDiscontinuous(_pointsFromList(decoded['points'] as List));
  }

  static List<List<LatLng>> linesFromCached(dynamic decoded) {
    if (decoded is! List || decoded.isEmpty) return [];
    if (decoded.first is List) {
      return [
        for (final line in decoded)
          if (line is List) ...splitDiscontinuous(_pointsFromList(line)),
      ];
    }
    return splitDiscontinuous(_pointsFromList(decoded));
  }

  static List<LatLng> _pointsFromList(List<dynamic> raw) {
    return [
      for (final p in raw)
        if (p is Map)
          LatLng(
            ParseUtils.parseDbl(p['lat']),
            ParseUtils.parseDbl(p['lng']),
          ),
    ].where((l) => l.latitude != 0 && l.longitude != 0).toList();
  }

  /// Same rule as the server. Steps that reverse across a short connector,
  /// or that leave a teleport with no road continuation, are not stroked.
  /// Colinear bridge spans stay.
  static List<List<LatLng>> splitDiscontinuous(List<LatLng> points) {
    if (points.length < 2) return [];
    const cap = 600.0;
    const maxTurn = 30.0;
    const neighMin = 8.0;
    const reverseMin = 160.0;
    const reverseTurn = 120.0;
    const maxConn = 400.0;
    const isolateMin = 250.0;
    const contBar = 80.0;
    final ds = <double>[];
    final bs = <double>[];
    for (var i = 1; i < points.length; i++) {
      ds.add(_meters(points[i - 1], points[i]));
      bs.add(_bearing(points[i - 1], points[i]));
    }
    ({double bearing, double dist})? neigh(int start, int step) {
      var j = start;
      while (j >= 0 && j < ds.length) {
        if (ds[j] >= neighMin) return (bearing: bs[j], dist: ds[j]);
        j += step;
      }
      return null;
    }

    final breakAfter = List<bool>.filled(ds.length, false);
    for (var i = 0; i < ds.length; i++) {
      final d = ds[i];
      if (d < cap) continue;
      final prev = neigh(i - 1, -1);
      final next = neigh(i + 1, 1);
      final badP = prev != null && _angleDiff(bs[i], prev.bearing) > maxTurn;
      final badN = next != null && _angleDiff(bs[i], next.bearing) > maxTurn;
      final shortP = prev != null && prev.dist < cap * 0.5;
      final shortN = next != null && next.dist < cap * 0.5;
      if (badP || badN || (shortP && shortN)) breakAfter[i] = true;
    }
    final longs = <int>[
      for (var i = 0; i < ds.length; i++)
        if (ds[i] >= reverseMin) i,
    ];
    for (var k = 1; k < longs.length; k++) {
      final a = longs[k - 1];
      final b = longs[k];
      var conn = 0.0;
      for (var j = a + 1; j < b; j++) {
        conn += ds[j];
      }
      if (conn <= maxConn && _angleDiff(bs[a], bs[b]) > reverseTurn) {
        breakAfter[a] = true;
        breakAfter[b] = true;
      }
    }
    for (var i = 0; i < ds.length; i++) {
      if (ds[i] < isolateMin || breakAfter[i]) continue;
      final prev = neigh(i - 1, -1);
      final next = neigh(i + 1, 1);
      if (prev == null && next == null) continue;
      final turnP = prev == null ? null : _angleDiff(bs[i], prev.bearing);
      final turnN = next == null ? null : _angleDiff(bs[i], next.bearing);
      final gapP = prev == null || (prev.dist >= cap && turnP! > maxTurn);
      final gapN = next == null || (next.dist >= cap && turnN! > maxTurn);
      final contP = prev != null && turnP! <= maxTurn && prev.dist >= contBar;
      final contN = next != null && turnN! <= maxTurn && next.dist >= contBar;
      if ((gapP || gapN) && !contP && !contN) breakAfter[i] = true;
    }
    final lines = <List<LatLng>>[];
    var cur = <LatLng>[points.first];
    for (var i = 0; i < ds.length; i++) {
      if (breakAfter[i]) {
        if (cur.length >= 2) lines.add(cur);
        cur = <LatLng>[points[i + 1]];
      } else {
        cur.add(points[i + 1]);
      }
    }
    if (cur.length >= 2) lines.add(cur);
    return lines;
  }

  static double _meters(LatLng a, LatLng b) {
    final dy = b.latitude - a.latitude;
    final dx = (b.longitude - a.longitude) * math.cos(((a.latitude + b.latitude) / 2) * math.pi / 180);
    return math.sqrt(dy * dy + dx * dx) * 111320;
  }

  static double _bearing(LatLng a, LatLng b) {
    final dy = b.latitude - a.latitude;
    final dx = (b.longitude - a.longitude) * math.cos(((a.latitude + b.latitude) / 2) * math.pi / 180);
    return (math.atan2(dx, dy) * 180 / math.pi + 360) % 360;
  }

  static double _angleDiff(double a, double b) {
    final d = (a - b).abs() % 360;
    return math.min(d, 360 - d);
  }

  static Future<List<LatLng>?> fetchAndSliceGpx(String route, int dir, LatLng fromPt, LatLng toPt) async {
    try {
      final allGpx = await fetchFullGpx(route, dir);
      if (allGpx.isEmpty) return null;
      int startIdx = 0; double minStartDist = double.infinity; final Distance distanceCalc = const Distance();
      for (int i = 0; i < allGpx.length; i++) { double d = distanceCalc.as(LengthUnit.Meter, fromPt, allGpx[i]); if (d < minStartDist) { minStartDist = d; startIdx = i; } }
      int endIdx = startIdx; double minEndDist = double.infinity; bool foundTargetArea = false;
      for (int i = 0; i < allGpx.length; i++) { int actualIdx = (startIdx + i) % allGpx.length; double d = distanceCalc.as(LengthUnit.Meter, toPt, allGpx[actualIdx]); if (d < minEndDist) { minEndDist = d; endIdx = actualIdx; if (d < 60) foundTargetArea = true; } else if (foundTargetArea && d > minEndDist + 80) { break; } }
      if (startIdx <= endIdx) { return allGpx.sublist(startIdx, endIdx + 1); } else { List<LatLng> combined = []; combined.addAll(allGpx.sublist(startIdx)); combined.addAll(allGpx.sublist(0, endIdx + 1)); return combined; }
    } catch (_) {} return null;
  }
}
