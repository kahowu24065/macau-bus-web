import '../constants/app_translations.dart';

/// Local banner for the 3-minute warning. Distinct from the immediate alarm (889)
/// and the ongoing tracking notification (888).
const int boardingWarningNotificationId = 890;

/// Local banner for predicted arrival. Fires when the countdown reaches zero.
const int boardingArrivalNotificationId = 891;

/// How far ahead of [arrivesAt] the "about 3 minutes" banner is armed.
const Duration boardingAlertLead = Duration(minutes: 3);

/// When the reminder is already inside the last 3 minutes, fire the warning
/// almost immediately instead of skipping it.
const Duration boardingAlertSoon = Duration(seconds: 1);

/// One scheduled local notification. The plugin plays the default sound, which
/// is what makes iOS vibrate.
class ScheduledBoardingAlert {
  final int id;
  final String title;
  final String body;
  final DateTime at;

  const ScheduledBoardingAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
  });
}

class BoardingAlertPlan {
  final DateTime? warningAt;
  final int? warningMinutes;
  final DateTime? arrivalAt;

  const BoardingAlertPlan({this.warningAt, this.warningMinutes, this.arrivalAt});

  bool get isEmpty => warningAt == null && arrivalAt == null;
}

/// Unix seconds (or milliseconds) of predicted arrival. Values that are not a
/// real timestamp are ignored so a missing endsAt does not schedule a banner.
DateTime? arrivesAtFromEnds(double? endsAt) {
  if (endsAt == null || !endsAt.isFinite || endsAt <= 1000000000) return null;
  final seconds = endsAt > 10000000000 ? endsAt / 1000.0 : endsAt;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}

/// Warning at arrival minus 3 minutes, or about one second from [now] when
/// that moment has already passed. Arrival is [arrivesAt] itself. Nothing is
/// scheduled once arrival is no longer in the future.
BoardingAlertPlan planBoardingAlerts({
  required DateTime arrivesAt,
  required DateTime now,
}) {
  if (!arrivesAt.isAfter(now)) return const BoardingAlertPlan();
  final leadAt = arrivesAt.subtract(boardingAlertLead);
  if (leadAt.isAfter(now)) {
    return BoardingAlertPlan(
      warningAt: leadAt,
      warningMinutes: boardingAlertLead.inMinutes,
      arrivalAt: arrivesAt,
    );
  }
  final soon = now.add(boardingAlertSoon);
  if (!soon.isBefore(arrivesAt)) {
    return BoardingAlertPlan(arrivalAt: arrivesAt);
  }
  final rounded = (arrivesAt.difference(now).inSeconds / 60).round();
  return BoardingAlertPlan(
    warningAt: soon,
    warningMinutes: rounded < 1 ? 1 : rounded,
    arrivalAt: arrivesAt,
  );
}

String boardingAlertTitle({required String lang, required String route}) {
  final trimmed = route.trim();
  if (trimmed.isNotEmpty) return trimmed;
  return _tr(lang, 'boarding_alarm');
}

String boardingWarningBody(String lang, int minutes) {
  return _tr(lang, 'boarding_alert_warning').replaceAll('@mins', '$minutes');
}

String boardingArrivalBody(String lang, String stopName) {
  final stop = stopName.trim();
  if (stop.isEmpty) return _tr(lang, 'boarding_alert_arrived');
  return _tr(lang, 'boarding_alert_arrived_stop').replaceAll('@stop', stop);
}

/// Banners for one registration. Empty when [endsAt] is missing or already past,
/// so the caller cancels anything previously armed.
List<ScheduledBoardingAlert> buildBoardingAlertNotifications({
  required String lang,
  required String route,
  required String stopName,
  required double? endsAt,
  required DateTime now,
}) {
  final arrivesAt = arrivesAtFromEnds(endsAt);
  if (arrivesAt == null) return const [];
  final plan = planBoardingAlerts(arrivesAt: arrivesAt, now: now);
  if (plan.isEmpty) return const [];
  final title = boardingAlertTitle(lang: lang, route: route);
  final alerts = <ScheduledBoardingAlert>[];
  final warningAt = plan.warningAt;
  final warningMinutes = plan.warningMinutes;
  if (warningAt != null && warningMinutes != null) {
    alerts.add(
      ScheduledBoardingAlert(
        id: boardingWarningNotificationId,
        title: title,
        body: boardingWarningBody(lang, warningMinutes),
        at: warningAt,
      ),
    );
  }
  final arrivalAt = plan.arrivalAt;
  if (arrivalAt != null) {
    alerts.add(
      ScheduledBoardingAlert(
        id: boardingArrivalNotificationId,
        title: title,
        body: boardingArrivalBody(lang, stopName),
        at: arrivalAt,
      ),
    );
  }
  return alerts;
}

String _tr(String lang, String key) {
  return AppTranslations.data[lang]?[key] ?? AppTranslations.data['zh']?[key] ?? key;
}
