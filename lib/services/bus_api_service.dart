import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus_stop.dart';
import '../models/bus.dart';
import 'package:flutter/foundation.dart';

class BusApiService {
  static const String baseUrl = 'https://api.macaubus-kat1.com/api';

  // 核心修正：加入共用 Headers 偽裝成真實手機瀏覽器，防止 Cloudflare WAF 封鎖
  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json',
  };

  static Future<Map<String, dynamic>> fetchStops(String route, int dir) async {
    try {
      // 修正：移除 baseUrl 後面多餘嘅 /api，避免變成 /api/api/bus-stops
      final res = await http.get(
        Uri.parse('$baseUrl/bus-stops?route=$route&dir=$dir'),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));
      
      final json = jsonDecode(res.body);
      if (json['success'] == true && (json['stops'] as List).isNotEmpty) {
        List<BusStop> stops = (json['stops'] as List).map((s) => BusStop.fromJson(s as Map<String, dynamic>)).toList();
        return {'success': true, 'stops': stops};
      }
      return {'success': false, 'message': json['message'] ?? '查無此路線之站點 / 此乃循環路線'};
    } catch (e) {
      debugPrint('fetchStops Error: $e'); // 加入 Console 輸出，方便日後 Debug
      return {'success': false, 'message': '伺服器回應逾時或被阻擋，請再試一次'};
    }
  }

  static Future<Map<String, dynamic>> fetchBusETA(String route, int dir, {int? targetStopSeq}) async {
    try {
      final seqParam = targetStopSeq != null ? '&targetStopSeq=$targetStopSeq' : '';
      // 修正：移除多餘嘅 /api 並加入 _headers
      final res = await http.get(
        Uri.parse('$baseUrl/bus-eta?route=$route&dir=$dir$seqParam&_t=${DateTime.now().millisecondsSinceEpoch}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));
      
      final json = jsonDecode(res.body);
      if (json['success'] == true) {
        List<Bus> buses = ((json['allBuses'] ?? []) as List).map((b) => Bus.fromJson(b as Map<String, dynamic>)).toList();
        return { 'success': true, 'etaData': json['data'], 'allBuses': buses, 'timetableDetails': json['debug_details'] };
      }
      return {'success': false, 'message': json['message'] ?? '查詢失敗'};
    } catch (e) {
      debugPrint('fetchBusETA Error: $e');
      return {'success': false, 'message': '伺服器回應逾時或被阻擋，請再試一次'};
    }
  }

  static Future<List<String>> fetchAllRoutes() async {
    try {
      // 修正：移除多餘嘅 /api 並加入 _headers
      final res = await http.get(
        Uri.parse('$baseUrl/search-routes?_t=${DateTime.now().millisecondsSinceEpoch}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));
      
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true) return List<String>.from(json['routes']);
      }
    } catch (e) {
      debugPrint('fetchAllRoutes Error: $e');
    } 
    return [];
  }

  static Future<List<String>> searchRoutes(String query) async {
    try {
      // 修正：移除多餘嘅 /api 並加入 _headers
      final res = await http.get(
        Uri.parse('$baseUrl/search-routes?q=$query'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true) return List<String>.from(json['routes']);
      }
    } catch (e) {
      debugPrint('searchRoutes Error: $e');
    } 
    return [];
  }
}