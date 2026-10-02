class Itinerary {
  final int duration;
  final List<RouteLeg> legs;

  /// When the plan was requested (epoch ms). Not persisted.
  int? requestedAtMs;

  Itinerary({
    required this.duration,
    required this.legs,
    this.requestedAtMs,
  });

  /// Walking + riding only (sum of legs, excludes any waiting).
  int get movingSeconds => legs.fold(0, (sum, l) => sum + l.duration);

  /// Door-to-door time from the request until arrival, so the initial wait
  /// for the bus and transfer waits are included. Falls back to OTP's
  /// itinerary duration (which already includes transfer waits).
  int get totalSecondsInclWait {
    final end = legs.isEmpty ? null : legs.last.endTime;
    final req = requestedAtMs;
    if (end != null && req != null && end > req) {
      final total = ((end - req) / 1000).round();
      return total > duration ? total : duration;
    }
    return duration > movingSeconds ? duration : movingSeconds;
  }

  /// Leave time (first leg start) and arrival (last leg end), epoch ms.
  int? get departAtMs => legs.isEmpty ? null : legs.first.startTime;
  int? get arriveAtMs => legs.isEmpty ? null : legs.last.endTime;

  /// HH:MM in Macau time (UTC+8), independent of the device time zone.
  static String macauHm(int epochMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true)
        .add(const Duration(hours: 8));
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  factory Itinerary.fromJson(Map<String, dynamic> json) {
    var legsList = json['legs'] as List? ?? [];
    List<RouteLeg> legs = legsList.map((i) => RouteLeg.fromJson(i as Map<String, dynamic>)).toList();

    return Itinerary(
      duration: (json['duration'] ?? 0).toInt(),
      legs: legs,
    );
  }

  // 🌟 讓 Itinerary 可以被轉換為 JSON 儲存入手機
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
  
  // 🌟 核心站點名稱 (支援多國語言)
  final String fromName;
  final String? fromNameEn; 
  final String? fromNamePt;
  
  final double fromLat;
  final double fromLon;
  
  final String toName;
  final String? toNameEn;
  final String? toNamePt;
  
  final double toLat;
  final double toLon;
  
  final String geometry;
  final String routeName;
  final double? distance;

  /// OTP scheduled start/end (epoch ms). Used to check service windows at
  /// boarding time instead of "now" (e.g. N2 boarding at 00:11).
  final int? startTime;
  final int? endTime;

  // 導航附加資訊 (Enriched Fields)
  int? bestDir;
  int? boardingStopSeq;
  int? alightStopSeq;
  String? realtimeEta;

  /// Live cross-check near a route's last trip (set after results show):
  /// 'confirmed' = a bus is still before the boarding stop,
  /// 'maybe_ended' = no bus before the stop and the service window is over.
  String? liveCheck;

  /// True when the planned trip leaves well after the next live bus, so the
  /// UI shows the scheduled departure instead of the next bus's ETA.
  bool showScheduledDeparture = false;

  /// Official DSAT names after match (override OTP phantom names in UI).
  String? displayFromName;
  String? displayFromNameEn;
  String? displayFromNamePt;
  String? displayToName;
  String? displayToNameEn;
  String? displayToNamePt;

  RouteLeg({
    required this.mode,
    required this.duration,
    required this.fromName,
    this.fromNameEn,
    this.fromNamePt,
    required this.fromLat,
    required this.fromLon,
    required this.toName,
    this.toNameEn,
    this.toNamePt,
    required this.toLat,
    required this.toLon,
    required this.geometry,
    required this.routeName,
    this.distance,
    this.startTime,
    this.endTime,
    this.bestDir,
    this.boardingStopSeq,
    this.alightStopSeq,
    this.realtimeEta,
  });

  factory RouteLeg.fromJson(Map<String, dynamic> json) {
    String rName = '';
    final routeObj = json['route'];
    if (routeObj is Map) {
      rName = '${routeObj['shortName'] ?? ''}'.trim();
      if (rName.isEmpty) {
        final gtfsId = '${routeObj['gtfsId'] ?? ''}';
        if (gtfsId.contains(':')) {
          rName = gtfsId.split(':').last.trim();
        } else {
          rName = gtfsId.trim();
        }
      }
    } else if (json['routeName'] != null) {
      rName = json['routeName'].toString();
    }

    String fName = json['from']?['name'] ?? json['fromName'] ?? '';
    
    // 🌟 終極防禦網：涵蓋起點各種可能嘅外語 JSON 欄位命名
    String? fNameEn = json['from']?['nameEn'] ?? json['from']?['name_en'] ?? json['from']?['sta_name_en'] ?? json['fromNameEn'] ?? json['from_name_en'];
    String? fNamePt = json['from']?['namePt'] ?? json['from']?['name_pt'] ?? json['from']?['sta_name_pt'] ?? json['fromNamePt'] ?? json['from_name_pt'];
    
    double fLat = (json['from']?['lat'] ?? json['fromLat'] ?? 0).toDouble();
    double fLon = (json['from']?['lon'] ?? json['fromLon'] ?? 0).toDouble();

    String tName = json['to']?['name'] ?? json['toName'] ?? '';
    
    // 🌟 終極防禦網：涵蓋終點各種可能嘅外語 JSON 欄位命名
    String? tNameEn = json['to']?['nameEn'] ?? json['to']?['name_en'] ?? json['to']?['sta_name_en'] ?? json['toNameEn'] ?? json['to_name_en'];
    String? tNamePt = json['to']?['namePt'] ?? json['to']?['name_pt'] ?? json['to']?['sta_name_pt'] ?? json['toNamePt'] ?? json['to_name_pt'];
    
    double tLat = (json['to']?['lat'] ?? json['toLat'] ?? 0).toDouble();
    double tLon = (json['to']?['lon'] ?? json['toLon'] ?? 0).toDouble();

    String geom = json['legGeometry']?['points'] ?? json['geometry'] ?? '';

    return RouteLeg(
      mode: json['mode'] ?? 'WALK',
      duration: (json['duration'] ?? 0).toInt(),
      fromName: fName,
      fromNameEn: fNameEn,    // 載入起點英文
      fromNamePt: fNamePt,    // 載入起點葡文
      fromLat: fLat,
      fromLon: fLon,
      toName: tName,
      toNameEn: tNameEn,      // 載入終點英文
      toNamePt: tNamePt,      // 載入終點葡文
      toLat: tLat,
      toLon: tLon,
      geometry: geom,
      routeName: rName,
      distance: json['distance']?.toDouble(),
      startTime: (json['startTime'] as num?)?.toInt(),
      endTime: (json['endTime'] as num?)?.toInt(),
      bestDir: json['bestDir']?.toInt(),
      boardingStopSeq: json['boardingStopSeq']?.toInt(),
      alightStopSeq: json['alightStopSeq']?.toInt(),
      realtimeEta: json['realtimeEta'],
    );
  }

  // 🌟 讓 RouteLeg 可以被轉換為 JSON 儲存入手機
  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'duration': duration,
      'fromName': fromName,
      'fromNameEn': fromNameEn,
      'fromNamePt': fromNamePt,
      'fromLat': fromLat,
      'fromLon': fromLon,
      'toName': toName,
      'toNameEn': toNameEn,
      'toNamePt': toNamePt,
      'toLat': toLat,
      'toLon': toLon,
      'geometry': geometry,
      'routeName': routeName,
      'distance': distance,
      'startTime': startTime,
      'endTime': endTime,
      'bestDir': bestDir,
      'boardingStopSeq': boardingStopSeq,
      'alightStopSeq': alightStopSeq,
      'realtimeEta': realtimeEta,
    };
  }

  /// Boarding time as Macau wall-clock (UTC+8), independent of device zone.
  DateTime? get boardingTimeMacau => startTime == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(startTime!, isUtc: true)
          .add(const Duration(hours: 8));

  // 🌟 封裝翻譯函數：起點（優先官方站名）
  String getLocalizedFromName(String lang) {
    if (displayFromName != null && displayFromName!.isNotEmpty) {
      if (lang == 'en' && displayFromNameEn != null && displayFromNameEn!.isNotEmpty) {
        return displayFromNameEn!;
      }
      if (lang == 'pt' && displayFromNamePt != null && displayFromNamePt!.isNotEmpty) {
        return displayFromNamePt!;
      }
      return displayFromName!;
    }
    if (lang == 'en' && fromNameEn != null && fromNameEn!.isNotEmpty) return fromNameEn!;
    if (lang == 'pt' && fromNamePt != null && fromNamePt!.isNotEmpty) return fromNamePt!;
    return fromName;
  }

  // 🌟 封裝翻譯函數：終點（優先官方站名）
  String getLocalizedToName(String lang) {
    if (displayToName != null && displayToName!.isNotEmpty) {
      if (lang == 'en' && displayToNameEn != null && displayToNameEn!.isNotEmpty) {
        return displayToNameEn!;
      }
      if (lang == 'pt' && displayToNamePt != null && displayToNamePt!.isNotEmpty) {
        return displayToNamePt!;
      }
      return displayToName!;
    }
    if (lang == 'en' && toNameEn != null && toNameEn!.isNotEmpty) return toNameEn!;
    if (lang == 'pt' && toNamePt != null && toNamePt!.isNotEmpty) return toNamePt!;
    return toName;
  }
}