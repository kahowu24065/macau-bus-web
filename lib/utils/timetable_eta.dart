import 'package:latlong2/latlong.dart';

import '../services/dsat_timetable.dart';

/// Road speed used when the timetable only knows the terminus departure.
/// DSAT bands and exact clocks are not per-stop times.
const double timetableEtaKmh = 22;

/// Dwell at each stop the bus passes, not added at the terminus or the target.
const int timetableDwellSeconds = 25;

class TimetableStopPoint {
  final int seq;
  final double lat;
  final double lng;

  const TimetableStopPoint(this.seq, this.lat, this.lng);
}

/// Minutes to ride from the first stop to [targetSeq], or null when a hop
/// has no coordinates. The first stop itself is 0.
int? timetableTravelMinutes(List<TimetableStopPoint> stops, int targetSeq) {
  if (stops.isEmpty) return null;
  final ordered = [...stops]..sort((a, b) => a.seq.compareTo(b.seq));
  final targetIndex = ordered.indexWhere((stop) => stop.seq == targetSeq);
  if (targetIndex < 0) return null;
  if (targetIndex == 0) return 0;

  const distance = Distance();
  var meters = 0.0;
  for (var i = 0; i < targetIndex; i++) {
    final from = ordered[i];
    final to = ordered[i + 1];
    if (!_usable(from.lat, from.lng) || !_usable(to.lat, to.lng)) return null;
    meters += distance.as(
      LengthUnit.Meter,
      LatLng(from.lat, from.lng),
      LatLng(to.lat, to.lng),
    );
  }
  final intermediates = targetIndex - 1;
  final seconds = meters / (timetableEtaKmh * 1000 / 3600) +
      intermediates * timetableDwellSeconds;
  final minutes = (seconds / 60).round();
  return minutes < 0 ? 0 : minutes;
}

bool _usable(double lat, double lng) {
  return lat.isFinite && lng.isFinite && lat.abs() > 1 && lng.abs() > 1;
}

/// Minutes until the next timetable bus reaches this stop, or null.
///
/// A frequency band is a headway range, not a departure clock. The only
/// departures that can be timed are an exact clock (route 71S) and the
/// opening of a service period (a band start that does not continue from
/// the previous band). While that opening's bus can still be on its way,
/// the wait includes [travelMinutes] from the terminus. Inside a running
/// headway, this returns null rather than inventing a minute.
///
/// [nextDayRows] is used only after today's published service has finished,
/// so a suspended day does not show tomorrow's first bus.
int? timetableArrivalMinutes({
  required List<DsatFrequencyBand> rows,
  required DateTime now,
  required int travelMinutes,
  List<DsatFrequencyBand>? nextDayRows,
}) {
  final nowMinutes = now.hour * 60 + now.minute;
  final today = _evaluate(rows, nowMinutes, travelMinutes);
  if (today.kind == _WaitKind.eta) return today.minutes;
  if (today.kind == _WaitKind.running) return null;
  if (nextDayRows == null || !_hasDepartures(rows)) return null;
  final next = _evaluate(nextDayRows, nowMinutes - 1440, travelMinutes);
  if (next.kind == _WaitKind.eta) return next.minutes;
  return null;
}

enum _WaitKind { eta, running, none }

class _Wait {
  final _WaitKind kind;
  final int? minutes;

  const _Wait(this.kind, [this.minutes]);
}

class _Span {
  final int start;
  final int end;

  const _Span(this.start, this.end);
}

class _Schedule {
  final List<int> exact;
  final List<_Span> bands;

  const _Schedule(this.exact, this.bands);

  bool get hasDepartures => exact.isNotEmpty || bands.isNotEmpty;
}

bool _hasDepartures(List<DsatFrequencyBand> rows) => _parse(rows).hasDepartures;

final RegExp _clock = RegExp(r'^(\d{1,2}):(\d{2})$');
final RegExp _band = RegExp(
  r'^(\d{1,2}):(\d{2})\s*[-–－~～]\s*(\d{1,2}):(\d{2})$',
);

bool _suspended(String freq) {
  final text = freq.toLowerCase();
  return text.contains('暫停') ||
      text.contains('暂停') ||
      text.contains('suspenso') ||
      text.contains('不設') ||
      text.contains('不设');
}

int? _clockMinutes(String hour, String minute) {
  final h = int.tryParse(hour);
  final m = int.tryParse(minute);
  if (h == null || m == null || h > 23 || m > 59) return null;
  return h * 60 + m;
}

_Schedule _parse(List<DsatFrequencyBand> rows) {
  final exact = <int>[];
  final bands = <_Span>[];
  for (final row in rows) {
    final time = row.time.trim();
    if (_suspended(row.freq)) continue;
    final clock = _clock.firstMatch(time);
    if (clock != null) {
      final minutes = _clockMinutes(clock.group(1)!, clock.group(2)!);
      if (minutes != null) exact.add(minutes);
      continue;
    }
    final band = _band.firstMatch(time);
    if (band == null) continue;
    final start = _clockMinutes(band.group(1)!, band.group(2)!);
    final endClock = _clockMinutes(band.group(3)!, band.group(4)!);
    if (start == null || endClock == null || start == endClock) continue;
    final end = endClock > start ? endClock : endClock + 1440;
    bands.add(_Span(start, end));
  }
  return _Schedule(exact, bands);
}

int _mod(int minutes) => ((minutes % 1440) + 1440) % 1440;

bool _covered(List<_Span> bands, int now) {
  if (now < 0 || now >= 1440) return false;
  for (final band in bands) {
    if (now >= band.start && now < band.end) return true;
    if (now + 1440 >= band.start && now + 1440 < band.end) return true;
  }
  return false;
}

List<int> _openings(List<_Span> bands) {
  final starts = bands.map((band) => band.start % 1440).toSet().toList()..sort();
  final openings = <int>[];
  for (final start in starts) {
    final before = (start - 1 + 1440) % 1440;
    if (!_covered(bands, before)) openings.add(start);
  }
  return openings;
}

_Wait _evaluate(List<DsatFrequencyBand> rows, int now, int travel) {
  final schedule = _parse(rows);
  if (schedule.exact.isNotEmpty) {
    int? best;
    for (final depart in schedule.exact) {
      final wait = depart + travel - now;
      if (wait < 0) continue;
      if (best == null || wait < best) best = wait;
    }
    return best == null ? const _Wait(_WaitKind.none) : _Wait(_WaitKind.eta, best);
  }
  if (schedule.bands.isEmpty) return const _Wait(_WaitKind.none);

  final openings = _openings(schedule.bands);
  final clock = now >= 0 && now < 1440 ? now : _mod(now);
  if (now >= 0 && now < 1440 && _covered(schedule.bands, clock)) {
    final active = _activeOpening(schedule.bands, openings, now);
    if (active == null) return const _Wait(_WaitKind.running);
    final wait = active + travel - now;
    if (wait >= 0) return _Wait(_WaitKind.eta, wait);
    return const _Wait(_WaitKind.running);
  }

  int? best;
  for (final opening in openings) {
    final wait = opening + travel - now;
    if (wait < 0) continue;
    if (best == null || wait < best) best = wait;
  }
  return best == null ? const _Wait(_WaitKind.none) : _Wait(_WaitKind.eta, best);
}

/// Latest service-period opening whose coverage still includes [now].
int? _activeOpening(List<_Span> bands, List<int> openings, int now) {
  int? best;
  for (final opening in openings) {
    var start = opening;
    if (start > now) start -= 1440;
    if (start > now) continue;
    var covered = true;
    for (var minute = start; minute <= now; minute++) {
      if (!_covered(bands, _mod(minute))) {
        covered = false;
        break;
      }
    }
    if (!covered) continue;
    if (best == null || start > best) best = start;
  }
  return best;
}

bool statusHasMinuteCount(String status) {
  return RegExp(
    r'\d+\s*(?:分鐘|分钟|mins?|min)\b',
    caseSensitive: false,
  ).hasMatch(status);
}

/// Puts [timetableLabel] in the first arrival row only when that row is not
/// already a realtime bus or a realtime minute count.
List<Map<String, String>> withTimetableEta({
  required List<Map<String, String>> upcoming,
  required String? timetableLabel,
  required String noServiceToday,
}) {
  if (timetableLabel == null || timetableLabel.isEmpty) return upcoming;
  if (upcoming.isEmpty) {
    return [
      {'status': timetableLabel, 'plate': ''},
    ];
  }
  final first = upcoming.first;
  final status = first['status'] ?? '';
  final plate = (first['plate'] ?? '').trim();
  if (plate.isNotEmpty || statusHasMinuteCount(status) || status.contains(noServiceToday)) {
    return upcoming;
  }
  return [
    {'status': timetableLabel, 'plate': ''},
    for (final row in upcoming.skip(1))
      if ((row['plate'] ?? '').trim().isNotEmpty) row,
  ];
}
