import 'package:http/http.dart' as http;

/// All traffic goes through Cloudflare (TLS, cache, DDoS protection).
/// The origin server's IP is intentionally not shipped in the app.
///
/// This host is the bus API only. Store marketing, support, and privacy
/// URLs live in store_links.dart and are not served from here.
class ApiConfig {
  static const String origin = 'https://macaubus-kat1.com';

  static String get api => '$origin/api';

  /// True when Cloudflare answered with a block/challenge page instead of JSON.
  static bool looksLikeChallenge(http.Response res) {
    if (res.statusCode == 403 || res.statusCode == 429 || res.statusCode == 503) {
      return true;
    }
    final body = res.body.trimLeft();
    return body.startsWith('<');
  }
}