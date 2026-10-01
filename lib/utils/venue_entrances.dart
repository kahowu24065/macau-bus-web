import 'package:latlong2/latlong.dart';

/// Large venues whose interior has no walkable path in the street map, so a
/// pin inside them (e.g. Google's 威尼斯人 location) snaps to a service road
/// and every plan ends with a 14-16 min walk around the building. A pin
/// inside such a zone is moved to the nearest public entrance before routing.
/// Zones come from a walk-time grid on the OTP graph (only areas where every
/// nearby stop is > 8 min away); entrances are walk-connected points next to
/// the venue's own bus stops.
class VenueEntrances {
  static const List<_Venue> _venues = [
    _Venue(
      name: '威尼斯人',
      south: 22.1450,
      north: 22.1490,
      west: 113.5593,
      east: 113.5613,
      entrances: [
        LatLng(22.1480, 113.5585), // west side, 新城大馬路/威尼斯人 (T394)
        LatLng(22.1478, 113.5625), // Cotai Strip side, 連貫公路/威尼斯人 (T363)
      ],
    ),
    _Venue(
      name: '倫敦人',
      south: 22.1446,
      north: 22.1454,
      west: 113.5616,
      east: 113.5628,
      entrances: [
        LatLng(22.1460, 113.5630), // 連貫公路/倫敦人 (T380)
      ],
    ),
  ];

  static const Distance _distance = Distance();

  /// Returns the entrance to route to when [p] lies in a venue dead zone,
  /// otherwise [p] unchanged.
  static LatLng snap(LatLng p) {
    for (final v in _venues) {
      if (p.latitude < v.south ||
          p.latitude > v.north ||
          p.longitude < v.west ||
          p.longitude > v.east) {
        continue;
      }
      LatLng best = v.entrances.first;
      double bestD = double.infinity;
      for (final e in v.entrances) {
        final d = _distance.as(LengthUnit.Meter, p, e);
        if (d < bestD) {
          bestD = d;
          best = e;
        }
      }
      return best;
    }
    return p;
  }
}

class _Venue {
  final String name;
  final double south;
  final double north;
  final double west;
  final double east;
  final List<LatLng> entrances;
  const _Venue({
    required this.name,
    required this.south,
    required this.north,
    required this.west,
    required this.east,
    required this.entrances,
  });
}
