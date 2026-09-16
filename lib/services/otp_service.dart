import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/itinerary.dart';

class OTPService {
  static const String baseUrl = 'https://api.macaubus-kat1.com/otp/routers/default/index/graphql';
  
  static Future<dynamic> getRoutePlan({required double fromLat, required double fromLng, required double toLat, required double toLng, List<String> bannedRoutes = const []}) async {
    try {
      final now = DateTime.now(); 
      final timeString = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}'; 
      final dateString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      String bannedParam = ''; 
      if (bannedRoutes.isNotEmpty) { 
        String routesStr = bannedRoutes.join(','); 
        bannedParam = 'banned: {routes: "$routesStr"}'; 
      }
      final String graphqlQuery = '''{ plan(from: {lat: $fromLat, lon: $fromLng} to: {lat: $toLat, lon: $toLng} date: "$dateString" time: "$timeString" numItineraries: 5 maxWalkDistance: 2000.0 walkReluctance: 8.0 transportModes: [{mode: WALK}, {mode: TRANSIT}] $bannedParam) { itineraries { duration legs { mode duration startTime endTime route { gtfsId, shortName } from { name, lat, lon } to { name, lat, lon } legGeometry { points } } } } }''';
      
      final response = await http.post(Uri.parse(baseUrl), headers: {'Content-Type': 'application/json'}, body: json.encode({'query': graphqlQuery})).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body); 
        if (data['errors'] != null) return "GraphQL 語法錯誤:\n${json.encode(data['errors'])}";
        if (data['data'] != null && data['data']['plan'] != null) { 
          final rawItineraries = data['data']['plan']['itineraries'] as List; 
          if (rawItineraries.isNotEmpty) { 
            rawItineraries.sort((a, b) => (a['duration'] as num).compareTo(b['duration'] as num)); 
            // 🛡️ Phase 7: 直接轉化為強型別 Itinerary 物件！
            return rawItineraries.map((json) => Itinerary.fromJson(json as Map<String, dynamic>)).toList(); 
          } 
          return "大腦話呢個距離/時間搵唔到路線！(可能步行距離太遠)"; 
        } 
        return "大腦回傳結構異常:\n${response.body}";
      } 
      return "OTP 伺服器錯誤: HTTP ${response.statusCode}";
    } catch (e) { 
      return "網絡連線失敗: $e"; 
    }
  }
}