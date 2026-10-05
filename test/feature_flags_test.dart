import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:macau_bus_app/constants/app_translations.dart';
import 'package:macau_bus_app/constants/feature_flags.dart';
import 'package:macau_bus_app/services/gpx_service.dart';

void main() {
  tearDown(() {
    GPXService.debugFetch = null;
  });

  test('timetable and route trajectory are both shown', () {
    expect(FeatureFlags.showTimetable, isTrue);
    expect(FeatureFlags.showRouteTrajectory, isTrue);
  });

  test('route shape is loaded from the open-data API only', () async {
    final uris = <Uri>[];
    GPXService.debugFetch = (uri) async {
      uris.add(uri);
      return http.Response(
        '{"success":true,"source":"ROUTE_NETWORK","points":[{"lat":22.19,"lng":113.54},{"lat":22.20,"lng":113.55}]}',
        200,
      );
    };

    final points = await GPXService.fetchFullGpx('1A', 0);
    expect(points, [
      const LatLng(22.19, 113.54),
      const LatLng(22.20, 113.55),
    ]);
    expect(uris, hasLength(1));
    expect(uris.single.path, '/api/route-shape');
    expect(uris.single.queryParameters['route'], '1A');
    expect(uris.single.queryParameters['dir'], '0');
    expect(uris.single.toString(), isNot(contains('motransportinfo')));
    expect(uris.single.toString(), isNot(contains('bus-gpx')));

    final slice = await GPXService.fetchAndSliceGpx(
      '1A',
      0,
      const LatLng(22.19, 113.54),
      const LatLng(22.20, 113.55),
    );
    expect(slice, isNotNull);
    expect(slice!.length, greaterThanOrEqualTo(2));
  });

  test('a missing route shape stays empty with no second source', () async {
    var calls = 0;
    GPXService.debugFetch = (uri) async {
      calls++;
      return http.Response('{"success":false,"points":[]}', 404);
    };
    expect(await GPXService.fetchFullGpx('99Z', 1), isEmpty);
    expect(calls, 1);
  });

  test('client sources do not call motransportinfo or bus-gpx', () {
    const files = [
      'lib/services/gpx_service.dart',
      'lib/controllers/navigation_controller.dart',
      'lib/controllers/bus_controller.dart',
      'lib/views/screens/map_screen.dart',
    ];
    for (final path in files) {
      final text = File(path).readAsStringSync();
      expect(text, isNot(contains('motransportinfo.com')), reason: path);
      expect(text, isNot(contains('bus-gpx')), reason: path);
    }
  });

  test('map attribution names the open-data platform and export date', () {
    for (final lang in ['zh', 'zhHans', 'en', 'pt']) {
      final note = AppTranslations.data[lang]!['route_shape_source_note'];
      expect(note, isNotNull, reason: lang);
      expect(note, contains('澳門特別行政區政府數據開放平台'));
      expect(note, contains('2026-09-25'));
    }
  });
}
