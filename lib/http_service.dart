import 'dart:convert';
import 'package:http/http.dart' as http;

class BusService {
  // 注意：如果是用 Chrome (Web) 測試，用 localhost
  // 如果是用 Android 模擬器，請改用 10.0.2.2
  static const String baseUrl = 'http://localhost:3000/api/bus-eta';

  static Future<Map<String, dynamic>?> fetchBusETA(String route, int targetStopSeq) async {
    try {
      final uri = Uri.parse('$baseUrl?route=$route&targetStopSeq=$targetStopSeq');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true) {
          return jsonResponse['data'];
        }
      }
      return null;
    } catch (e) {
      print('連線錯誤: $e');
      return null;
    }
  }
}