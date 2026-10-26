// Soft map position from ETA minutes and per-leg travel time.
//
// The client does not receive learned hop tables. Bus.etaMinutes is the
// whole-minute ETA to the selected stop. etaRemainingOnLeg turns that into
// seconds still left on the current leg: the whole ETA when the selected
// stop is the next one, otherwise a share of it. The share uses learned
// hop durations when every remaining hop has one, and distance otherwise.
//
// The icon then blends that pace with damped dead-reckoning. This file only
// does the arithmetic. The controller keeps the no-backward clamp, the
// at-stop placement, and the leg cap.

class MapLegHop {
  final int fromSeq;
  final int toSeq;
  final double meters;

  /// Full travel time of this hop, when the device has learned one.
  final double? learnedSeconds;

  const MapLegHop({
    required this.fromSeq,
    required this.toSeq,
    required this.meters,
    this.learnedSeconds,
  });
}

/// Seconds from the fix until the bus should reach the end of the first hop.
///
/// [hops] starts with the current leg and ends at the ETA stop. Null when
/// the remaining time or the gap is too small to pace the icon (a coarse
/// 0-minute ETA, or the bus is already at the stop).
double? etaRemainingOnLeg({
  required int etaMinutes,
  required List<MapLegHop> hops,
  required double gpsMeters,
  double minGapMeters = 25,
  double minRemainingSeconds = 20,
}) {
  if (etaMinutes < 1 || hops.isEmpty) return null;
  final leg = hops.first.meters;
  if (leg < 1) return null;
  var gap = leg - gpsMeters;
  if (gap < 0) gap = 0;
  if (gap < minGapMeters) return null;

  final learnedComplete = hops.every(
    (hop) => hop.learnedSeconds != null && hop.learnedSeconds! >= 1,
  );
  final double share;
  if (learnedComplete) {
    final firstRemain = hops.first.learnedSeconds! * (gap / leg);
    var total = firstRemain;
    for (var i = 1; i < hops.length; i++) {
      total += hops[i].learnedSeconds!;
    }
    if (total < 1) return null;
    share = firstRemain / total;
  } else {
    var total = gap;
    for (var i = 1; i < hops.length; i++) {
      final meters = hops[i].meters;
      if (meters > 0) total += meters;
    }
    if (total < 1) return null;
    share = gap / total;
  }
  final remaining = etaMinutes * 60.0 * share;
  if (remaining < minRemainingSeconds) return null;
  return remaining;
}

/// Metres per second that covers [gapMeters] in [remainingSeconds].
///
/// Capped so a one-minute ETA over a long gap cannot sprint. Null when the
/// inputs are too coarse to be a reference.
double? etaPaceMps({
  required double gapMeters,
  required double remainingSeconds,
  double maxMps = 22,
  double minGapMeters = 25,
  double minRemainingSeconds = 20,
}) {
  if (remainingSeconds < minRemainingSeconds || gapMeters < minGapMeters) {
    return null;
  }
  var mps = gapMeters / remainingSeconds;
  if (mps > maxMps) mps = maxMps;
  if (mps <= 0) return null;
  return mps;
}

/// Where a learned full-leg duration says the bus is, counting from departure.
///
/// Null when that point is not ahead of the snapshot. The caller must not
/// move the icon backward to meet the clock.
double? learnedLegMeters({
  required double legMeters,
  required double gpsMeters,
  required double elapsedSeconds,
  required double learnedSeconds,
}) {
  if (learnedSeconds < 1 || legMeters < 1 || elapsedSeconds < 0) return null;
  var t = elapsedSeconds / learnedSeconds;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final ref = legMeters * t;
  if (ref <= gpsMeters + 0.5) return null;
  return ref;
}

/// Blend damped dead-reckoning with a time reference.
///
/// [timeMeters] is ignored when it is missing or not ahead of the snapshot.
/// The result stays within `[gpsMeters, cap]`.
double blendLegMeters({
  required double gpsMeters,
  required double speedMeters,
  required double? timeMeters,
  required double blend,
  required double cap,
}) {
  var speed = speedMeters;
  if (speed < gpsMeters) speed = gpsMeters;
  var meters = speed;
  if (timeMeters != null && timeMeters > gpsMeters) {
    final w = blend < 0 ? 0.0 : (blend > 1 ? 1.0 : blend);
    meters = speed * (1 - w) + timeMeters * w;
  }
  if (meters < gpsMeters) meters = gpsMeters;
  if (meters > cap) meters = cap;
  if (meters < 0) meters = 0;
  return meters;
}
