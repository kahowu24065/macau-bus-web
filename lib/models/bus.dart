import '../utils/parse_utils.dart';

class Bus {
  final String busLicense;
  final double lat;
  final double lng;
  final double speed;
  final int currentStopSeq;
  final bool atStop;

  /// Server distance-based ETA for this bus. Null when the payload has none.
  final int? etaMinutes;

  const Bus({
    required this.busLicense,
    required this.lat,
    required this.lng,
    required this.speed,
    required this.currentStopSeq,
    this.atStop = true,
    this.etaMinutes,
  });

  factory Bus.fromJson(Map<String, dynamic> json) {
    return Bus(
      busLicense: json['busLicense']?.toString() ?? '未知車牌',
      lat: ParseUtils.parseDbl(json['lat']),
      lng: ParseUtils.parseDbl(json['lng']),
      speed: ParseUtils.parseDbl(json['speed']),
      currentStopSeq: json['currentStopSeq'] is int
          ? json['currentStopSeq']
          : (int.tryParse(json['currentStopSeq']?.toString() ?? '') ?? -1),
      atStop: json['atStop'] != false,
      etaMinutes: _parseEtaMinutes(json['etaMinutes']),
    );
  }

  static int? _parseEtaMinutes(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }
}