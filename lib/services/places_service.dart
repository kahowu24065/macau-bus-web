import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlacesService {
  static const String baseUrl = 'https://api.macaubus-kat1.com/api/places';

  static Future<List<dynamic>> autocomplete(String query, String sessionToken) async {
    try {
      final url = Uri.parse('$baseUrl/autocomplete?input=${Uri.encodeComponent(query)}&sessiontoken=$sessionToken');
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) { final data = jsonDecode(res.body); if (data['status'] == 'OK') return data['predictions']; }
    } catch (_) {} return [];
  }

  static Future<LatLng?> getDetails(String placeId, String sessionToken) async {
    try {
      final url = Uri.parse('$baseUrl/details?place_id=$placeId&sessiontoken=$sessionToken');
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) { final data = jsonDecode(res.body); if (data['status'] == 'OK' && data['result'] != null) { final loc = data['result']['geometry']['location']; return LatLng(loc['lat'], loc['lng']); } }
    } catch (_) {} return null;
  }

  static Future<LatLng?> textSearch(String query) async {
    try {
      final url = Uri.parse('$baseUrl/textsearch?query=${Uri.encodeComponent(query)}');
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) { final data = jsonDecode(res.body); if (data['status'] == 'OK' && data['results'] != null && (data['results'] as List).isNotEmpty) { final loc = data['results'][0]['geometry']['location']; return LatLng(loc['lat'], loc['lng']); } }
    } catch (_) {} return null;
  }
}