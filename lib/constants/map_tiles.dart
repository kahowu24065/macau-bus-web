import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Which basemap is on screen, so the credit line matches the tiles.
enum MapTileCredit { openFreeMap, mierune }

/// Basemap for the bus map.
///
/// OpenStreetMap's volunteer servers (`tile.openstreetmap.org`) do not allow
/// native apps. Clients that omit a User-Agent receive the gray
/// "403 Access blocked" tile. The previous [CachedTileProvider] dropped that
/// header, so every request was identified as `Dart/x.x (dart:io)`.
///
/// Tiles now come from OpenFreeMap (no API key, apps and commercial use
/// allowed). If that style cannot be loaded, the map falls back to MIERUNE's
/// free raster endpoint, which has the same kind of terms. CARTO, MapTiler,
/// and Stadia require an API key this repo does not have.
class MapTiles {
  MapTiles._();

  static const String userAgent =
      'MacauBus/mo.mbka.bus (+https://macaubus-kat1.com)';

  static const String packageName = 'mo.mbka.bus';

  /// MapLibre style. OpenFreeMap serves vector tiles, not a volunteer raster.
  static const String openFreeMapStyle =
      'https://tiles.openfreemap.org/styles/bright';

  /// TileJSON. The planet path inside it changes when OpenFreeMap rebuilds.
  static const String openFreeMapPlanet =
      'https://tiles.openfreemap.org/planet';

  static const String openFreeMapHillshade =
      'https://tiles.openfreemap.org/natural_earth/ne2sr/{z}/{x}/{y}.png';

  static const String openFreeMapTerms = 'https://openfreemap.org';

  /// Road-line raster used when OpenFreeMap is unavailable (and on web).
  static const String mieruneUrlTemplate =
      'https://tile.mierune.co.jp/mierune/{z}/{x}/{y}.png';

  /// MIERUNE documents this style through zoom 18.
  static const int mieruneMaxNativeZoom = 18;

  static const String mieruneTerms = 'https://mierune.co.jp';
  static const String openMapTilesTerms = 'https://www.openmaptiles.org/';
  static const String openStreetMapCopyright =
      'https://www.openstreetmap.org/copyright';
}

/// Disk-cached raster tiles that send [MapTiles.userAgent] off the web.
class CachedTileProvider extends TileProvider {
  CachedTileProvider() : super(headers: {'User-Agent': MapTiles.userAgent});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final requestHeaders = Map<String, String>.from(headers);
    // Browsers forbid setting User-Agent from script.
    if (kIsWeb) requestHeaders.remove('User-Agent');
    return CachedNetworkImageProvider(
      getTileUrl(coordinates, options),
      headers: requestHeaders.isEmpty ? null : requestHeaders,
    );
  }
}
