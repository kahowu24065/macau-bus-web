import '../utils/parse_utils.dart';

class BusStop {
  final int seq;
  final String name;
  final String code;
  final double lat;
  final double lng;
  final bool hasAlert;
  final String? alertUrl;

  const BusStop({
    required this.seq,
    required this.name,
    required this.code,
    required this.lat,
    required this.lng,
    this.hasAlert = false,
    this.alertUrl,
  });

  factory BusStop.fromJson(Map<String, dynamic> json) {
    return BusStop(
      seq: json['seq'] is int ? json['seq'] : (int.tryParse(json['seq']?.toString() ?? '') ?? 0),
      name: json['name']?.toString().trim() ?? '未知站點',
      code: json['code']?.toString().trim() ?? '',
      lat: ParseUtils.parseDbl(json['lat']),
      lng: ParseUtils.parseDbl(json['lng']),
      hasAlert: json['hasAlert'] == true,
      alertUrl: json['alertUrl']?.toString(),
    );
  }

  // 🌟 新增：將 BusStop 物件轉換為 JSON 格式以寫入快取
  Map<String, dynamic> toJson() {
    return {
      'seq': seq,
      'name': name,
      'code': code,
      'lat': lat,
      'lng': lng,
      'hasAlert': hasAlert,
      'alertUrl': alertUrl,
    };
  }
}