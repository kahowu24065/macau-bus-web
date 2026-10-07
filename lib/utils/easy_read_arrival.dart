/// Arrival wording.
///
/// The decision of "next stop" versus "arriving now" stays the same.
/// Easy Read Mode only swaps in a short sentence, for example "5 分鐘後到".
String approachingStatus({
  required bool easyRead,
  required int stopsAway,
  required int estimatedMins,
  required String Function(String key) tr,
}) {
  final String normal;
  if (stopsAway <= 0) {
    normal = tr('arriving_soon');
  } else if (stopsAway == 1) {
    normal = estimatedMins > 0
        ? tr('arriving_next_mins').replaceAll('@mins', '$estimatedMins')
        : tr('arriving_next');
  } else if (estimatedMins > 0) {
    normal = tr('stops_away_mins')
        .replaceAll('@stops', '$stopsAway')
        .replaceAll('@mins', '$estimatedMins');
  } else {
    normal = tr('stops_away').replaceAll('@stops', '$stopsAway');
  }
  return presentArrivalStatus(easyRead: easyRead, status: normal, tr: tr);
}

String presentArrivalStatus({
  required bool easyRead,
  required String status,
  required String Function(String key) tr,
}) {
  if (!easyRead) return status;
  final mins = RegExp(
    r'(\d+)\s*(?:分鐘|分钟|mins|min)',
    caseSensitive: false,
  ).firstMatch(status);
  if (mins != null) {
    return tr('easy_read_eta_mins').replaceAll('@mins', mins.group(1)!);
  }
  if (status == tr('arriving_soon') ||
      status.contains('即將到站') ||
      status.contains('即将到站') ||
      status.toLowerCase().contains('arriving')) {
    return tr('easy_read_arriving_soon');
  }
  if (status == tr('arriving_next') ||
      status.contains('下一站') ||
      status.contains('下站到達') ||
      status.contains('下站到达') ||
      status.toLowerCase().contains('next stop')) {
    return tr('easy_read_arriving_next');
  }
  return status;
}
