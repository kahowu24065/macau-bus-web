import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../utils/parse_utils.dart';

class GPXService {
  static const String baseUrl = 'https://api.macaubus-kat1.com';

  static Future<List<LatLng>> fetchFullGpx(String route, int dir) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/bus-gpx?route=$route&dir=$dir')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true && json['points'] != null) {
          return (json['points'] as List).map((p) => LatLng(ParseUtils.parseDbl(p['lat']), ParseUtils.parseDbl(p['lng']))).where((l) => l.latitude != 0).toList();
        }
      }
    } catch (_) {} return [];
  }

  static Future<List<LatLng>?> fetchAndSliceGpx(String route, int dir, LatLng fromPt, LatLng toPt) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/bus-gpx?route=$route&dir=$dir')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true && json['points'] != null) {
          List<LatLng> allGpx = (json['points'] as List).map((p) => LatLng(ParseUtils.parseDbl(p['lat']), ParseUtils.parseDbl(p['lng']))).where((l) => l.latitude != 0).toList();
          if (allGpx.isNotEmpty) {
            int startIdx = 0; double minStartDist = double.infinity; final Distance distanceCalc = const Distance();
            for (int i = 0; i < allGpx.length; i++) { double d = distanceCalc.as(LengthUnit.Meter, fromPt, allGpx[i]); if (d < minStartDist) { minStartDist = d; startIdx = i; } }
            int endIdx = startIdx; double minEndDist = double.infinity; bool foundTargetArea = false;
            for (int i = 0; i < allGpx.length; i++) { int actualIdx = (startIdx + i) % allGpx.length; double d = distanceCalc.as(LengthUnit.Meter, toPt, allGpx[actualIdx]); if (d < minEndDist) { minEndDist = d; endIdx = actualIdx; if (d < 60) foundTargetArea = true; } else if (foundTargetArea && d > minEndDist + 80) { break; } }
            if (startIdx <= endIdx) { return allGpx.sublist(startIdx, endIdx + 1); } else { List<LatLng> combined = []; combined.addAll(allGpx.sublist(startIdx)); combined.addAll(allGpx.sublist(0, endIdx + 1)); return combined; }
          }
        }
      }
    } catch (_) {} return null;
  }
}