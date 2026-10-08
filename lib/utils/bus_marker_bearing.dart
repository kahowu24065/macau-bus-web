import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const _distance = Distance();

/// Clockwise degrees from north, along the route from [position] toward [nextStop].
///
/// When [route] has a shape, the aim is the next vertex ahead on that shape,
/// so a bend is followed instead of a straight line to the stop.
double? busTravelBearingDegrees({
  required LatLng position,
  required LatLng nextStop,
  List<LatLng> route = const [],
}) {
  final aim = _aimPoint(position: position, nextStop: nextStop, route: route);
  if (aim == null) return null;
  if (_distance(position, aim) < 1) return null;
  return (_distance.bearing(position, aim) + 360) % 360;
}

/// The part of [route] from [from] to [to], walking forward along the line.
List<LatLng> routeSlice(List<LatLng> route, LatLng from, LatLng to) {
  if (route.length < 2) return const [];
  final start = _nearestIndex(route, from, 0, route.length - 1);
  final end = _nearestIndex(route, to, start, route.length - 1);
  if (end <= start) return const [];
  return route.sublist(start, end + 1);
}

/// Radians for an up-pointing chevron inside a marker that flutter_map
/// counter-rotates by [mapRotationDegrees].
///
/// The map layer is rotated by +rotation and the marker child is rotated by
/// -rotation so the info tab stays upright. Adding the map rotation back makes
/// the chevron follow the road instead of sticking to the screen.
double busChevronRadians({
  required double bearingDegrees,
  required double mapRotationDegrees,
}) {
  return (bearingDegrees + mapRotationDegrees) * math.pi / 180.0;
}

LatLng? _aimPoint({
  required LatLng position,
  required LatLng nextStop,
  required List<LatLng> route,
}) {
  if (route.length < 2) {
    return _distance(position, nextStop) < 1 ? null : nextStop;
  }
  final spanEnd = _nearestIndex(route, nextStop, 0, route.length - 1);
  if (spanEnd <= 0) {
    return _distance(position, nextStop) < 1 ? null : nextStop;
  }
  var bestI = 0;
  var bestD = double.infinity;
  var bestT = 0.0;
  for (var i = 0; i < spanEnd; i++) {
    final proj = _projectSegment(route[i], route[i + 1], position);
    final d = _distance(position, proj.point);
    if (d < bestD) {
      bestD = d;
      bestI = i;
      bestT = proj.t;
    }
  }
  if (bestT > 0.98 && bestI + 1 < spanEnd) {
    final next = route[bestI + 2];
    return _distance(position, next) < 1 ? null : next;
  }
  final end = route[bestI + 1];
  if (_distance(position, end) < 1) {
    if (bestI + 2 <= spanEnd) return route[bestI + 2];
    return _distance(position, nextStop) < 1 ? null : nextStop;
  }
  return end;
}

int _nearestIndex(List<LatLng> route, LatLng target, int from, int to) {
  final lo = math.min(from, to);
  final hi = math.max(from, to);
  var best = lo;
  var bestD = double.infinity;
  for (var i = lo; i <= hi; i++) {
    final d = _distance(route[i], target);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

({LatLng point, double t}) _projectSegment(LatLng a, LatLng b, LatLng p) {
  final lat0 = ((a.latitude + b.latitude) / 2) * math.pi / 180;
  double x(LatLng q) => q.longitude * math.cos(lat0);
  double y(LatLng q) => q.latitude;
  final dx = x(b) - x(a);
  final dy = y(b) - y(a);
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : ((x(p) - x(a)) * dx + (y(p) - y(a)) * dy) / len2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  return (
    point: LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    ),
    t: t,
  );
}
