import 'dart:convert';
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
    if (!FeatureFlags.showRouteTrajectory) return [];
    try {
      final res = await _fetch(routeShapeUri(route, dir));
      if (res.statusCode != 200 || res.body.isEmpty) return [];
      return pointsFromShapeBody(res.body);
    } catch (_) {
      return [];
    }
  }

  static Future<http.Response> _fetch(Uri uri) {
    final override = debugFetch;
    if (override != null) return override(uri);
    return http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
  }

  static List<LatLng> pointsFromShapeBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return [];
    if (decoded['success'] != true || decoded['points'] is! List) return [];
    return [
      for (final p in decoded['points'] as List)
        if (p is Map)
          LatLng(
            ParseUtils.parseDbl(p['lat']),
            ParseUtils.parseDbl(p['lng']),
          ),
    ].where((l) => l.latitude != 0 && l.longitude != 0).toList();
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
