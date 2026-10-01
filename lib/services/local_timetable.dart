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

  static bool noServiceToday(String route) {
    final rows = _rowsFor(route);
    if (rows.isEmpty) {
      final r = normalizeRoute(route);
      return r == '15T' || r == '21AT' || r == '26AT';
    }
    return rows.any(_rowIsNoService);
  }

  /// First bus of every direction is still in the future.
  static bool serviceNotStarted(String route) =>
      _windowState(route) == _Win.notStarted;

  static bool serviceEnded(String route) => _windowState(route) == _Win.ended;

  static bool unavailableForPlanning(String route) {
    if (noServiceToday(route)) return true;
    final win = _windowState(route);
    return win == _Win.notStarted || win == _Win.ended;
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

  static _Win _windowState(String route) {
    final now = DateTime.now();
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
