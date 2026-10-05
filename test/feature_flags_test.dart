import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
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

  test('the map footer does not show the route-shape attribution', () {
    final map = File('lib/views/screens/map_screen.dart').readAsStringSync();
    expect(map, isNot(contains('route_shape_source_note')));
    expect(map, isNot(contains('路線形狀')));
  });

  test('a teleport splits and a straight bridge span stays one line', () {
    final bridge = <LatLng>[];
    var lng = 113.54;
    for (var i = 0; i < 8; i++) {
      lng += 0.0001;
      bridge.add(LatLng(22.19, lng));
    }
    for (var i = 0; i < 3; i++) {
      lng += 0.008;
      bridge.add(LatLng(22.19, lng));
    }
    for (var i = 0; i < 8; i++) {
      lng += 0.0001;
      bridge.add(LatLng(22.19, lng));
    }
    expect(GPXService.splitDiscontinuous(bridge), hasLength(1));

    final teleport = <LatLng>[
      for (var i = 0; i < 6; i++) LatLng(22.2015, 113.5740 + i * 0.0001),
      for (var i = 0; i < 6; i++) LatLng(22.1413, 113.5460 + i * 0.0001),
    ];
    final parts = GPXService.splitDiscontinuous(teleport);
    expect(parts, hasLength(2));
    for (final part in parts) {
      for (var i = 1; i < part.length; i++) {
        final jump = (part[i].latitude - part[i - 1].latitude).abs()
            + (part[i].longitude - part[i - 1].longitude).abs();
        expect(jump, lessThan(0.02));
      }
    }

    final zigzag = [
      const LatLng(22.1560, 113.5560),
      const LatLng(22.1600, 113.5600),
      const LatLng(22.1601, 113.5601),
      const LatLng(22.1561, 113.5561),
    ];
    for (final part in GPXService.splitDiscontinuous(zigzag)) {
      for (var i = 1; i < part.length; i++) {
        final jump = (part[i].latitude - part[i - 1].latitude).abs()
            + (part[i].longitude - part[i - 1].longitude).abs();
        expect(jump, lessThan(0.001));
      }
    }

    final chord = [
      const LatLng(22.2100, 113.5590),
      const LatLng(22.1425, 113.5621),
      const LatLng(22.1427, 113.5582),
      const LatLng(22.1427, 113.5581),
      const LatLng(22.2102, 113.5570),
    ];
    for (final part in GPXService.splitDiscontinuous(chord)) {
      for (var i = 1; i < part.length; i++) {
        final jump = (part[i].latitude - part[i - 1].latitude).abs()
            + (part[i].longitude - part[i - 1].longitude).abs();
        expect(jump, lessThan(0.003));
      }
    }
  });

  test('102X with no shape is requested as route 102', () async {
    final uris = <Uri>[];
    GPXService.debugFetch = (uri) async {
      uris.add(uri);
      if (uri.queryParameters['route'] == '102X') {
        return http.Response('{"success":false,"points":[],"error":"no_shape"}', 404);
      }
      return http.Response(
        '{"success":true,"lines":[[{"lat":22.14,"lng":113.58},{"lat":22.15,"lng":113.57}]]}',
        200,
      );
    };
    final lines = await GPXService.fetchRouteLines('102X', 0);
    expect(lines, hasLength(1));
    expect(lines.single, hasLength(2));
    expect(uris.map((u) => u.queryParameters['route']).toList(), ['102X', '102']);
  });
}
