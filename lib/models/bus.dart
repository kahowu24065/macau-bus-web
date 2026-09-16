import '../utils/parse_utils.dart';

class Bus {
  final String busLicense;
  final double lat;
  final double lng;
  final double speed;
  final int currentStopSeq;

  const Bus({
    required this.busLicense,
    required this.lat,
    required this.lng,
    required this.speed,
    required this.currentStopSeq,
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
    );
  }
}