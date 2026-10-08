import 'dart:math' as math;

/// One live bus the phone may follow for a boarding reminder.
class BoardingBusInput {
  final String license;
  final double lat;
  final double lng;
  final int currentStopSeq;
  final bool atStop;

  const BoardingBusInput({
    required this.license,
    required this.lat,
    required this.lng,
    required this.currentStopSeq,
    this.atStop = true,
  });
}

class BoardingPoint {
  final double lat;
  final double lng;
  final int? seq;

  const BoardingPoint(this.lat, this.lng, {this.seq});
}

enum BoardingChoiceFailure {
  /// The nearest bus in the right direction has no current or last position.
  noRecordedPosition,

  /// No bus is still coming toward this stop.
  noApproachingBus,

  /// Every located bus is already at or past the stop.
  alreadyPassed,
}

class BoardingChoice {
  final String? license;
  final double? lat;
  final double? lng;
  final bool usedLastRecorded;
  final BoardingChoiceFailure? failure;

  const BoardingChoice._({
    this.license,
    this.lat,
    this.lng,
    this.usedLastRecorded = false,
    this.failure,
  });

  const BoardingChoice.bus({
    required String license,
    required double lat,
    required double lng,
    required bool usedLastRecorded,
  }) : this._(
          license: license,
          lat: lat,
          lng: lng,
          usedLastRecorded: usedLastRecorded,
        );

  const BoardingChoice.failed(BoardingChoiceFailure failure)
      : this._(failure: failure);

  bool get ok => failure == null && license != null;
}

/// A GPS fix Macau can actually be at. Zero and other placeholders are not.
bool boardingCoordsUsable(double lat, double lng) {
  if (!lat.isFinite || !lng.isFinite) return false;
  return lat.abs() > 1 && lng.abs() > 1;
}

const double _passedMeters = 35;
const double _offRouteMeters = 300;
const double _latMeters = 110540;
final double _lngMeters = 111320 * math.cos(22.2 * math.pi / 180);

class _Xy {
  final double x;
  final double y;
  const _Xy(this.x, this.y);
}

_Xy _xy(double lat, double lng) => _Xy(lng * _lngMeters, lat * _latMeters);

double _dist(_Xy a, _Xy b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

class _Projection {
  final double along;
  final double cross;
  const _Projection(this.along, this.cross);
}

_Projection _project(double lat, double lng, List<_Xy> line, List<double> cumulative) {
  final p = _xy(lat, lng);
  var bestCross = double.infinity;
  var bestAlong = 0.0;
  for (var i = 0; i < line.length - 1; i++) {
    final a = line[i];
    final b = line[i + 1];
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final len2 = abx * abx + aby * aby;
    var t = 0.0;
    if (len2 > 0) {
      t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2;
      t = t.clamp(0.0, 1.0);
    }
    final qx = a.x + abx * t;
    final qy = a.y + aby * t;
    final cross = math.sqrt((p.x - qx) * (p.x - qx) + (p.y - qy) * (p.y - qy));
    final along = cumulative[i] + math.sqrt(len2) * t;
    if (cross < bestCross) {
      bestCross = cross;
      bestAlong = along;
    }
  }
  return _Projection(bestAlong, bestCross);
}

class _Placed {
  final BoardingBusInput bus;
  final double lat;
  final double lng;
  final double remaining;
  final bool usedLastRecorded;
  const _Placed({
    required this.bus,
    required this.lat,
    required this.lng,
    required this.remaining,
    required this.usedLastRecorded,
  });
}

/// Picks the single nearest bus traveling toward [targetSeq].
///
/// Located buses are compared by remaining distance along this direction's
/// route. A bus already past the stop is not a candidate, even when its
/// straight-line distance is shorter or its stop sequence is still behind.
/// The phone remembers that one bus's coordinates and does not estimate
/// the other buses.
BoardingChoice chooseBoardingBus({
  required List<BoardingBusInput> buses,
  required int targetSeq,
  required BoardingPoint? target,
  required List<BoardingPoint> stops,
  required List<BoardingPoint> routePoints,
  required Map<String, BoardingPoint> lastRecorded,
}) {
  if (target == null || !boardingCoordsUsable(target.lat, target.lng)) {
    return const BoardingChoice.failed(BoardingChoiceFailure.noApproachingBus);
  }

  final usingRoute = routePoints.length >= 2;
  final source = usingRoute
      ? routePoints
      : (stops.where((s) => boardingCoordsUsable(s.lat, s.lng)).toList()
        ..sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0)));
  if (source.length < 2) {
    return const BoardingChoice.failed(BoardingChoiceFailure.noApproachingBus);
  }

  final line = [for (final p in source) _xy(p.lat, p.lng)];
  final cumulative = <double>[0];
  for (var i = 1; i < line.length; i++) {
    cumulative.add(cumulative.last + _dist(line[i - 1], line[i]));
  }

  double targetAlong;
  if (!usingRoute) {
    final index = source.indexWhere((s) => s.seq == targetSeq);
    if (index < 0) {
      return const BoardingChoice.failed(BoardingChoiceFailure.noApproachingBus);
    }
    targetAlong = cumulative[index];
  } else {
    targetAlong = _project(target.lat, target.lng, line, cumulative).along;
  }

  final approaching = <_Placed>[];
  final unresolved = <BoardingBusInput>[];
  var sawPassed = false;

  for (final bus in buses) {
    if (bus.currentStopSeq == targetSeq) continue;

    final currentOk = boardingCoordsUsable(bus.lat, bus.lng);
    final last = lastRecorded[bus.license];
    final lastOk = last != null && boardingCoordsUsable(last.lat, last.lng);
    final double lat;
    final double lng;
    final bool usedLast;
    if (currentOk) {
      lat = bus.lat;
      lng = bus.lng;
      usedLast = false;
    } else if (lastOk) {
      lat = last.lat;
      lng = last.lng;
      usedLast = true;
    } else if (bus.currentStopSeq > 0 && bus.currentStopSeq < targetSeq) {
      unresolved.add(bus);
      continue;
    } else {
      continue;
    }

    final projected = _project(lat, lng, line, cumulative);
    if (projected.cross > _offRouteMeters) continue;
    final remaining = targetAlong - projected.along;
    if (remaining <= _passedMeters) {
      sawPassed = true;
      continue;
    }
    approaching.add(_Placed(
      bus: bus,
      lat: lat,
      lng: lng,
      remaining: remaining,
      usedLastRecorded: usedLast,
    ));
  }

  if (approaching.isEmpty) {
    if (unresolved.isNotEmpty) {
      return const BoardingChoice.failed(BoardingChoiceFailure.noRecordedPosition);
    }
    if (sawPassed) {
      return const BoardingChoice.failed(BoardingChoiceFailure.alreadyPassed);
    }
    return const BoardingChoice.failed(BoardingChoiceFailure.noApproachingBus);
  }

  approaching.sort((a, b) => a.remaining.compareTo(b.remaining));
  final nearest = approaching.first;
  final blocked = unresolved.any((bus) => bus.currentStopSeq > nearest.bus.currentStopSeq);
  if (blocked) {
    return const BoardingChoice.failed(BoardingChoiceFailure.noRecordedPosition);
  }

  return BoardingChoice.bus(
    license: nearest.bus.license,
    lat: nearest.lat,
    lng: nearest.lng,
    usedLastRecorded: nearest.usedLastRecorded,
  );
}

String boardingChoiceMessageKey(BoardingChoiceFailure failure) {
  switch (failure) {
    case BoardingChoiceFailure.noRecordedPosition:
      return 'boarding_no_position';
    case BoardingChoiceFailure.noApproachingBus:
      return 'boarding_no_bus';
    case BoardingChoiceFailure.alreadyPassed:
      return 'boarding_passed';
  }
}
