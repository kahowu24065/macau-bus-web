class Itinerary {
  final int duration;
  final List<RouteLeg> legs;

  Itinerary({
    required this.duration,
    required this.legs,
  });

  factory Itinerary.fromJson(Map<String, dynamic> json) {
    var legsList = json['legs'] as List? ?? [];
    List<RouteLeg> legs = legsList.map((i) => RouteLeg.fromJson(i as Map<String, dynamic>)).toList();

    return Itinerary(
      duration: (json['duration'] ?? 0).toInt(),
      legs: legs,
    );
  }

  // 🌟 新增：讓 Itinerary 可以被轉換為 JSON 儲存入手機
  Map<String, dynamic> toJson() {
    return {
      'duration': duration,
      'legs': legs.map((leg) => leg.toJson()).toList(),
    };
  }
}

class RouteLeg {
  final String mode;
  final int duration;
  final String fromName;
  final double fromLat;
  final double fromLon;
  final String toName;
  final double toLat;
  final double toLon;
  final String geometry;
  final String routeName;
  final double? distance;

  // 導航附加資訊 (Enriched Fields)
  int? bestDir;
  int? boardingStopSeq;
  int? alightStopSeq;
  String? realtimeEta;

  RouteLeg({
    required this.mode,
    required this.duration,
    required this.fromName,
    required this.fromLat,
    required this.fromLon,
    required this.toName,
    required this.toLat,
    required this.toLon,
    required this.geometry,
    required this.routeName,
    this.distance,
    this.bestDir,
    this.boardingStopSeq,
    this.alightStopSeq,
    this.realtimeEta,
  });

  factory RouteLeg.fromJson(Map<String, dynamic> json) {
    // 兼容從 OTP API 原始結構讀取，或從 SharedPreferences 歷史紀錄讀取
    String rName = '';
    if (json['route'] != null && json['route']['shortName'] != null) {
      rName = json['route']['shortName'].toString();
    } else if (json['routeName'] != null) {
      rName = json['routeName'].toString();
    }

    String fName = json['from']?['name'] ?? json['fromName'] ?? '';
    double fLat = (json['from']?['lat'] ?? json['fromLat'] ?? 0).toDouble();
    double fLon = (json['from']?['lon'] ?? json['fromLon'] ?? 0).toDouble();

    String tName = json['to']?['name'] ?? json['toName'] ?? '';
    double tLat = (json['to']?['lat'] ?? json['toLat'] ?? 0).toDouble();
    double tLon = (json['to']?['lon'] ?? json['toLon'] ?? 0).toDouble();

    String geom = json['legGeometry']?['points'] ?? json['geometry'] ?? '';

    return RouteLeg(
      mode: json['mode'] ?? 'WALK',
      duration: (json['duration'] ?? 0).toInt(),
      fromName: fName,
      fromLat: fLat,
      fromLon: fLon,
      toName: tName,
      toLat: tLat,
      toLon: tLon,
      geometry: geom,
      routeName: rName,
      distance: json['distance']?.toDouble(),
      bestDir: json['bestDir']?.toInt(),
      boardingStopSeq: json['boardingStopSeq']?.toInt(),
      alightStopSeq: json['alightStopSeq']?.toInt(),
      realtimeEta: json['realtimeEta'],
    );
  }

  // 🌟 新增：讓 RouteLeg 可以被轉換為 JSON 儲存入手機
  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'duration': duration,
      'fromName': fromName,
      'fromLat': fromLat,
      'fromLon': fromLon,
      'toName': toName,
      'toLat': toLat,
      'toLon': toLon,
      'geometry': geometry,
      'routeName': routeName,
      'distance': distance,
      'bestDir': bestDir,
      'boardingStopSeq': boardingStopSeq,
      'alightStopSeq': alightStopSeq,
      'realtimeEta': realtimeEta,
    };
  }
}