import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:macau_bus_app/constants/feature_flags.dart';
import 'package:macau_bus_app/services/gpx_service.dart';

void main() {
  test('route trajectory and timetable stay hidden', () {
    expect(FeatureFlags.showRouteTrajectory, isFalse);
    expect(FeatureFlags.showTimetable, isFalse);
  });

  test('GPX fetch does not run while the trajectory is hidden', () async {
    final points = await GPXService.fetchFullGpx('3', 0);
    expect(points, isEmpty);

    final slice = await GPXService.fetchAndSliceGpx(
      '3',
      0,
      const LatLng(22.19, 113.54),
      const LatLng(22.20, 113.55),
    );
    expect(slice, isNull);
  });
}
