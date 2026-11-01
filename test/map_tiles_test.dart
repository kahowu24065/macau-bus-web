import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/constants/map_tiles.dart';
import 'package:macau_bus_app/views/widgets/map_tile_attribution.dart';

void main() {
  test('basemap does not call the OSM volunteer tile servers', () {
    expect(MapTiles.openFreeMapStyle, contains('tiles.openfreemap.org'));
    expect(MapTiles.openFreeMapPlanet, contains('tiles.openfreemap.org'));
    expect(MapTiles.mieruneUrlTemplate, contains('tile.mierune.co.jp'));
    for (final url in [
      MapTiles.openFreeMapStyle,
      MapTiles.openFreeMapPlanet,
      MapTiles.openFreeMapHillshade,
      MapTiles.mieruneUrlTemplate,
    ]) {
      expect(url, isNot(contains('tile.openstreetmap.org')));
      expect(url, isNot(contains('openstreetmap.de')));
      expect(url, isNot(contains('openstreetmap.fr')));
    }
    expect(MapTiles.userAgent, contains('mo.mbka.bus'));

    final map = File('lib/views/screens/map_screen.dart').readAsStringSync();
    expect(map, isNot(contains('tile.openstreetmap.org')));
    expect(map, contains('MapBasemap'));
    expect(map, contains('MapTileAttribution'));

    final provider = CachedTileProvider();
    expect(provider.headers['User-Agent'], MapTiles.userAgent);
  });

  testWidgets('OpenFreeMap credit names the host, OpenMapTiles, and OSM', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapTileAttribution(credit: MapTileCredit.openFreeMap),
        ),
      ),
    );
    expect(find.textContaining('OpenFreeMap'), findsOneWidget);
    expect(find.textContaining('OpenMapTiles'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
    expect(find.textContaining('MIERUNE'), findsNothing);
  });

  testWidgets('MIERUNE fallback credit names MIERUNE, OpenMapTiles, and OSM', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MapTileAttribution(credit: MapTileCredit.mierune)),
      ),
    );
    expect(find.textContaining('MIERUNE Inc.'), findsOneWidget);
    expect(find.textContaining('OpenMapTiles'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
  });
}
