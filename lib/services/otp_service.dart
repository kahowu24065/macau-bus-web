import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../controllers/language_controller.dart';
import '../config/api_config.dart';

class OTPService {
  static String get baseUrl => '${ApiConfig.api}/otp-graphql';
  
  static Future<dynamic> getRoutePlan({
    required double fromLat, 
    required double fromLng, 
    required double toLat, 
    required double toLng,
    required LanguageController langCtrl
  }) async {
    try {
      final now = DateTime.now();
      final timeString = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final dateString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      String graphqlQuery(bool withMinTransfer) {
        final extra = withMinTransfer ? ' minTransferTime: 60' : '';
        return '''{ plan(from: {lat: $fromLat, lon: $fromLng} to: {lat: $toLat, lon: $toLng} date: "$dateString" time: "$timeString" numItineraries: 6 maxWalkDistance: 2500.0 walkReluctance: 3.0$extra transportModes: [{mode: WALK}, {mode: TRANSIT}]) { itineraries { duration legs { mode duration startTime endTime route { gtfsId, shortName } from { name, lat, lon } to { name, lat, lon } legGeometry { points } } } } }''';
      }

      Future<http.Response> postQuery(bool withMinTransfer) {
        return http.post(
          Uri.parse(baseUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'query': graphqlQuery(withMinTransfer)}),
        ).timeout(const Duration(seconds: 10));
      }

      var response = await postQuery(false);
      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        if (data['errors'] != null) {
          response = await postQuery(true);
          data = json.decode(response.body);
        }
        if (response.statusCode == 200 && data['errors'] != null) {
          return langCtrl.tr('graphql_error');
        }
        if (data['data'] != null && data['data']['plan'] != null) {
          final itineraries = data['data']['plan']['itineraries'] as List;
          if (itineraries.isNotEmpty) {
            itineraries.sort((a, b) => (a['duration'] as num).compareTo(b['duration'] as num));
            return itineraries;
          }
          return langCtrl.tr('no_route_found');
        }
        return "${langCtrl.tr('invalid_response')}:\n${response.body}";
      }
      return "${langCtrl.tr('otp_server_error')}: HTTP ${response.statusCode}";
    } catch (e) {
      return "${langCtrl.tr('network_failed')}: $e";
    }
  }

  static Future<List<Map<String, dynamic>>> fetchNearbyStops({
    required double lat,
    required double lng,
    int maxDistance = 700,
    int limit = 8,
  }) async {
    try {
      final graphqlQuery =
          '{ nearest(lat: $lat, lon: $lng, maxDistance: $maxDistance) { edges { node { distance place { lat lon __typename ... on Stop { name code gtfsId routes { shortName } } } } } } }';

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: const {'Content-Type': 'application/json'},
        body: json.encode({'query': graphqlQuery}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];
      final data = json.decode(response.body);
      final edges = data['data']?['nearest']?['edges'] as List? ?? [];
      final Map<String, Map<String, dynamic>> unique = {};

      for (final edge in edges) {
        final node = edge['node'];
        final place = node?['place'];
        if (place is! Map || place['__typename'] != 'Stop') continue;
        final gtfsId = (place['gtfsId'] ?? '').toString();
        if (gtfsId.isEmpty || unique.containsKey(gtfsId)) continue;

        final routes = ((place['routes'] as List?) ?? [])
            .map((r) => (r is Map ? r['shortName'] : r)?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

        unique[gtfsId] = {
          'name': (place['name'] ?? '').toString(),
          'code': (place['code'] ?? gtfsId.split(':').last).toString(),
          'distance': (node['distance'] as num?)?.toDouble() ?? 0,
          'lat': place['lat'],
          'lng': place['lon'],
          'routes': routes,
        };
      }

      final stops = unique.values.toList()
        ..sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
      return stops.take(limit).toList();
    } catch (e) {
      debugPrint('fetchNearbyStops timeout: $e');
      return [];
    }
  }
}