/// Minutes until an approaching bus.
///
/// The first bus keeps the official status text when that text includes a
/// minute count. Later buses use their own server [busEtaMinutes] when the
/// payload has one, instead of scaling the first bus's time by stop distance.
int approachingEtaMinutes({
  required int? busEtaMinutes,
  required bool isFirst,
  required int stopsAway,
  required int firstStopsAway,
  required int? firstStatusMinutes,
}) {
  final own = (busEtaMinutes != null && busEtaMinutes >= 0) ? busEtaMinutes : null;
  if (!isFirst && own != null) return own;
  if (isFirst && firstStatusMinutes != null) return firstStatusMinutes;
  if (own != null) return own;
  if (firstStatusMinutes != null && firstStopsAway > 0) {
    return (stopsAway * (firstStatusMinutes / firstStopsAway)).round();
  }
  return (stopsAway * 2.5).round();
}
