import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../utils/parse_utils.dart';
import '../config/api_config.dart';

class GPXService {
  static String get baseUrl => ApiConfig.origin;
  static const String _upstreamGpx = 'https://motransportinfo.com/gpx';
  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, application/gpx+xml, application/xml, text/xml, */*',
  };

  static Future<List<LatLng>> fetchFullGpx(String route, int dir) async {
    final points = await _fetchFromBackend(route, dir);
    if (points.isNotEmpty) return points;
    return _fetchFromMoTransport(route, dir);
  }

  static Future<List<LatLng>> _fetchFromBackend(String route, int dir) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/bus-gpx?route=$route&dir=$dir'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true && json['points'] != null) {
          return (json['points'] as List)
              .map((p) => LatLng(ParseUtils.parseDbl(p['lat']), ParseUtils.parseDbl(p['lng'])))
              .where((l) => l.latitude != 0)
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Official shape file: https://motransportinfo.com/gpx/{ROUTE}_Forward.gpx
  static Future<List<LatLng>> _fetchFromMoTransport(String route, int dir) async {
    final dirName = dir == 1 ? 'Backward' : 'Forward';
    final code = route.trim().toUpperCase();
    try {
      final res = await http.get(
        Uri.parse('$_upstreamGpx/${Uri.encodeComponent(code)}_$dirName.gpx'),
        headers: {
          'User-Agent': _headers['User-Agent']!,
          'Accept': 'application/gpx+xml,application/xml,text/xml,*/*',
        },
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200 || res.body.isEmpty) return [];
      return _pointsFromGpxXml(res.body);
    } catch (_) {
      return [];
    }
  }

  static List<LatLng> _pointsFromGpxXml(String xml) {
    final re = RegExp(r'<trkpt\s+lat="([^"]+)"\s+lon="([^"]+)"', caseSensitive: false);
    return [
      for (final m in re.allMatches(xml))
        LatLng(ParseUtils.parseDbl(m.group(1)), ParseUtils.parseDbl(m.group(2))),
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
