import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Prefer Cloudflare so cache / TLS / DDoS stay on the edge.
/// If CF returns a challenge HTML page, native apps fall back to origin
/// for the rest of the session.
class ApiConfig {
  static const String cdnOrigin = 'https://macaubus-kat1.com';
  static const String directOrigin = 'http://158.101.140.210:3000';

  static bool _useDirect = false;

  static String get origin {
    if (kIsWeb) return cdnOrigin;
    return _useDirect ? directOrigin : cdnOrigin;
  }

  static String get api => '$origin/api';

  static void preferDirectOrigin() {
    if (kIsWeb || _useDirect) return;
    _useDirect = true;
    debugPrint('API fallback to origin (Cloudflare blocked JSON)');
  }

  static bool looksLikeChallenge(http.Response res) {
    if (res.statusCode == 403 || res.statusCode == 429 || res.statusCode == 503) {
      return true;
    }
    final body = res.body.trimLeft();
    return body.startsWith('<');
  }
}
