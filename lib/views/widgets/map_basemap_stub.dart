import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../constants/map_tiles.dart';

/// Raster fallback. Also the web basemap: the vector renderer uses `dart:io`.
class MapBasemap extends StatefulWidget {
  const MapBasemap({super.key, this.onCredit});

  final ValueChanged<MapTileCredit>? onCredit;

  @override
  State<MapBasemap> createState() => _MapBasemapState();
}

class _MapBasemapState extends State<MapBasemap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCredit?.call(MapTileCredit.mierune);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: MapTiles.mieruneUrlTemplate,
      maxNativeZoom: MapTiles.mieruneMaxNativeZoom,
      userAgentPackageName: MapTiles.packageName,
      tileProvider: CachedTileProvider(),
    );
  }
}
