import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/services/open_data_config.dart';

BusStop _stop(int seq, double lat) {
  return BusStop(
    seq: seq,
    name: '站$seq',
    nameZh: '站$seq',
    nameZhHans: '站$seq',
    namePt: 'Paragem $seq',
    nameEn: 'Stop $seq',
    code: 'M$seq',
    lat: lat,
    lng: 113.54,
  );
}

Bus _bus({
  required double lat,
  required double speed,
  required int seq,
  bool atStop = false,
  String plate = 'MB-1',
}) {
  return Bus(
    busLicense: plate,
    lat: lat,
    lng: 113.54,
    speed: speed,
    currentStopSeq: seq,
    atStop: atStop,
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

  test('speed below 2 km/h is stopped, including the displayed speed', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 1.5, seq: 1)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(1));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
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
    expect(apart(ahead, atFix), greaterThan(15));
    expect(apart(ahead, atFix), lessThan(25));
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, ahead), lessThan(1));

    bus.allBusesList = [_bus(lat: 22.196, speed: 0, seq: 1)];
    final stoppedAt = t0.add(const Duration(seconds: 4));
    bus.advanceBusMotion(stoppedAt);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, ahead), lessThan(5));

    bus.advanceBusMotion(stoppedAt.add(const Duration(seconds: 1)));
    final parked = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(parked, const LatLng(22.196, 113.54)), lessThan(25));
    bus.advanceBusMotion(stoppedAt.add(const Duration(seconds: 5)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, parked), lessThan(1));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('moving buses extrapolate for about two seconds, then hold', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 30, seq: 1)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.advanceBusMotion(t0.add(const Duration(seconds: 1)));
    final early = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(early, atFix), greaterThan(5));
    expect(apart(early, atFix), lessThan(15));

    bus.advanceBusMotion(t0.add(const Duration(seconds: 2)));
    final atWindow = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(atWindow, atFix), greaterThan(12));
    expect(apart(atWindow, early), greaterThan(5));

    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, atWindow), lessThan(1));
    bus.advanceBusMotion(t0.add(const Duration(seconds: 9)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, atWindow), lessThan(1));
    bus.advanceBusMotion(t0.add(const Duration(seconds: 11)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, atWindow), lessThan(1));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 30);
  });

  test('a new fix eases onto the GPS point over a second before using speed', () {
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
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, before), lessThan(5));

    bus.advanceBusMotion(fixAt.add(const Duration(milliseconds: 500)));
    final mid = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(mid, before), greaterThan(40));
    expect(apart(mid, nextFix), greaterThan(40));
    expect(apart(mid, before) + apart(mid, nextFix), closeTo(apart(before, nextFix), 30));

    bus.advanceBusMotion(fixAt.add(const Duration(seconds: 1)));
    final eased = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(eased, nextFix), lessThan(25));

    bus.advanceBusMotion(fixAt.add(const Duration(seconds: 3)));
    final after = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(after, eased), greaterThan(5));
    expect(apart(after, eased), lessThan(15));
    bus.advanceBusMotion(fixAt.add(const Duration(seconds: 5)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, after), lessThan(1));
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
    for (var second = 0; second <= 8; second++) {
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

  test('without motion yet, the icon still follows GPS instead of the last stop', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.allBusesList = [_bus(lat: 22.195, speed: 12, seq: 1)];
    final icon = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(icon, const LatLng(22.195, 113.54)), lessThan(25));
    expect(apart(icon, const LatLng(22.19, 113.54)), greaterThan(400));
  });
}
