import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus_stop.dart';
import '../models/bus.dart';
import '../utils/bus_eta_estimate.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

class _ResettableClient {
  http.Client _client = http.Client();

  void reset() {
    try {
      _client.close();
    } catch (_) {}
    _client = http.Client();
  }

  Future<http.Response> get(
    String url, {
    required Map<String, String> headers,
    required Duration timeout,
  }) {
    return _client.get(Uri.parse(url), headers: headers).timeout(timeout);
  }
}

class RouteAlertsFetch {
  final List<Map<String, dynamic>> alerts;
  final bool realtimeFlagKnown;
  final bool realtimeAvailable;

  const RouteAlertsFetch({
    required this.alerts,
    this.realtimeFlagKnown = false,
    this.realtimeAvailable = false,
  });
}

class BusApiService {
  static String get baseUrl => ApiConfig.api;
  static final _ResettableClient _stops = _ResettableClient();
  static final _ResettableClient _eta = _ResettableClient();
  static final _ResettableClient _detour = _ResettableClient();
  static final _ResettableClient _catalog = _ResettableClient();
  static final _ResettableClient _config = _ResettableClient();

  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json',
  };

  static Future<http.Response> _get(
    _ResettableClient client,
    String path, {
    required Duration timeout,
  }) async {
    Future<http.Response> once() => client.get(
      '${ApiConfig.api}$path',
      headers: _headers,
      timeout: timeout,
    );

    // One retry on the same (Cloudflare) origin with a fresh connection.
    try {
      final res = await once();
      if (!kIsWeb && ApiConfig.looksLikeChallenge(res)) {
        debugPrint('API got challenge/blocked ${res.statusCode}, retrying once');
        client.reset();
        return await once();
      }
      return res;
    } on TimeoutException {
      client.reset();
      if (!kIsWeb) return await once();
      rethrow;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('ClientException') || msg.contains('SocketException')) {
        client.reset();
        if (!kIsWeb) return await once();
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> fetchStops(String route, int dir, {String lang = 'zh'}) async {
    try {
      final res = await _get(
        _stops,
        '/bus-stops?route=$route&dir=$dir&lang=$lang',
        timeout: const Duration(seconds: 8),
      );

      if (res.body.trimLeft().startsWith('<')) {
        debugPrint('fetchStops got HTML ${res.statusCode}');
        return {'success': false, 'message': '伺服器回應逾時或被阻擋，請再試一次'};
      }
      final json = jsonDecode(res.body);
      if (json['success'] == true && (json['stops'] as List).isNotEmpty) {
        List<BusStop> stops = (json['stops'] as List).map((s) => BusStop.fromJson(s as Map<String, dynamic>)).toList();
        return {'success': true, 'stops': stops};
      }
      return {'success': false, 'message': json['message'] ?? '查無此路線之站點 / 此乃循環路線'};
    } catch (e) {
      debugPrint('fetchStops Error: $e');
      return {'success': false, 'message': '伺服器回應逾時或被阻擋，請再試一次'};
    }
  }

  /// Test hook. Production leaves this null and requests `/bus-eta`.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(
    String route,
    int dir, {
    int? targetStopSeq,
    String lang,
  })? debugFetchBusETA;

  static Future<Map<String, dynamic>> fetchBusETA(String route, int dir, {int? targetStopSeq, String lang = 'zh'}) async {
    final override = debugFetchBusETA;
    if (override != null) {
      return override(route, dir, targetStopSeq: targetStopSeq, lang: lang);
    }
    try {
      final seqParam = targetStopSeq != null ? '&targetStopSeq=$targetStopSeq' : '';
      final res = await _get(
        _eta,
        '/bus-eta?route=$route&dir=$dir$seqParam&lang=$lang',
        timeout: const Duration(seconds: 8),
      );

      if (res.body.trimLeft().startsWith('<')) {
        debugPrint('fetchBusETA got HTML ${res.statusCode}');
        return {'success': false, 'message': '伺服器回應逾時或被阻擋，請再試一次'};
      }
      final json = jsonDecode(res.body);
      if (json['success'] == true) {
        List<Bus> buses = ((json['allBuses'] ?? []) as List).map((b) => Bus.fromJson(b as Map<String, dynamic>)).toList();
        final dataList = json['dataList'] is List ? json['dataList'] as List : const <dynamic>[];
        buses = attachDataListEta(buses, dataList, extra: json['data']);
        return {
          'success': true,
          'etaData': json['data'],
          'allBuses': buses,
          'timetableDetails': json['debug_details'],
          // Buses between the terminal and the target stop.
          'approachingCount': (json['dataList'] is List) ? (json['dataList'] as List).length : 0,
          'lastBusWindow': json['lastBusWindow'] == true,
          'serviceEnded': json['serviceEnded'] == true,
          'realtimeFlagKnown': json['realtimeAvailable'] is bool,
          'realtimeAvailable': json['realtimeAvailable'] == true,
        };
      }
      return {'success': false, 'message': json['message'] ?? '查詢失敗'};
    } catch (e) {
      debugPrint('fetchBusETA timeout: $e');
      return {'success': false, 'message': '伺服器回應逾時或被阻擋，請再試一次'};
    }
  }

  static Future<Map<String, dynamic>?> fetchStopDetour({
    required String route,
    required String stationCode,
    required String lang,
  }) async {
    try {
      final res = await _get(
        _detour,
        '/stop-detour?route=${Uri.encodeQueryComponent(route)}'
        '&stationCode=${Uri.encodeQueryComponent(stationCode)}&lang=$lang',
        timeout: const Duration(seconds: 12),
      );
      if (res.statusCode != 200) return null;
      if (res.body.trimLeft().startsWith('<')) return null;
      final json = jsonDecode(res.body);
      if (json['success'] == true && json['data'] != null) {
        return Map<String, dynamic>.from(json['data'] as Map);
      }
    } catch (e) {
      debugPrint('fetchStopDetour Error: $e');
    }
    return null;
  }

  static Future<RouteAlertsFetch> fetchRouteAlerts(String route) async {
    try {
      final res = await _get(
        _catalog,
        '/bus-alerts?route=${Uri.encodeQueryComponent(route)}',
        timeout: const Duration(seconds: 6),
      );
      if (res.statusCode == 200 && !res.body.trimLeft().startsWith('<')) {
        final json = jsonDecode(res.body);
        if (json is Map && json['success'] == true && json['alerts'] is List) {
          return RouteAlertsFetch(
            alerts: (json['alerts'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(),
            realtimeFlagKnown: json['realtimeAvailable'] is bool,
            realtimeAvailable: json['realtimeAvailable'] == true,
          );
        }
      }
    } catch (e) {
      debugPrint('fetchRouteAlerts Error: $e');
    }
    return const RouteAlertsFetch(alerts: <Map<String, dynamic>>[]);
  }

  /// App-wide realtime switch and open-data credit. Null when the request fails.
  static Future<Map<String, dynamic>?> fetchAppConfig() async {
    try {
      final res = await _get(
        _config,
        '/config',
        timeout: const Duration(seconds: 6),
      );
      if (res.statusCode != 200 || res.body.trimLeft().startsWith('<')) return null;
      final json = jsonDecode(res.body);
      if (json is Map<String, dynamic>) return json;
      if (json is Map) return Map<String, dynamic>.from(json);
    } catch (e) {
      debugPrint('fetchAppConfig Error: $e');
    }
    return null;
  }

  /// specialRoutes from the last successful /all-routes.json (festival /
  /// date-only routes); null if the server did not send the field.
  static List<String>? lastSpecialRoutes;

  static Future<List<String>> fetchAllRoutes({String lang = 'zh'}) async {
    try {
      final res = await _get(
        _catalog,
        '/all-routes.json?lang=$lang',
        timeout: const Duration(seconds: 5),
      );

      if (res.statusCode == 200 && !res.body.trimLeft().startsWith('<')) {
        final json = jsonDecode(res.body);
        if (json['success'] == true) {
          final sp = json['specialRoutes'];
          lastSpecialRoutes = sp is List ? sp.map((e) => '$e'.trim().toUpperCase()).toList() : null;
          return List<String>.from(json['routes']);
        }
      }
    } catch (e) {
      debugPrint('fetchAllRoutes Error: $e');
    }
    return [];
  }

  static Future<List<String>> searchRoutes(String query, {String lang = 'zh'}) async {
    try {
      final res = await _get(
        _catalog,
        '/all-routes.json?q=$query&lang=$lang',
        timeout: const Duration(seconds: 5),
      );

      if (res.statusCode == 200 && !res.body.trimLeft().startsWith('<')) {
        final json = jsonDecode(res.body);
        if (json['success'] == true) return List<String>.from(json['routes']);
      }
    } catch (e) {
      debugPrint('searchRoutes Error: $e');
    }
    return [];
  }
}
