import 'dart:convert';

import 'package:flutter/services.dart';

/// One headway row: a service-time band and a frequency range such as "9 - 11".
class DsatFrequencyBand {
  final String time;
  final String freq;

  const DsatFrequencyBand({required this.time, required this.freq});
}

/// A day-type block (for example 星期一至六（公眾假期除外）).
class DsatTimetableSection {
  final String title;
  final List<DsatFrequencyBand> items;

  const DsatTimetableSection({required this.title, required this.items});
}

/// Official DSAT frequency bands bundled in `assets/dsat_timetables.json`.
///
/// The dialog reads each route's `app_frequency` (day sections, then one row
/// list per direction). DSAT sheets are headway ranges; route 71S is the
/// exception and stores exact clocks. This is separate from LocalTimetable,
/// which only stores first/last service windows for planning filters
/// (`assets/timetable.json` and `/api/timetable.json`).
///
/// A circular route (one direction in `app_frequency`) is shown for either
/// direction index. An unknown route, or a missing direction on a
/// two-direction route, is empty.
class DsatTimetable {
  static const assetPath = 'assets/dsat_timetables.json';

  static final _headway = RegExp(r'^(\d+)\s*[-–]\s*(\d+)$');

  static Map<String, dynamic> _routes = {};
  static bool _loaded = false;

  /// Routes present in the bundled DSAT file.
  static int get routeCount => _routes.length;

  static String normalizeRoute(String route) {
    var r = route.trim().toUpperCase();
    if (r.contains(':')) r = r.split(':').last;
    r = r.replaceAll(RegExp(r'\s+'), '');
    r = r.replaceAll('線', '').replaceAll('线', '');
    return r;
  }

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['routes'] is Map) {
        _routes = Map<String, dynamic>.from(decoded['routes'] as Map);
      }
    } catch (_) {
      _routes = {};
    }
    _loaded = true;
  }

  static bool hasRoute(String route) => sectionsFor(route, 0).isNotEmpty;

  /// Headway "9-11" is shown as "9 - 11". Exact clocks and suspended-service
  /// cells are left as published.
  static String displayFreq(String raw) {
    final m = _headway.firstMatch(raw.trim());
    if (m == null) return raw.trim();
    return '${m.group(1)} - ${m.group(2)}';
  }

  static List<DsatTimetableSection> sectionsFor(String route, int direction) {
    final entry = _routes[normalizeRoute(route)];
    if (entry is! Map) return const [];
    final app = entry['app_frequency'];
    if (app is Map && app['sections'] is List) {
      return _fromAppFrequency(app, direction);
    }
    return _fromLegacyDirections(entry['directions'], direction);
  }

  static List<DsatTimetableSection> _fromAppFrequency(Map app, int direction) {
    final sections = app['sections'];
    if (sections is! List || sections.isEmpty) return const [];

    var widest = 0;
    for (final sec in sections) {
      if (sec is Map && sec['directions'] is List) {
        final n = (sec['directions'] as List).length;
        if (n > widest) widest = n;
      }
    }
    if (widest == 0) return const [];
    final index = widest == 1 ? 0 : direction;
    if (index < 0 || index >= widest) return const [];

    final out = <DsatTimetableSection>[];
    for (final sec in sections) {
      if (sec is! Map) continue;
      final dirs = sec['directions'];
      if (dirs is! List || index >= dirs.length) continue;
      final dir = dirs[index];
      if (dir is! Map) continue;
      final rows = dir['rows'];
      if (rows is! List) continue;
      final items = <DsatFrequencyBand>[];
      for (final row in rows) {
        if (row is! Map) continue;
        final time = (row['服務時間'] ?? row['time'] ?? '').toString().trim();
        final freq = displayFreq((row['班次(分鐘)'] ?? row['freq'] ?? '').toString());
        if (time.isEmpty && freq.isEmpty) continue;
        items.add(DsatFrequencyBand(time: time, freq: freq));
      }
      if (items.isEmpty) continue;
      out.add(DsatTimetableSection(
        title: sec['title']?.toString() ?? '',
        items: items,
      ));
    }
    return out;
  }

  /// Earlier seed file: directions keyed "0"/"1" with time/freq items.
  static List<DsatTimetableSection> _fromLegacyDirections(dynamic dirs, int direction) {
    if (dirs is! Map || dirs.isEmpty) return const [];
    var node = dirs['$direction'];
    if (node == null && dirs.length == 1) node = dirs.values.first;
    if (node is! Map) return const [];
    final sections = node['sections'];
    if (sections is! List) return const [];

    final out = <DsatTimetableSection>[];
    for (final sec in sections) {
      if (sec is! Map) continue;
      final itemsRaw = sec['items'];
      if (itemsRaw is! List) continue;
      final items = <DsatFrequencyBand>[];
      for (final item in itemsRaw) {
        if (item is! Map) continue;
        final time = item['time']?.toString() ?? '';
        final freq = displayFreq(item['freq']?.toString() ?? '');
        if (time.isEmpty && freq.isEmpty) continue;
        items.add(DsatFrequencyBand(time: time, freq: freq));
      }
      if (items.isEmpty) continue;
      out.add(DsatTimetableSection(
        title: sec['title']?.toString() ?? '',
        items: items,
      ));
    }
    return out;
  }
}
