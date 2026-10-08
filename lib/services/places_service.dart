import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_config.dart';

class PlacesService {
  static String get baseUrl => '${ApiConfig.api}/places';

  static String googleLanguage(String lang) {
    switch (lang) {
      case 'zhHans':
        return 'zh-CN';
      case 'pt':
        return 'pt';
      case 'en':
        return 'en';
      case 'zh':
      default:
        return 'zh-TW';
    }
  }

  static Future<List<dynamic>> autocomplete(String query, String sessionToken, {String language = 'zh'}) async {
    try {
      final url = Uri.parse('$baseUrl/autocomplete?input=${Uri.encodeComponent(query)}&sessiontoken=$sessionToken&language=${googleLanguage(language)}');
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