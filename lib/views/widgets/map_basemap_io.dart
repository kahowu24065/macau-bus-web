import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../constants/map_tiles.dart';
import 'map_basemap_stub.dart' as raster;

/// OpenFreeMap bright style, drawn by flutter_map. Falls back to MIERUNE.
class MapBasemap extends StatefulWidget {
  const MapBasemap({super.key, this.onCredit});

  final ValueChanged<MapTileCredit>? onCredit;

  @override
  State<MapBasemap> createState() => _MapBasemapState();
}

class _MapBasemapState extends State<MapBasemap> {
  static Future<Style>? _style;

  Style? _ready;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pending = _style ??= _readStyle();
    try {
      final style = await pending;
      if (!mounted) return;
      setState(() => _ready = style);
      widget.onCredit?.call(MapTileCredit.openFreeMap);
    } catch (error) {
      if (identical(_style, pending)) _style = null;
      debugPrint('OpenFreeMap basemap unavailable: $error');
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onCredit?.call(MapTileCredit.mierune);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _ready;
    if (_failed || style == null) {
      if (_failed) return raster.MapBasemap(onCredit: widget.onCredit);
      return const SizedBox.shrink();
    }
    return VectorTileLayer(
      tileProviders: style.providers,
      theme: style.theme,
      sprites: style.sprites,
      layerMode: VectorTileLayerMode.vector,
    );
  }
}

Future<Style> _readStyle() async {
  final headers = {'User-Agent': MapTiles.userAgent};
  final style = await StyleReader(uri: MapTiles.openFreeMapStyle).read();
  final planet = await http.get(
    Uri.parse(MapTiles.openFreeMapPlanet),
    headers: headers,
  );
  if (planet.statusCode != 200) {
    throw StateError('OpenFreeMap planet HTTP ${planet.statusCode}');
  }
  final json = jsonDecode(planet.body);
  if (json is! Map<String, dynamic>) {
    throw StateError('OpenFreeMap planet TileJSON was not an object');
  }
  final tiles = json['tiles'];
  if (tiles is! List || tiles.isEmpty || tiles.first is! String) {
    throw StateError('OpenFreeMap planet TileJSON has no tile template');
  }
  return Style(
    theme: style.theme,
    sprites: style.sprites,
    providers: TileProviders({
      'openmaptiles': NetworkVectorTileProvider(
        urlTemplate: tiles.first as String,
        maximumZoom: (json['maxzoom'] as num?)?.toInt() ?? 14,
        minimumZoom: (json['minzoom'] as num?)?.toInt() ?? 0,
        httpHeaders: headers,
      ),
      'ne2_shaded': NetworkVectorTileProvider(
        type: TileProviderType.raster,
        urlTemplate: MapTiles.openFreeMapHillshade,
        maximumZoom: 6,
        minimumZoom: 0,
        httpHeaders: headers,
      ),
    }),
  );
}
