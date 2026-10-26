import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:macau_bus_app/utils/map_segment_reference.dart';

BusStop _stop(int seq, double lat, {double lng = 113.54}) {
  return BusStop(
    seq: seq,
    name: '站$seq',
    nameZh: '站$seq',
    nameZhHans: '站$seq',
    namePt: 'Paragem $seq',
    nameEn: 'Stop $seq',
    code: 'M$seq',
    lat: lat,
    lng: lng,
  );
}

Bus _bus({
  required double lat,
  required double speed,
  required int seq,
  double lng = 113.54,
  bool atStop = false,
  String plate = 'MB-1',
  int? etaMinutes,
}) {
  return Bus(
    busLicense: plate,
    lat: lat,
    lng: lng,
    speed: speed,
    currentStopSeq: seq,
    atStop: atStop,
    etaMinutes: etaMinutes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const distance = Distance();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenDataConfig.instance.debugApply(configRealtime: true, etaRealtime: true);
  });

  tearDown(() {
    OpenDataConfig.instance.debugReset();
  });

  BusController route() {
    final bus = BusController();
    bus.stopsList = [
      _stop(1, 22.19),
      _stop(2, 22.20),
      _stop(3, 22.21),
    ];
    return bus;
  }

  double apart(LatLng a, LatLng b) => distance.as(LengthUnit.Meter, a, b);

  /// Metres added by the smooth cruise-then-taper envelope.
  double predictedExtra(double speedKmh, double ageSeconds) {
    return speedEnvelopeMeters(
      speedKmh: speedKmh,
      ageSeconds: ageSeconds,
      cruiseFactor: BusController.mapCruiseFactor,
      cruiseSeconds: BusController.mapCruiseSeconds,
      taperSeconds: BusController.mapTaperSeconds,
      maxMeters: BusController.mapPredictMaxMeters,
      softCapMeters: BusController.mapSpeedSoftCapMeters,
    );
  }

  void expectMoved(double actual, double expected) {
    final slack = math.max(1.5, expected * 0.12);
    expect(
      actual,
      inInclusiveRange(expected - slack, expected + slack),
      reason: 'moved ${actual.toStringAsFixed(1)}m, expected about ${expected.toStringAsFixed(1)}m',
    );
  }

  test('fresh GPS is placed on the route, and a stopped bus stays there', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    const halfway = LatLng(22.195, 113.54);
    bus.allBusesList = [_bus(lat: halfway.latitude, speed: 0, seq: 1)];

    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(placed, halfway), lessThan(25));
    expect(apart(placed, const LatLng(22.19, 113.54)), greaterThan(400));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);

    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(held, placed), lessThan(1));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('speed at or below 5 km/h is stopped, including the displayed speed', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 5, seq: 1)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(1));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('speed just above 5 km/h cruises, then eases to a hold short of full speed', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 6, seq: 1)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 6);

    bus.advanceBusMotion(t0.add(const Duration(seconds: 2)));
    final early = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(early, atFix), predictedExtra(6, 2));

    bus.advanceBusMotion(t0.add(const Duration(seconds: 8)));
    final coasting = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(coasting, early), greaterThan(0.4));

    final fullTen = 6 / 3.6 * 10;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final atPoll = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(atPoll, atFix), predictedExtra(6, 10));
    expect(apart(atPoll, atFix), greaterThan(fullTen * 0.6));
    expect(apart(atPoll, atFix), lessThan(fullTen * 0.95));

    final holdAt = BusController.mapCruiseSeconds + BusController.mapTaperSeconds;
    bus.advanceBusMotion(t0.add(Duration(milliseconds: (holdAt * 1000).round())));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(Duration(milliseconds: (holdAt * 1000).round() + 4000)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, held), lessThan(1));
  });

  test('a later speed of 0 does not keep sliding at the previous speed', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 2)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(ahead, atFix), predictedExtra(36, 2));
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final later = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(later, ahead), predictedExtra(36, 4) - predictedExtra(36, 2));

    bus.allBusesList = [_bus(lat: 22.196, speed: 0, seq: 1)];
    final stoppedAt = t0.add(const Duration(seconds: 4));
    bus.advanceBusMotion(stoppedAt);
    final atStopFix = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(atStopFix, later), lessThan(5));

    bus.advanceBusMotion(stoppedAt.add(const Duration(seconds: 1)));
    final early = bus.snapBusToStop(bus.allBusesList.single)!;
    // One second must not keep the old 36 km/h (~10m) or already reach the fix.
    expect(apart(early, atStopFix), lessThan(6));
    expect(apart(early, const LatLng(22.196, 113.54)), greaterThan(20));

    bus.advanceBusMotion(stoppedAt.add(const Duration(seconds: 40)));
    final parked = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(parked, const LatLng(22.196, 113.54)), lessThan(30));
    bus.advanceBusMotion(stoppedAt.add(const Duration(seconds: 48)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, parked), lessThan(2));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('moving buses cruise slower than reported speed, then ease to a hold', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 30, seq: 1)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.advanceBusMotion(t0.add(const Duration(seconds: 1)));
    final early = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(early, atFix), predictedExtra(30, 1));

    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final mid = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(mid, atFix), predictedExtra(30, 4));
    expect(apart(mid, early), greaterThan(8));

    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final atPoll = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(atPoll, atFix), predictedExtra(30, 10));
    expect(apart(atPoll, atFix), greaterThan(30 / 3.6 * 10 * 0.6));
    expect(apart(atPoll, atFix), lessThan(30 / 3.6 * 10 * 0.95));

    bus.advanceBusMotion(t0.add(const Duration(seconds: 14)));
    final stillCoasting = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(stillCoasting, atPoll), greaterThan(4));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 30);

    final holdAt = BusController.mapCruiseSeconds + BusController.mapTaperSeconds;
    bus.advanceBusMotion(t0.add(Duration(milliseconds: (holdAt * 1000).round())));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(Duration(milliseconds: (holdAt * 1000).round() + 4000)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, held), lessThan(1));
  });

  test('a same-leg fix ahead glides instead of sprinting onto the GPS', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.192, speed: 30, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 2)));
    final before = bus.snapBusToStop(bus.allBusesList.single)!;

    const nextFix = LatLng(22.196, 113.54);
    final fixAt = t0.add(const Duration(seconds: 2));
    bus.allBusesList = [_bus(lat: nextFix.latitude, speed: 30, seq: 1)];
    bus.advanceBusMotion(fixAt);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(atFix, before), lessThan(5));

    bus.advanceBusMotion(fixAt.add(const Duration(seconds: 1)));
    final early = bus.snapBusToStop(bus.allBusesList.single)!;
    final gap = apart(before, nextFix);
    final step = apart(early, atFix);
    // One second must not swallow most of the gap, but cruise still moves forward.
    expect(step, greaterThan(4));
    expect(step, lessThan(gap * 0.25));
    expect(early.latitude, greaterThan(atFix.latitude));

    var previous = early;
    for (var half = 1; half <= 8; half++) {
      bus.advanceBusMotion(fixAt.add(Duration(milliseconds: 1000 + 500 * half)));
      final here = bus.snapBusToStop(bus.allBusesList.single)!;
      expect(here.latitude, greaterThan(previous.latitude - 1e-7));
      expect(apart(here, previous), lessThan(12));
      previous = here;
    }
    expect(previous.latitude, greaterThan(early.latitude));
  });

  test('a new stop sequence keeps the GPS position instead of snapping to the stop', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.199, speed: 18, seq: 1)];
    bus.advanceBusMotion(t0);
    final before = bus.snapBusToStop(bus.allBusesList.single)!;

    const gps = LatLng(22.205, 113.54);
    final changed = t0.add(const Duration(seconds: 2));
    bus.allBusesList = [_bus(lat: gps.latitude, speed: 18, seq: 2)];
    bus.advanceBusMotion(changed);
    final atChange = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(atChange, before), lessThan(20));
    expect(apart(atChange, const LatLng(22.20, 113.54)), greaterThan(20));

    bus.advanceBusMotion(changed.add(const Duration(seconds: 1)));
    final eased = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(eased, gps), lessThan(25));
    expect(apart(eased, const LatLng(22.20, 113.54)), greaterThan(400));
  });

  test('speed cannot carry the icon past the next stop before that stop is current', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    const stop2 = LatLng(22.20, 113.54);
    bus.allBusesList = [_bus(lat: 22.1995, speed: 80, seq: 1)];
    for (var second = 0; second <= 12; second++) {
      bus.advanceBusMotion(t0.add(Duration(seconds: second)));
    }
    final icon = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(icon, stop2), greaterThan(20));
  });

  test('a stopped terminal leg stays on its GPS fix and does not creep at 20 km/h', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    const halfway = LatLng(22.205, 113.54);
    const terminal = LatLng(22.21, 113.54);
    bus.allBusesList = [
      _bus(lat: halfway.latitude, speed: 0, seq: 3, atStop: true),
    ];
    bus.advanceBusMotion(t0);
    expect(bus.hasVisuallyArrived(bus.allBusesList.single), isFalse);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 8)));
    final icon = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(icon, halfway), lessThan(25));
    expect(apart(icon, terminal), greaterThan(400));
    expect(bus.hasVisuallyArrived(bus.allBusesList.single), isFalse);
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('a moving terminal leg can still reach the stop', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [
      _bus(lat: 22.20982, speed: 50, seq: 3, atStop: true),
    ];
    bus.advanceBusMotion(t0);
    expect(bus.hasVisuallyArrived(bus.allBusesList.single), isFalse);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    expect(bus.hasVisuallyArrived(bus.allBusesList.single), isTrue);
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 50);
  });

  test('a GPS on a long route segment stays on the line instead of a stop vertex', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.gpxRoutePoints = const [
      LatLng(22.19, 113.54),
      LatLng(22.20, 113.54),
    ];
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 0, seq: 1)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(placed, const LatLng(22.195, 113.54)), lessThan(25));
    expect(apart(placed, const LatLng(22.19, 113.54)), greaterThan(400));
    expect(apart(placed, const LatLng(22.20, 113.54)), greaterThan(400));
  });

  test('dead reckoning follows a bent route instead of the stop-to-stop chord', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.stopsList = [
      _stop(1, 22.19),
      _stop(2, 22.20),
    ];
    bus.gpxRoutePoints = const [
      LatLng(22.19, 113.54),
      LatLng(22.195, 113.545),
      LatLng(22.20, 113.54),
    ];
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.19, speed: 30, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final icon = bus.snapBusToStop(bus.allBusesList.single)!;
    // Damped 10s of 30 km/h stays on the first leg of the bend, east of the
    // stop-to-stop chord (which keeps longitude 113.54).
    expect(icon.longitude, greaterThan(113.54012));
    expect(icon.longitude, lessThan(113.545));
    expect(apart(icon, const LatLng(22.19, 113.54)), greaterThan(25));
  });

  test('short samples keep the reported speed instead of hopping', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1)];
    bus.advanceBusMotion(t0);
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 36);
    var previous = bus.snapBusToStop(bus.allBusesList.single)!;
    final origin = previous;
    for (var step = 1; step <= 10; step++) {
      bus.advanceBusMotion(t0.add(Duration(milliseconds: 100 * step)));
      final here = bus.snapBusToStop(bus.allBusesList.single)!;
      final moved = const Distance(roundResult: false).as(LengthUnit.Meter, here, previous);
      final stepMeters = predictedExtra(36, 0.1);
      expect(moved, greaterThan(stepMeters * 0.75));
      expect(moved, lessThan(stepMeters * 1.25));
      previous = here;
    }
    expectMoved(
      const Distance(roundResult: false).as(LengthUnit.Meter, previous, origin),
      predictedExtra(36, 1),
    );
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 36);
    expect(BusController.mapMotionFrame.inMilliseconds, inInclusiveRange(16, 40));
  });

  test('a same-leg correction glides along the bend instead of cutting the corner', () {
    final bus = route();
    addTearDown(bus.dispose);
    const corner = LatLng(22.19072, 113.54);
    const end = LatLng(22.19072, 113.54078);
    bus.stopsList = [
      _stop(1, 22.19),
      _stop(2, end.latitude, lng: end.longitude),
    ];
    bus.gpxRoutePoints = const [
      LatLng(22.19, 113.54),
      corner,
      end,
    ];
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.19, speed: 18, seq: 1)];
    bus.advanceBusMotion(t0);
    final fixAt = t0.add(const Duration(seconds: 2));
    bus.advanceBusMotion(fixAt);
    final before = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [_bus(lat: end.latitude, lng: end.longitude, speed: 18, seq: 1)];
    bus.advanceBusMotion(fixAt);
    LatLng? onSecondLeg;
    for (var step = 1; step <= 40; step++) {
      bus.advanceBusMotion(fixAt.add(Duration(milliseconds: 500 * step)));
      final here = bus.snapBusToStop(bus.allBusesList.single)!;
      // The route goes north, then east. A chord would raise lat and lng together.
      if (here.longitude > 113.54015 && here.latitude > corner.latitude - 0.00008) {
        onSecondLeg = here;
        break;
      }
    }
    expect(onSecondLeg, isNotNull, reason: 'before=$before');
    final chordAtLng = before.latitude +
        (end.latitude - before.latitude) *
            ((onSecondLeg!.longitude - before.longitude) / (end.longitude - before.longitude));
    expect(onSecondLeg.latitude, greaterThan(chordAtLng + 0.00015));
  });

  test('without motion yet, the icon still follows GPS instead of the last stop', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.allBusesList = [_bus(lat: 22.195, speed: 12, seq: 1)];
    final icon = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(icon, const LatLng(22.195, 113.54)), lessThan(25));
    expect(apart(icon, const LatLng(22.19, 113.54)), greaterThan(400));
  });

  test('a fix behind the icon does not reverse and does not freeze', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;

    final backAt = t0.add(const Duration(seconds: 4));
    bus.allBusesList = [_bus(lat: 22.192, speed: 36, seq: 1)];
    bus.advanceBusMotion(backAt);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, ahead), lessThan(5));

    bus.advanceBusMotion(backAt.add(const Duration(seconds: 3)));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(held.latitude, greaterThan(ahead.latitude));
    expect(apart(held, ahead), greaterThan(8));
    expect(held.latitude, greaterThan(22.192));
    final cruise = 36 / 3.6 * BusController.mapCruiseFactor * 3;
    expect(apart(held, ahead), lessThan(cruise * 1.35));
  });

  test('atStop on the current stop does not snap the icon backward', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [_bus(lat: 22.19, speed: 0, seq: 1, atStop: true)];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(held, ahead), lessThan(5));
    expect(apart(held, const LatLng(22.19, 113.54)), greaterThan(20));
    expect(bus.hasVisuallyArrived(bus.allBusesList.single), isFalse);
  });

  test('one stop-sequence retreat does not jump the icon backward', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.201, speed: 0, seq: 2)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [_bus(lat: 22.192, speed: 20, seq: 1)];
    bus.advanceBusMotion(t0);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(8));
    bus.advanceBusMotion(t0.add(const Duration(seconds: 5)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(8));
  });

  test('a second distinct stop retreat places the new trip', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.201, speed: 0, seq: 2)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [_bus(lat: 22.192, speed: 0, seq: 1)];
    bus.advanceBusMotion(t0);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(8));

    bus.allBusesList = [_bus(lat: 22.193, speed: 0, seq: 1)];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 1)));
    final reset = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(reset, const LatLng(22.193, 113.54)), lessThan(25));
    expect(apart(reset, placed), greaterThan(100));
  });

  test('a stop retreat that stays for two polls resets the floor', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.201, speed: 0, seq: 2)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;

    final seen = t0.add(const Duration(seconds: 1));
    bus.allBusesList = [_bus(lat: 22.191, speed: 0, seq: 1)];
    bus.advanceBusMotion(seen);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(8));

    bus.advanceBusMotion(seen.add(BusController.mapTripResetHold - const Duration(seconds: 1)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(8));

    bus.advanceBusMotion(seen.add(BusController.mapTripResetHold));
    final reset = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(reset, const LatLng(22.191, 113.54)), lessThan(25));
    expect(apart(reset, placed), greaterThan(100));
  });

  test('a bus that leaves the list can be placed behind on the way back', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 5)));
    bus.allBusesList = [_bus(lat: 22.191, speed: 0, seq: 1)];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 6)));
    final again = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(again, const LatLng(22.191, 113.54)), lessThan(25));
    expect(apart(again, ahead), greaterThan(100));
  });

  test('a fix ahead of the icon still eases forward after a rejected one', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 30, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 3)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;

    final rejectedAt = t0.add(const Duration(seconds: 3));
    bus.allBusesList = [_bus(lat: 22.194, speed: 30, seq: 1)];
    bus.advanceBusMotion(rejectedAt);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, ahead), lessThan(5));

    const nextFix = LatLng(22.198, 113.54);
    final fixAt = rejectedAt.add(const Duration(seconds: 2));
    final beforeNext = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(beforeNext.latitude, greaterThan(ahead.latitude - 1e-7));
    bus.allBusesList = [_bus(lat: nextFix.latitude, speed: 30, seq: 1)];
    bus.advanceBusMotion(fixAt);
    final atNext = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(atNext, beforeNext), lessThan(8));
    expect(atNext.latitude + 1e-7, greaterThan(ahead.latitude));
    bus.advanceBusMotion(fixAt.add(const Duration(seconds: 6)));
    final later = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(later.latitude, greaterThan(atNext.latitude));
    expect(apart(later, atNext), lessThan(80));
  });

  test('ETA to the next stop slows a fast snapshot', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    const fix = LatLng(22.195, 113.54);
    const from = LatLng(22.19, 113.54);
    const to = LatLng(22.20, 113.54);
    final length = distance.as(LengthUnit.Meter, from, to);
    final gps = distance.as(LengthUnit.Meter, from, fix);
    final gap = length - gps;
    bus.allBusesList = [_bus(lat: fix.latitude, speed: 36, seq: 1, etaMinutes: 8)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final moved = apart(bus.snapBusToStop(bus.allBusesList.single)!, atFix);
    final speedOnly = predictedExtra(36, 10);
    final paced = gap / (8 * 60) * 10;
    final blended = speedOnly * (1 - BusController.mapEtaBlend) + paced * BusController.mapEtaBlend;
    expect(paced, lessThan(speedOnly));
    expectMoved(moved, blended);
    expect(moved, lessThan(speedOnly * 0.85));
  });

  test('a stopped bus still eases forward while ETA has time left', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    const fix = LatLng(22.195, 113.54);
    const from = LatLng(22.19, 113.54);
    const to = LatLng(22.20, 113.54);
    final gap = distance.as(LengthUnit.Meter, from, to) - distance.as(LengthUnit.Meter, from, fix);
    bus.allBusesList = [_bus(lat: fix.latitude, speed: 0, seq: 1, etaMinutes: 2)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final moved = apart(bus.snapBusToStop(bus.allBusesList.single)!, atFix);
    final paced = gap / (2 * 60) * 10 * BusController.mapEtaBlend;
    expectMoved(moved, paced);
    expect(moved, greaterThan(15));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, to), greaterThan(80));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('ETA covering a later stop only spends this leg its share of the time', () {
    final current = etaRemainingOnLeg(
      etaMinutes: 8,
      gpsMeters: 500,
      hops: const [
        MapLegHop(fromSeq: 1, toSeq: 2, meters: 1000),
        MapLegHop(fromSeq: 2, toSeq: 3, meters: 1000),
      ],
    );
    // Half of this hop remains, plus the next hop: 500 / 1500 of 8 minutes.
    expect(current, closeTo(8 * 60 * (500 / 1500), 0.01));

    final learned = etaRemainingOnLeg(
      etaMinutes: 7,
      gpsMeters: 500,
      hops: const [
        MapLegHop(fromSeq: 1, toSeq: 2, meters: 1000, learnedSeconds: 100),
        MapLegHop(fromSeq: 2, toSeq: 3, meters: 1000, learnedSeconds: 300),
      ],
    );
    // Remainder is half of 100s, then 300s. Share 50/350 of 7 minutes.
    expect(learned, closeTo(7 * 60 * (50 / 350), 0.01));
  });

  test('the same ETA to a further stop spends less time on this leg', () {
    double movedToward(int stopSeq) {
      final bus = route();
      addTearDown(bus.dispose);
      bus.selectStop(stopSeq);
      final t0 = DateTime.utc(2026, 10, 8, 8);
      bus.allBusesList = [_bus(lat: 22.195, speed: 0, seq: 1, etaMinutes: 8)];
      bus.advanceBusMotion(t0);
      final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
      bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
      return apart(bus.snapBusToStop(bus.allBusesList.single)!, atFix);
    }

    final nextStop = movedToward(2);
    final furtherStop = movedToward(3);
    expect(furtherStop, greaterThan(nextStop + 8));
  });

  test('atStop places the bus at the stop even when ETA still has minutes', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 0, seq: 1, etaMinutes: 10)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 5)));
    final before = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [
      _bus(lat: 22.20, speed: 0, seq: 2, atStop: true, etaMinutes: 0),
    ];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 5)));
    final parked = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(parked, const LatLng(22.20, 113.54)), lessThan(25));
    expect(apart(parked, before), greaterThan(100));
  });

  test('a fix behind the icon does not reverse even if ETA is short', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1, etaMinutes: 8)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;

    final backAt = t0.add(const Duration(seconds: 4));
    bus.allBusesList = [_bus(lat: 22.192, speed: 36, seq: 1, etaMinutes: 1)];
    bus.advanceBusMotion(backAt);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, ahead), lessThan(5));
    bus.advanceBusMotion(backAt.add(const Duration(seconds: 3)));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(held.latitude, greaterThan(ahead.latitude));
    expect(held.latitude, greaterThan(22.192));
    // A 1-minute ETA must not sprint the icon toward the stop in 3 seconds.
    expect(apart(held, ahead), lessThan(80));
  });

  test('clearing the selected-stop ETA stops the time glide', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 0, seq: 1, etaMinutes: 2)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 8)));
    final mid = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(mid, atFix), greaterThan(15));

    bus.selectStop(3);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 18)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, mid), lessThan(5));
  });

  test('a learned segment duration glides a later bus from the stop', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [
      _bus(lat: 22.19, speed: 0, seq: 1, atStop: true, plate: 'TRAIN'),
    ];
    bus.advanceBusMotion(t0);
    final left = t0.add(const Duration(seconds: 1));
    bus.allBusesList = [_bus(lat: 22.1903, speed: 0, seq: 1, plate: 'TRAIN')];
    bus.advanceBusMotion(left);
    bus.allBusesList = [
      _bus(lat: 22.20, speed: 0, seq: 2, atStop: true, plate: 'TRAIN'),
    ];
    bus.advanceBusMotion(left.add(const Duration(seconds: 100)));

    final t1 = left.add(const Duration(seconds: 110));
    bus.allBusesList = [
      _bus(lat: 22.19, speed: 0, seq: 1, atStop: true, plate: 'RIDER'),
    ];
    bus.advanceBusMotion(t1);
    final go = t1.add(const Duration(seconds: 1));
    bus.allBusesList = [_bus(lat: 22.1903, speed: 0, seq: 1, plate: 'RIDER')];
    bus.advanceBusMotion(go);
    final started = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.advanceBusMotion(go.add(const Duration(seconds: 40)));
    final later = bus.snapBusToStop(bus.allBusesList.single)!;
    const from = LatLng(22.19, 113.54);
    const fix = LatLng(22.1903, 113.54);
    final length = distance.as(LengthUnit.Meter, from, const LatLng(22.20, 113.54));
    final gps = distance.as(LengthUnit.Meter, from, fix);
    final ref = length * (40 / 100);
    final blended = gps * (1 - BusController.mapEtaBlend) + ref * BusController.mapEtaBlend;
    expect(apart(later, started), greaterThan(80));
    expectMoved(apart(later, from), blended);
    expect(apart(later, const LatLng(22.20, 113.54)), greaterThan(200));
  });

  test('cruise speed does not cliff across the old predict window', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.192, speed: 24, seq: 1)];
    bus.advanceBusMotion(t0);
    final origin = bus.snapBusToStop(bus.allBusesList.single)!;
    const precise = Distance(roundResult: false);
    final marks = <int, double>{};
    for (final second in [5, 6, 7, 8, 10, 11]) {
      bus.advanceBusMotion(t0.add(Duration(seconds: second)));
      final here = bus.snapBusToStop(bus.allBusesList.single)!;
      marks[second] = precise.as(LengthUnit.Meter, here, origin);
    }
    final early = marks[6]! - marks[5]!;
    final later = marks[8]! - marks[7]!;
    expect(later, greaterThan(early * 0.9));
    expect(early, greaterThan(later * 0.9));
    final intoTaper = marks[11]! - marks[10]!;
    final cruiseStep = marks[10]! - marks[8]!;
    // The old formula dropped from 0.6 to 0.25 at 6s. The first taper second stays near cruise.
    expect(intoTaper, greaterThan(cruiseStep / 2 * 0.85));
  });

  test('a whole-minute ETA change does not stall or sprint', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 0, seq: 1, etaMinutes: 4)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final mid = bus.snapBusToStop(bus.allBusesList.single)!;
    final firstHop = apart(mid, atFix);
    expect(firstHop, greaterThan(10));

    bus.allBusesList = [_bus(lat: 22.195, speed: 0, seq: 1, etaMinutes: 1)];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, mid), lessThan(5));
    bus.advanceBusMotion(t0.add(const Duration(seconds: 20)));
    final secondHop = apart(bus.snapBusToStop(bus.allBusesList.single)!, mid);
    expect(secondHop, greaterThan(firstHop * 0.85));
    expect(secondHop, lessThan(firstHop * 1.7));
  });

  test('speed envelope eases into the taper instead of stepping', () {
    const speed = 24.0;
    final before = speedEnvelopeMeters(
      speedKmh: speed,
      ageSeconds: BusController.mapCruiseSeconds - 0.4,
      cruiseFactor: BusController.mapCruiseFactor,
      cruiseSeconds: BusController.mapCruiseSeconds,
      taperSeconds: BusController.mapTaperSeconds,
      maxMeters: 1000,
      softCapMeters: 0,
    );
    final at = speedEnvelopeMeters(
      speedKmh: speed,
      ageSeconds: BusController.mapCruiseSeconds,
      cruiseFactor: BusController.mapCruiseFactor,
      cruiseSeconds: BusController.mapCruiseSeconds,
      taperSeconds: BusController.mapTaperSeconds,
      maxMeters: 1000,
      softCapMeters: 0,
    );
    final after = speedEnvelopeMeters(
      speedKmh: speed,
      ageSeconds: BusController.mapCruiseSeconds + 0.4,
      cruiseFactor: BusController.mapCruiseFactor,
      cruiseSeconds: BusController.mapCruiseSeconds,
      taperSeconds: BusController.mapTaperSeconds,
      maxMeters: 1000,
      softCapMeters: 0,
    );
    final into = at - before;
    final out = after - at;
    expect(out, greaterThan(into * 0.9));
    final done = speedEnvelopeMeters(
      speedKmh: speed,
      ageSeconds: BusController.mapCruiseSeconds + BusController.mapTaperSeconds + 5,
      cruiseFactor: BusController.mapCruiseFactor,
      cruiseSeconds: BusController.mapCruiseSeconds,
      taperSeconds: BusController.mapTaperSeconds,
      maxMeters: 1000,
      softCapMeters: 0,
    );
    final held = speedEnvelopeMeters(
      speedKmh: speed,
      ageSeconds: BusController.mapCruiseSeconds + BusController.mapTaperSeconds + 9,
      cruiseFactor: BusController.mapCruiseFactor,
      cruiseSeconds: BusController.mapCruiseSeconds,
      taperSeconds: BusController.mapTaperSeconds,
      maxMeters: 1000,
      softCapMeters: 0,
    );
    expect(held, closeTo(done, 0.01));
    final full = speed / 3.6 * (BusController.mapCruiseSeconds + 4);
    expect(at, lessThan(full));
  });

  test('soft cap approaches the metre limit without passing it', () {
    final capped = speedEnvelopeMeters(
      speedKmh: 80,
      ageSeconds: 30,
      cruiseFactor: 1,
      cruiseSeconds: 30,
      taperSeconds: 1,
      maxMeters: 90,
      softCapMeters: 30,
    );
    expect(capped, lessThan(90));
    expect(capped, greaterThan(80));
    final uncapped = speedEnvelopeMeters(
      speedKmh: 80,
      ageSeconds: 4,
      cruiseFactor: 1,
      cruiseSeconds: 30,
      taperSeconds: 1,
      maxMeters: 1000,
      softCapMeters: 0,
    );
    // 4s at 80 km/h is about 89m, still linear before the soft cap.
    expect(uncapped, closeTo(80 / 3.6 * 4, 0.1));
  });

  test('catch-up and glide do not jump or reverse', () {
    expect(
      catchUpMeters(gapMeters: 80, ageSeconds: 0, minSeconds: 10, averageMps: 3.5),
      0,
    );
    final early = catchUpMeters(gapMeters: 80, ageSeconds: 1, minSeconds: 10, averageMps: 3.5);
    expect(early, lessThan(8));
    final done = catchUpMeters(gapMeters: 80, ageSeconds: 40, minSeconds: 10, averageMps: 3.5);
    expect(done, closeTo(80, 0.01));

    final atFix = glideMeters(
      origin: 100,
      curveAtFix: 180,
      curveNow: 180,
      ageSeconds: 0,
      cap: 500,
    );
    expect(atFix, 100);
    final soon = glideMeters(
      origin: 100,
      curveAtFix: 180,
      curveNow: 188,
      ageSeconds: 1,
      cap: 500,
    );
    expect(soon, greaterThan(100));
    expect(soon, lessThan(130));
    final joined = glideMeters(
      origin: 100,
      curveAtFix: 180,
      curveNow: 180,
      ageSeconds: 40,
      cap: 500,
    );
    expect(joined, closeTo(180, 0.5));

    final behind = glideMeters(
      origin: 200,
      curveAtFix: 140,
      curveNow: 152,
      ageSeconds: 3,
      cap: 500,
    );
    expect(behind, closeTo(212, 0.5));
  });

  test('ETA pace slew limits a whole-minute jump', () {
    final doubled = slewPaceMps(previous: 4, target: 8, slew: 0.35, maxStep: 0.25);
    expect(doubled, closeTo(4 * 1.25, 0.001));
    final small = slewPaceMps(previous: 4, target: 4.4, slew: 0.35, maxStep: 0.25);
    expect(small, closeTo(4 + 0.4 * 0.35, 0.001));
    expect(slewPaceMps(previous: 0, target: 5), 5);
    expect(slewPaceMps(previous: 4, target: 0), 0);
  });
}
