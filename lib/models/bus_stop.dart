import '../utils/parse_utils.dart';

class BusStop {
  final int seq;
  final String name; // 預設(繁體)
  final String nameZh;
  final String nameZhHans;
  final String namePt;
  final String nameEn;
  final String code;
  final double lat;
  final double lng;
  final bool hasAlert;
  final String? alertUrl;

  const BusStop({
    required this.seq,
    required this.name,
    required this.nameZh,
    required this.nameZhHans,
    required this.namePt,
    required this.nameEn,
    required this.code,
    required this.lat,
    required this.lng,
    this.hasAlert = false,
    this.alertUrl,
  });

  BusStop copyWith({double? lat, double? lng, bool? hasAlert, String? alertUrl}) {
    return BusStop(
      seq: seq,
      name: name,
      nameZh: nameZh,
      nameZhHans: nameZhHans,
      namePt: namePt,
      nameEn: nameEn,
      code: code,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      hasAlert: hasAlert ?? this.hasAlert,
      alertUrl: alertUrl ?? this.alertUrl,
    );
  }

  factory BusStop.fromJson(Map<String, dynamic> json) {
    final defaultName = json['name']?.toString().trim() ?? '未知站點';
    return BusStop(
      seq: json['seq'] is int ? json['seq'] : (int.tryParse(json['seq']?.toString() ?? '') ?? 0),
      name: defaultName,
      nameZh: json['nameZh']?.toString().trim() ?? defaultName,
      nameZhHans: json['nameZhHans']?.toString().trim() ?? defaultName,
      namePt: json['namePt']?.toString().trim() ?? defaultName,
      nameEn: json['nameEn']?.toString().trim() ?? defaultName,
      code: json['code']?.toString().trim() ?? '',
      lat: ParseUtils.parseDbl(json['lat']),
      lng: ParseUtils.parseDbl(json['lng']),
      hasAlert: json['hasAlert'] == true || json['suspendState']?.toString() == '1',
      alertUrl: json['alertUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'seq': seq,
      'name': name,
      'nameZh': nameZh,
      'nameZhHans': nameZhHans,
      'namePt': namePt,
      'nameEn': nameEn,
      'code': code,
      'lat': lat,
      'lng': lng,
      'hasAlert': hasAlert,
      'alertUrl': alertUrl,
    };
  }

  // 🌟 核心魔法：根據語言代碼自動回傳對應語言嘅站名
  String getLocalizedName(String langCode) {
    switch (langCode) {
      case 'zhHans':
        return nameZhHans;
      case 'pt':
        return namePt;
      case 'en':
        return nameEn;
      case 'zh':
      default:
        return nameZh;
    }
  }
}