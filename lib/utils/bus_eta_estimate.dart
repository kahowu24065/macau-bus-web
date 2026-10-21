import '../models/bus.dart';

/// Minutes until an approaching bus, or null when no count should be shown.
///
/// Every bus, including the first, uses its own [busEtaMinutes] from the
/// matching `dataList` entry. The official status text is only a fallback
/// when that value is missing. With neither, a later bus can scale from the
/// first bus's known minutes. There is no fixed minutes-per-stop guess:
/// one stop away must not become "約 3 分鐘" just because 1 × 2.5 rounds to 3.
int? approachingEtaMinutes({
  required int? busEtaMinutes,
  required bool isFirst,
  required int stopsAway,
  required int firstStopsAway,
  required int? firstStatusMinutes,
}) {
  final own = (busEtaMinutes != null && busEtaMinutes >= 0) ? busEtaMinutes : null;
  if (own != null) return own;
  if (isFirst && firstStatusMinutes != null) return firstStatusMinutes;
  if (!isFirst && firstStatusMinutes != null && firstStopsAway > 0) {
    return (stopsAway * (firstStatusMinutes / firstStopsAway)).round();
  }
  return null;
}

/// Copies `etaMinutes` from [dataList] onto buses that share a license.
///
/// `allBuses` does not carry the minutes. [extra] is the single `data`
/// object, used only when that license is not already in [dataList].
List<Bus> attachDataListEta(List<Bus> buses, List<dynamic> dataList, {dynamic extra}) {
  final minutes = <String, int>{};
  void take(dynamic item) {
    if (item is! Map) return;
    final license = _licenseOf(item);
    if (license == null) return;
    final mins = parseEtaMinutes(item['etaMinutes']);
    if (mins == null || mins < 0) return;
    minutes.putIfAbsent(_licenseKey(license), () => mins);
  }

  for (final item in dataList) {
    take(item);
  }
  take(extra);
  if (minutes.isEmpty) return buses;
  return [
    for (final bus in buses)
      if (minutes.containsKey(_licenseKey(bus.busLicense)) &&
          minutes[_licenseKey(bus.busLicense)] != bus.etaMinutes)
        Bus(
          busLicense: bus.busLicense,
          lat: bus.lat,
          lng: bus.lng,
          speed: bus.speed,
          currentStopSeq: bus.currentStopSeq,
          atStop: bus.atStop,
          etaMinutes: minutes[_licenseKey(bus.busLicense)],
        )
      else
        bus,
  ];
}

int? parseEtaMinutes(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

String? _licenseOf(Map<dynamic, dynamic> item) {
  for (final key in ['busLicense', 'busPlate', 'plate']) {
    final raw = item[key]?.toString().trim() ?? '';
    if (raw.isNotEmpty) return raw;
  }
  return null;
}

String _licenseKey(String license) => license.trim().toUpperCase();

/// Minutes in an official status line such as 「約 9 分鐘」 or "9 min".
///
/// Parenthetical notes are dropped first, matching the route stop card.
int? parseStatusEtaMinutes(String? status) {
  if (status == null || status.isEmpty) return null;
  final clean = status.replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
  final match = RegExp(
    r'(?:約\s*|~\s*)?(\d+)\s*(?:分鐘|mins|min)',
    caseSensitive: false,
  ).firstMatch(clean);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// Realtime minutes for one chosen bus, using the route card's formula.
///
/// [etaStatus] is the official status for [targetSeq] only. Another bus's
/// minutes are not returned. 0 means that bus is at the stop or has passed
/// it. Null means this bus has no minute count yet, so the caller keeps the
/// countdown it already showed.
int? boardingBusLiveMinutes({
  required List<Bus> buses,
  required int targetSeq,
  required String license,
  String? etaStatus,
}) {
  final key = _licenseKey(license);
  if (key.isEmpty || targetSeq <= 0) return null;

  Bus? chosen;
  for (final bus in buses) {
    if (_licenseKey(bus.busLicense) == key) {
      chosen = bus;
      break;
    }
  }
  if (chosen == null || chosen.currentStopSeq <= 0) return null;
  if (chosen.currentStopSeq > targetSeq) return 0;
  if (chosen.currentStopSeq == targetSeq) return 0;

  final approaching = buses.where((bus) {
    if (bus.currentStopSeq <= 0 || bus.currentStopSeq > targetSeq) return false;
    if (bus.currentStopSeq == targetSeq && !bus.atStop) return false;
    return true;
  }).toList()
    ..sort(
      (a, b) => (targetSeq - a.currentStopSeq).compareTo(targetSeq - b.currentStopSeq),
    );
  if (approaching.isEmpty) return null;

  final firstStatus = parseStatusEtaMinutes(etaStatus);
  var firstStops = -1;
  int? reference = firstStatus;
  var seenPositive = false;
  for (final bus in approaching) {
    final stopsAway = targetSeq - bus.currentStopSeq;
    if (firstStops == -1) firstStops = stopsAway;
    if (stopsAway <= 0) {
      if (_licenseKey(bus.busLicense) == key) return 0;
      continue;
    }
    final isFirst = !seenPositive;
    seenPositive = true;
    final estimated = approachingEtaMinutes(
      busEtaMinutes: bus.etaMinutes,
      isFirst: isFirst,
      stopsAway: stopsAway,
      firstStopsAway: firstStops,
      firstStatusMinutes: isFirst ? firstStatus : reference,
    );
    if (isFirst && estimated != null) reference = estimated;
    if (_licenseKey(bus.busLicense) != key) continue;
    if (estimated == null || estimated <= 0) return null;
    return estimated;
  }
  return null;
}
