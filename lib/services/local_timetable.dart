import 'dart:convert';
import 'package:flutter/services.dart';

/// Official DSAT window from the app bundle — no network.
/// Used to hide 不設服務 / 尚未開始 / 已結束 routes before ETA/stop APIs.
class LocalTimetable {
  static Map<String, dynamic> _map = {};
  static bool _loaded = false;

  static String normalizeRoute(String route) {
    var r = route.trim().toUpperCase();
    if (r.contains(':')) r = r.split(':').last;
    r = r.replaceAll(RegExp(r'\s+'), '');
    r = r.replaceAll('線', '').replaceAll('线', '');
    return r;
  }

  static Future<void> ensureLoaded() async {
    if (_loaded && _map.isNotEmpty) return;
    try {
      final raw = await rootBundle.loadString('assets/timetable.json');
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _map = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Keep previous map if reload fails.
    }
    _loaded = _map.isNotEmpty;
  }

  /// Seasonal routes whose dates come from the OTP GTFS calendar (e.g. 21AT
  /// runs 1-7 Oct). The bundled snapshot says 不設服務, so for OTP legs (which
  /// pass a boarding time) the OTP schedule is trusted instead.
  static const Set<String> _calendarGoverned = {'21AT', '26AT'};

  static bool noServiceToday(String route, {DateTime? at}) {
    if (at != null && _calendarGoverned.contains(normalizeRoute(route))) {
      return false;
    }
    final rows = _rowsFor(route);
    if (rows.isEmpty) {
      final r = normalizeRoute(route);
      // 21AT/26AT now come from the OTP calendar (date-range services), so
      // only 15T is still assumed out of service when not in the timetable.
      return r == '15T';
    }
    return rows.any(_rowIsNoService);
  }

  /// First bus of every direction is still in the future.
  /// [at] is a Macau wall-clock time (e.g. the leg's boarding time); defaults
  /// to now. Only hour/minute are used, so times past midnight work with
  /// overnight windows (N2 00:11 is inside 23:xx-06:xx).
  static bool serviceNotStarted(String route, {DateTime? at}) =>
      _windowState(route, at) == _Win.notStarted;

  static bool serviceEnded(String route, {DateTime? at}) =>
      _windowState(route, at) == _Win.ended;

  /// Running filter for planning. [at] set = an OTP leg's scheduled boarding
  /// time at that stop: the OTP GTFS has explicit trips with per-stop times
  /// and day/holiday services, so the leg is trusted as-is (the bundled
  /// windows are terminal departures and wrongly dropped mid-route boardings
  /// after the last terminal departure). Without [at] (official fallback
  /// suggestions) the bundled window is checked against now.
  static bool unavailableForPlanning(String route, {DateTime? at}) {
    if (at != null) return false;
    if (noServiceToday(route)) return true;
    final win = _windowState(route, at);
    return win == _Win.notStarted || win == _Win.ended;
  }

  /// [at] (Macau wall clock) is within [beforeMins] before to [afterMins]
  /// after a route's last terminal departure: the boarding may be on one of
  /// the last trips, so a live ETA cross-check is worth showing.
  static bool nearLastTrip(
    String route,
    DateTime at, {
    int beforeMins = 30,
    int afterMins = 90,
  }) {
    final atMins = at.hour * 60 + at.minute;
    for (final row in _rowsFor(route)) {
      if (_rowIsNoService(row)) continue;
      final endMins = _toMins('${row['endTime'] ?? ''}');
      if (endMins == null) continue;
      final delta = (atMins - endMins + 1440) % 1440; // minutes after end
      if (delta <= afterMins || delta >= 1440 - beforeMins) return true;
    }
    return false;
  }

  static List<Map> _rowsFor(String route) {
    final r = normalizeRoute(route);
    if (r.isEmpty || _map.isEmpty) return const [];
    final rows = <Map>[];
    for (final entry in _map.entries) {
      final key = entry.key.toUpperCase();
      if (key == '${r}_0' ||
          key == '${r}_1' ||
          key.startsWith('${r}_')) {
        if (entry.value is Map) rows.add(entry.value as Map);
      }
    }
    return rows;
  }

  static bool _rowIsNoService(Map row) {
    final start = '${row['startTime'] ?? ''}';
    final end = '${row['endTime'] ?? ''}';
    return start.contains('不設服務') ||
        start.contains('不设服务') ||
        end.contains('不設服務') ||
        end.contains('不设服务');
  }

  static int? _toMins(String raw) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(raw.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    return h * 60 + min;
  }

  static _Win _windowState(String route, [DateTime? at]) {
    final now = at ?? DateTime.now();
    final nowMins = now.hour * 60 + now.minute;
    var anyRunning = false;
    var anyNotStarted = false;
    var anyEnded = false;

    for (final row in _rowsFor(route)) {
      if (_rowIsNoService(row)) continue;
      final startMins = _toMins('${row['startTime'] ?? ''}');
      final endMins = _toMins('${row['endTime'] ?? ''}');
      if (startMins == null || endMins == null) continue;

      final overnight = startMins > endMins;
      final running = overnight
          ? (nowMins >= startMins || nowMins <= endMins)
          : (nowMins >= startMins && nowMins <= endMins);
      if (running) {
        anyRunning = true;
        continue;
      }

      if (!overnight) {
        if (nowMins < startMins) {
          anyNotStarted = true;
        } else {
          anyEnded = true;
        }
        continue;
      }

      // Overnight route, currently in the gap (after last bus, before first).
      final distEnded = (nowMins - endMins + 1440) % 1440;
      final distStart = (startMins - nowMins + 1440) % 1440;
      if (distStart <= distEnded) {
        anyNotStarted = true;
      } else {
        anyEnded = true;
      }
    }

    if (anyRunning) return _Win.running;
    if (anyNotStarted && !anyEnded) return _Win.notStarted;
    if (anyEnded && !anyNotStarted) return _Win.ended;
    if (anyNotStarted) return _Win.notStarted;
    if (anyEnded) return _Win.ended;
    return _Win.unknown;
  }
}

enum _Win { unknown, running, notStarted, ended }
