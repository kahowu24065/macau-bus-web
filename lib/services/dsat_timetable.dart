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
/// DSAT route PDFs publish headway ranges, not a clock of departures. This is
/// separate from LocalTimetable, which only stores first/last service windows
/// for planning filters (`assets/timetable.json` and `/api/timetable.json`).
///
/// Schema `dsat-frequency-bands-v1`:
/// ```
/// {
///   "routes": {
///     "1A": {
///       "source_url": "https://www.dsat.gov.mo/dsat/download_route.aspx?route=busroute_1A",
///       "pdf_date": "2025-10-25",
///       "directions": {
///         "0": {
///           "sections": [
///             {
///               "title": "星期一至六（公眾假期除外）",
///               "items": [{"time": "06:00-07:00", "freq": "9 - 11"}]
///             }
///           ]
///         }
///       }
///     }
///   }
/// }
/// ```
/// Section titles stay in Chinese; the dialog translates them. A route stored
/// with a single direction (circular) is shown for either direction index.
/// An unknown route, or a missing direction on a two-direction route, is empty.
class DsatTimetable {
  static const assetPath = 'assets/dsat_timetables.json';

  static Map<String, dynamic> _routes = {};
  static bool _loaded = false;

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

  static bool hasRoute(String route) {
    final entry = _routes[normalizeRoute(route)];
    return entry is Map && entry['directions'] is Map && (entry['directions'] as Map).isNotEmpty;
  }

  static List<DsatTimetableSection> sectionsFor(String route, int direction) {
    final entry = _routes[normalizeRoute(route)];
    if (entry is! Map) return const [];
    final dirs = entry['directions'];
    if (dirs is! Map || dirs.isEmpty) return const [];

    var node = dirs['$direction'];
    if (node == null && dirs.length == 1) {
      node = dirs.values.first;
    }
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
        final freq = item['freq']?.toString() ?? '';
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
