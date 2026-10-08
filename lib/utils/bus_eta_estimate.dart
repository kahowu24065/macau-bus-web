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
