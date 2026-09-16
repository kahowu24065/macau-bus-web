import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/bus_controller.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../models/bus.dart';
import '../widgets/custom_banner_ad.dart';

class BusRouteScreen extends StatefulWidget {
  const BusRouteScreen({super.key});
  @override 
  State<BusRouteScreen> createState() => _BusRouteScreenState();
}

class _BusRouteScreenState extends State<BusRouteScreen> {
  late BusController _busCtrl;
  late LocationController _locCtrl;

  @override
  void initState() {
    super.initState();
    _busCtrl = context.read<BusController>();
    _locCtrl = context.read<LocationController>();
    
    _busCtrl.addListener(_onBusStateChanged);
    _locCtrl.addListener(_onLocationChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_busCtrl.allRoutesWithDir.isEmpty) {
        _busCtrl.fetchAllRoutes();
      }
      if (_busCtrl.stopsList.isEmpty && !_busCtrl.isLoadingStops && _busCtrl.currentRoute.isNotEmpty) {
        _busCtrl.fetchStops();
      }
    });
  }

  void _onLocationChanged() {
    if (mounted) {
      _busCtrl.checkAlightingAlarm(_locCtrl.userLocation);
    }
  }

  void _onBusStateChanged() {
    if (_busCtrl.pendingAlarmTitle != null && mounted) {
      final title = _busCtrl.pendingAlarmTitle!;
      final body = _busCtrl.pendingAlarmBody ?? '';
      
      _busCtrl.clearPendingAlarm();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.amber, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold))),
            ],
          ),
          content: Text(body, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('收到', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
            )
          ],
        )
      );
    }
  }

  @override
  void dispose() {
    _busCtrl.removeListener(_onBusStateChanged);
    _locCtrl.removeListener(_onLocationChanged);
    super.dispose();
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - math.cos((lat2 - lat1) * p)/2 + 
              math.cos(lat1 * p) * math.cos(lat2 * p) * 
              (1 - math.cos((lon2 - lon1) * p))/2;
    return 12742 * math.asin(math.sqrt(a)) * 1000; 
  }

  void _showAllAlertsDialog(BusController busCtrl) {
    final alertStops = busCtrl.stopsList.where((s) => s.hasAlert && s.alertUrl != null && s.alertUrl!.isNotEmpty).toList(); 
    if (alertStops.isEmpty) { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本路線目前沒有生效中的通告。'))); 
      return; 
    } 
    final isDark = Theme.of(context).brightness == Brightness.dark; 
    showDialog(context: context, builder: (context) { 
      return AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white, 
        title: Row(children: [const Icon(Icons.campaign, color: Colors.redAccent), const SizedBox(width: 8), Text('路線通告總覽', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold))]), 
        content: SizedBox(
          width: double.maxFinite, 
          child: ListView.separated(
            shrinkWrap: true, itemCount: alertStops.length, 
            separatorBuilder: (ctx, i) => Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]), 
            itemBuilder: (ctx, i) { 
              final stop = alertStops[i]; 
              return ListTile(
                contentPadding: EdgeInsets.zero, leading: const Icon(Icons.warning_rounded, color: Colors.yellow, size: 20), 
                title: Text('${stop.seq}. ${stop.name} (${stop.code})', style: TextStyle(color: isDark ? Colors.white : Colors.black)), 
                trailing: const Icon(Icons.open_in_new, color: Colors.grey, size: 16), 
                onTap: () async { 
                  final url = Uri.parse(stop.alertUrl!); 
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication); 
                  }
                }
              ); 
            }
          )
        ), 
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('關閉', style: TextStyle(color: Colors.amber)))]
      ); 
    }); 
  }

  void _showTimetableDialog(BusController busCtrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentRoute = busCtrl.currentRoute;
    List<dynamic> sections = [];
    
    if (busCtrl.timetableDetails != null) {
      if (busCtrl.timetableDetails is List) {
        sections = busCtrl.timetableDetails as List<dynamic>;
      } else if (busCtrl.timetableDetails is Map) {
        final details = busCtrl.timetableDetails as Map<String, dynamic>;
        if (details['sections'] is List) {
          sections = details['sections'];
        } else if (details['weekday'] != null || details['holiday'] != null) {
          if (details['weekday'] != null && (details['weekday'] as List).isNotEmpty) {
            sections.add({'title': '星期一至六（公眾假期除外）', 'items': details['weekday']});
          }
          if (details['holiday'] != null && (details['holiday'] as List).isNotEmpty) {
            sections.add({'title': '星期日及公眾假期', 'items': details['holiday']});
          }
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          contentPadding: EdgeInsets.zero, clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(children: [const Icon(Icons.schedule, color: Colors.amber), const SizedBox(width: 8), Text('$currentRoute 時間表', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18))]),
          content: SizedBox(
            width: double.maxFinite,
            child: sections.isEmpty
                ? const Padding(padding: EdgeInsets.all(30.0), child: Center(child: Text('暫無詳細時間表資料', style: TextStyle(color: Colors.grey))))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12), color: Colors.green[700], child: const Row(children: [Expanded(child: Center(child: Text('服務時間', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)))), Expanded(child: Center(child: Text('班次 (分鐘)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))))])),
                      Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: sections.map((sec) => _buildTimetableSection(sec['title']?.toString() ?? '', sec['items'], isDark)).toList()))),
                    ],
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('關閉', style: TextStyle(color: Colors.amber)))],
        );
      },
    );
  }

  Widget _buildTimetableSection(String title, dynamic dataDynamic, bool isDark) {
    if (dataDynamic == null) return const SizedBox();
    final List<dynamic> data = dataDynamic as List<dynamic>;
    if (data.isEmpty) return const SizedBox();
    final Set<String> seen = {};
    final List<dynamic> uniqueData = [];
    for (var item in data) {
      final key = '${item['time']}_${item['freq']}';
      if (!seen.contains(key)) { seen.add(key); uniqueData.add(item); }
    }
    return Column(
      children: [
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[300], child: Center(child: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)))),
        ...uniqueData.asMap().entries.map((entry) {
          int idx = entry.key; var item = entry.value; bool isLast = idx == uniqueData.length - 1;
          return Container(
            decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E1E) : Colors.white, border: isLast ? null : Border(bottom: BorderSide(color: isDark ? const Color(0xFF333333) : Colors.grey.shade300, width: 1))),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [Expanded(child: Center(child: Text(item['time']?.toString() ?? '', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)))), Expanded(child: Center(child: Text(item['freq']?.toString() ?? '', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14))))]),
          );
        })
      ],
    );
  }

  List<Map<String, String>> _getUpcomingBusesInfo(BusController busCtrl) {
    if (busCtrl.etaData == null && busCtrl.allBusesList.isEmpty) return [];
    
    String rawEtaStatus = busCtrl.etaData?['status']?.toString() ?? '';
    String cleanEta = rawEtaStatus.replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
    
    bool isTerminalEnded = busCtrl.isServiceEnded || 
                           cleanEta.contains('本日服務已結束') || 
                           cleanEta.contains('服務已結束') || 
                           cleanEta.contains('收車') || 
                           cleanEta.contains('尾班車已過');

    bool hasBusesOnRoad = busCtrl.allBusesList.isNotEmpty;

    int? firstBusMins;
    final minMatch = RegExp(r'約\s*(\d+)\s*分鐘').firstMatch(cleanEta) ?? RegExp(r'(\d+)\s*分鐘').firstMatch(cleanEta);
    if (minMatch != null) {
      firstBusMins = int.tryParse(minMatch.group(1)!);
    }

    int? firstBusStops;
    final stopMatch = RegExp(r'尚有\s*(\d+)\s*站').firstMatch(cleanEta) ?? RegExp(r'(\d+)\s*站').firstMatch(cleanEta);
    if (stopMatch != null) {
      firstBusStops = int.tryParse(stopMatch.group(1)!);
    }

    String officialPlate = busCtrl.etaData?['busLicense']?.toString() ?? 
                           busCtrl.etaData?['busPlate']?.toString() ?? 
                           busCtrl.etaData?['plate']?.toString() ?? '';
    
    List<Map<String, String>> upcoming = [];
    
    if (busCtrl.selectedStopSeq != null && hasBusesOnRoad) {
      List<Bus> approachingBuses = busCtrl.allBusesList
          .where((b) => b.currentStopSeq > 0 && b.currentStopSeq <= busCtrl.selectedStopSeq!)
          .toList();
      
      approachingBuses.sort((a, b) => 
          (busCtrl.selectedStopSeq! - a.currentStopSeq).compareTo(busCtrl.selectedStopSeq! - b.currentStopSeq));
      
      approachingBuses.removeWhere((bus) {
        int diff = busCtrl.selectedStopSeq! - bus.currentStopSeq;
        if (diff == 0) {
            bool isGhost = false;
            if (firstBusStops != null && firstBusStops > 1) {
              isGhost = true;
            } else if (firstBusMins != null && firstBusMins > 3) {
              isGhost = true;
            } else if (officialPlate.isNotEmpty && officialPlate != bus.busLicense.trim()) {
              isGhost = true;
            }
            if (isGhost) return true;

            try {
              final currStop = busCtrl.stopsList.firstWhere((s) => s.seq == busCtrl.selectedStopSeq);
              double distToCurr = _calculateDistance(bus.lat, bus.lng, currStop.lat, currStop.lng);
              if (distToCurr > 200) {
                dynamic nextStop;
                for (var s in busCtrl.stopsList) {
                  if (s.seq == busCtrl.selectedStopSeq! + 1) {
                    nextStop = s;
                  }
                }
                if (nextStop != null) {
                  double distToNext = _calculateDistance(bus.lat, bus.lng, nextStop.lat, nextStop.lng);
                  if (distToNext < distToCurr) {
                    return true; 
                  }
                }
              }
            } catch (e) {
              // Ignore
            }
        }
        return false;
      });
      
      int firstBusDiff = -1;
      
      for (var bus in approachingBuses) {
        int diff = busCtrl.selectedStopSeq! - bus.currentStopSeq;
        if (firstBusDiff == -1) firstBusDiff = diff; 
        String status = '';
        if (diff > 0) {
           int estimatedMins = 0;
           if (upcoming.isEmpty && firstBusMins != null) {
             estimatedMins = firstBusMins; 
           } else if (firstBusMins != null && firstBusDiff > 0) {
             estimatedMins = (diff * (firstBusMins / firstBusDiff)).round();
           } else {
             estimatedMins = (diff * 2.5).round();
           }
           status = diff == 1 ? (estimatedMins > 0 ? '下站到達 (約 $estimatedMins 分鐘)' : '下站到達') : (estimatedMins > 0 ? '尚有 $diff 站 (約 $estimatedMins 分鐘)' : '尚有 $diff 站');
        } else {
           status = '即將到站 / 到站中';
        }
        upcoming.add({'status': status, 'plate': bus.busLicense.trim()});
        if (upcoming.length >= 2) break; 
      }
    }
    
    if (upcoming.isEmpty) {
      if (isTerminalEnded) {
        if (hasBusesOnRoad) {
          upcoming.add({'status': '尾班車已過', 'plate': ''});
        } else {
          upcoming.add({'status': '本日服務已結束', 'plate': ''});
        }
      } else if (busCtrl.etaData != null) {
        upcoming.add({'status': cleanEta.isEmpty ? '點擊更新' : cleanEta, 'plate': officialPlate.trim()});
      }
    }
    
    bool isStoppedStatus = upcoming.isNotEmpty && 
        ((upcoming.first['status'] ?? '').contains('服務已結束') || 
         (upcoming.first['status'] ?? '').contains('尾班車') || 
         (upcoming.first['status'] ?? '').contains('尚未開始') || 
         (upcoming.first['status'] ?? '').contains('不設服務') ||
         (upcoming.first['status'] ?? '').contains('點擊更新'));
         
    if (!isStoppedStatus && upcoming.isNotEmpty && upcoming.length < 2) {
      if (isTerminalEnded) {
        upcoming.add({'status': '尾班車已過', 'plate': ''});
      } else {
        upcoming.add({'status': '等候總站發車', 'plate': ''});
      }
    }
    
    return upcoming;
  }

  void _showAlarmBottomSheet(BuildContext context, dynamic stop, BusController busCtrl, LocationController locCtrl, bool isDark) {
    showModalBottomSheet(
      context: context, backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            bool hasBoarding = busCtrl.boardingStopSeq == stop.seq;
            bool hasAlighting = busCtrl.alightingStopSeq == stop.seq;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  const Text('設定智慧提醒', style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('${stop.seq}. ${stop.name} (${stop.code})', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16)),
                  const SizedBox(height: 24),
                  ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.amber.withValues(alpha: 0.2), child: const Icon(Icons.directions_bus, color: Colors.amber)),
                    title: Text(hasBoarding ? '取消上車提醒' : '上車提醒', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                    subtitle: const Text('當巴士距離本站 ≤ 2 站時推播', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: Icon(hasBoarding ? Icons.check_circle : Icons.chevron_right, color: hasBoarding ? Colors.amber : Colors.grey),
                    onTap: () {
                      if (hasBoarding) { busCtrl.setBoardingStop(null); } else { busCtrl.setBoardingStop(stop.seq); }
                      Navigator.pop(context);
                    },
                  ),
                  Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                  ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.blueAccent.withValues(alpha: 0.2), child: const Icon(Icons.location_on, color: Colors.blueAccent)),
                    title: Text(hasAlighting ? '取消下車提醒' : '下車提醒', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                    subtitle: const Text('當手機 GPS 距離此站 < 300 公尺時推播', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: Icon(hasAlighting ? Icons.check_circle : Icons.chevron_right, color: hasAlighting ? Colors.blueAccent : Colors.grey),
                    onTap: () {
                      if (hasAlighting) { 
                        busCtrl.setAlightingStop(null); 
                        Navigator.pop(context);
                      } else { 
                        if (!locCtrl.isFollowingUser) {
                          showDialog(
                            context: context,
                            builder: (dialogCtx) => AlertDialog(
                              backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: Row(children: [const Icon(Icons.location_off, color: Colors.redAccent, size: 24), const SizedBox(width: 10), Expanded(child: Text('需要開啟 GPS', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold)))]),
                              content: Text('下車提醒功能需要讀取您的實時位置。是否允許系統立即開啟 GPS 追蹤？', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15, height: 1.4)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('取消', style: TextStyle(color: Colors.grey, fontSize: 16))),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(dialogCtx); busCtrl.setAlightingStop(stop.seq); 
                                    locCtrl.toggleLocationTracking((loc) { busCtrl.checkAlightingAlarm(loc); });
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已開啟 GPS 定位，下車提醒生效'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
                                    Navigator.pop(context); 
                                  },
                                  child: const Text('開啟', style: TextStyle(color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            )
                          );
                        } else {
                          busCtrl.setAlightingStop(stop.seq);
                          Navigator.pop(context);
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          }
        );
      }
    );
  }

  @override 
  Widget build(BuildContext context) {
    final busCtrl = context.watch<BusController>();
    final locCtrl = context.watch<LocationController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String currentTerminal = busCtrl.currentDirection == 0 ? busCtrl.outboundTerminal : busCtrl.inboundTerminal;

    if (!busCtrl.isLoadingStops && busCtrl.stopsList.isNotEmpty) {
      String firstStop = busCtrl.stopsList.first.name.replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
      String currentClean = currentTerminal.replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
      
      if (busCtrl.currentDirection == 1 || firstStop == currentClean) {
        String lastStop = busCtrl.stopsList.last.name.replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
        if (lastStop != firstStop) {
          currentTerminal = lastStop;
        }
      }
    }

    final isFavorite = busCtrl.favoriteRoutes.contains(busCtrl.currentRoute);
    final hasRoute = busCtrl.currentRoute.isNotEmpty;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: VirtualMapPainter(isDark: isDark),
          ),
        ),

        Column(
          children: [
            // 🌟 瘦身後嘅頂部操作列
            ClipRect( 
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                child: Container(
                  color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.85), 
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), 
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                        children: [
                          if (hasRoute)
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft, 
                                child: InkWell(
                                  onTap: () { busCtrl.toggleDirection(); busCtrl.fetchStops(); context.read<NavigationController>().clearNavigation(); }, 
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [Icon(Icons.swap_calls, color: isDark ? Colors.white : Colors.black), const SizedBox(height: 2), Text('對頭線', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 12))]
                                  )
                                )
                              )
                            )
                          else
                            const Expanded(child: SizedBox.shrink()),
                          
                          Column(
                            children: [
                              Text(hasRoute ? busCtrl.currentRoute : '請先搜尋路線', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5)), 
                              if (hasRoute) Text('往 $currentTerminal', style: const TextStyle(color: Colors.grey, fontSize: 14))
                            ]
                          ), 
                          
                          if (hasRoute)
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight, 
                                child: Row(
                                  mainAxisSize: MainAxisSize.min, 
                                  children: [
                                    InkWell(
                                      onTap: () => _showAllAlertsDialog(busCtrl), 
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min, 
                                        children: [
                                          const Icon(Icons.campaign, color: Colors.redAccent), 
                                          const SizedBox(height: 2), 
                                          Text('通告', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 12))
                                        ]
                                      )
                                    ),
                                    const SizedBox(width: 12),
                                    InkWell(
                                      onTap: () => _showTimetableDialog(busCtrl), 
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min, 
                                        children: [
                                          Icon(Icons.schedule, color: isDark ? Colors.white : Colors.black), 
                                          const SizedBox(height: 2), 
                                          Text('時間表', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 12))
                                        ]
                                      )
                                    ),
                                    const SizedBox(width: 12),
                                    InkWell(
                                      onTap: () => busCtrl.toggleFavorite(busCtrl.currentRoute),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min, 
                                        children: [
                                          Icon(isFavorite ? Icons.star : Icons.star_border, color: isFavorite ? Colors.amber : (isDark ? Colors.white : Colors.black)), 
                                          const SizedBox(height: 2), 
                                          Text('收藏', style: TextStyle(color: isFavorite ? Colors.amber : (isDark ? Colors.white : Colors.black), fontSize: 12))
                                        ]
                                      )
                                    ),
                                  ]
                                )
                              )
                            )
                          else
                            const Expanded(child: SizedBox.shrink()),
                        ]
                      )
                    ]
                  )
                ),
              ),
            ),
            Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
            
            Expanded(
              child: busCtrl.isLoadingStops 
                ? const Center(child: CircularProgressIndicator(color: Colors.amber)) 
                : busCtrl.errorMessage != null 
                  ? Center(child: Text(busCtrl.errorMessage!, style: const TextStyle(color: Colors.redAccent))) 
                  : ListView.builder(
                      itemCount: busCtrl.stopsList.length,
                      itemBuilder: (context, index) {
                        final stop = busCtrl.stopsList[index]; 
                        final isSelected = busCtrl.selectedStopSeq == stop.seq;
                        final hasBoardingAlarm = busCtrl.boardingStopSeq == stop.seq;
                        final hasAlightingAlarm = busCtrl.alightingStopSeq == stop.seq;
                        final isAlarmActive = hasBoardingAlarm || hasAlightingAlarm;
                        
                        return Column(
                          children: [
                            InkWell(
                              onTap: () { busCtrl.selectStop(stop.seq); busCtrl.fetchBusETA(); },
                              child: Container(
                                color: isSelected ? Colors.amber.withValues(alpha: 0.15) : Colors.transparent, 
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    Container(width: 4, height: 36, color: isSelected ? Colors.amber : Colors.transparent), 
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start, 
                                        children: [
                                          Text('${stop.seq}. ${stop.name} (${stop.code})', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)), 
                                          const SizedBox(height: 4), 
                                          const Text('車費: \$6.0', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                          
                                          if (isSelected && busCtrl.isLoadingETA)
                                            const Padding(padding: EdgeInsets.only(top: 8.0), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)))
                                          else if (isSelected && _getUpcomingBusesInfo(busCtrl).isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            ..._getUpcomingBusesInfo(busCtrl).asMap().entries.map((entry) {
                                              int idx = entry.key; var busInfo = entry.value; bool isSecondBus = idx == 1; 
                                              return Padding(
                                                padding: EdgeInsets.only(top: isSecondBus ? 4.0 : 0.0),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Expanded(child: Text(busInfo['status'] ?? '', style: TextStyle(color: isDark ? (isSecondBus ? Colors.amber.shade200 : Colors.amber) : (isSecondBus ? Colors.orange.shade500 : Colors.orange.shade700), fontWeight: isSecondBus ? FontWeight.w600 : FontWeight.bold, fontSize: isSecondBus ? 12 : 14))),
                                                    if (busInfo['plate'] != null && busInfo['plate']!.isNotEmpty) Text('車牌: ${busInfo['plate']}', style: TextStyle(color: isDark ? (isSecondBus ? Colors.grey[500] : Colors.grey[400]) : (isSecondBus ? Colors.grey[600] : Colors.grey[800]), fontSize: isSecondBus ? 10 : 11, fontWeight: FontWeight.w500)),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ]
                                        ]
                                      )
                                    ),
                                    if (stop.hasAlert) ...[
                                      const SizedBox(width: 8),
                                      BlinkingWarningIcon(onTap: () async { if (stop.alertUrl != null && stop.alertUrl!.isNotEmpty) { final Uri url = Uri.parse(stop.alertUrl!); if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication); } }),
                                    ],
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(isAlarmActive ? Icons.notifications_active : Icons.notifications_none, color: hasBoardingAlarm ? Colors.amber : (hasAlightingAlarm ? Colors.blueAccent : Colors.grey)),
                                      padding: EdgeInsets.zero, constraints: const BoxConstraints(), tooltip: '設定提醒',
                                      onPressed: () => _showAlarmBottomSheet(context, stop, busCtrl, locCtrl, isDark),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                          ],
                        );
                      },
                    ),
            ),
            
            const CustomBannerAd(),
          ],
        ),
      ],
    );
  }
}

class BlinkingWarningIcon extends StatefulWidget {
  final VoidCallback onTap;
  const BlinkingWarningIcon({super.key, required this.onTap});
  @override State<BlinkingWarningIcon> createState() => _BlinkingWarningIconState();
}
class _BlinkingWarningIconState extends State<BlinkingWarningIcon> {
  Timer? _timer; bool _isRed = true;
  @override void initState() { super.initState(); _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) { if (mounted) setState(() => _isRed = !_isRed); }); }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) { return InkWell(onTap: widget.onTap, child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(Icons.warning_rounded, color: _isRed ? Colors.redAccent : Colors.yellow, size: 22))); }
}

class VirtualMapPainter extends CustomPainter {
  final bool isDark;
  VirtualMapPainter({required this.isDark});
  @override
  void paint(Canvas canvas, Size size) {
    final bgColor = isDark ? const Color(0xFF101010) : const Color(0xFFF7F7F7);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = bgColor);

    final lineColor1 = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05);
    final lineColor2 = isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03);

    final paintLine1 = Paint()..color = lineColor1..strokeWidth = 6.0..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final paintLine2 = Paint()..color = lineColor2..strokeWidth = 4.0..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    
    final paintNodeInner = Paint()..color = bgColor..style = PaintingStyle.fill;
    final paintNodeOuter1 = Paint()..color = lineColor1..style = PaintingStyle.fill;
    final paintNodeOuter2 = Paint()..color = lineColor2..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    void drawTransitRoute(List<Offset> points, Paint linePaint, Paint nodePaint) {
      if (points.isEmpty) return;
      final path = Path();
      path.moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, linePaint);
      
      for (final pt in points) {
        if (pt.dx <= 0 || pt.dx >= w || pt.dy <= 0 || pt.dy >= h) continue;
        canvas.drawCircle(pt, 6.5, nodePaint); 
        canvas.drawCircle(pt, 3.0, paintNodeInner); 
      }
    }

    drawTransitRoute([Offset(-20, h * 0.15), Offset(w * 0.35, h * 0.15), Offset(w * 0.65, h * 0.35), Offset(w * 0.65, h * 0.75), Offset(w * 0.85, h * 0.88), Offset(w + 20, h * 0.88)], paintLine1, paintNodeOuter1);
    drawTransitRoute([Offset(w * 0.15, -20), Offset(w * 0.15, h * 0.4), Offset(w * 0.4, h * 0.55), Offset(w * 0.8, h * 0.55), Offset(w * 1.05, h * 0.4)], paintLine2, paintNodeOuter2);
    drawTransitRoute([Offset(-20, h * 0.6), Offset(w * 0.25, h * 0.6), Offset(w * 0.45, h * 0.72), Offset(w * 0.45, h + 20)], paintLine2, paintNodeOuter2);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}