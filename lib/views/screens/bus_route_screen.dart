import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/fit_marquee_text.dart'; // 🌟 走馬燈（只在超出寬度時滾動）

import '../../controllers/bus_controller.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../services/gps_service.dart'; 
import '../../services/bus_api_service.dart'; 
import '../../models/bus.dart';
import '../../controllers/background_controller.dart';
import '../widgets/glowing_badge.dart';
import '../widgets/blinking_warning_icon.dart';
import '../../controllers/language_controller.dart';
import '../widgets/route_liquid_glass_nav.dart';
import '../../utils/service_label_i18n.dart';
import '../../constants/app_translations.dart';

class BusRouteScreen extends StatefulWidget {
  const BusRouteScreen({super.key});
  @override 
  State<BusRouteScreen> createState() => _BusRouteScreenState();
}
String _lastFetchedLang = '';
class _BusRouteScreenState extends State<BusRouteScreen> {
  late BusController _busCtrl;
  late LocationController _locCtrl;
  final ScrollController _listScrollController = ScrollController();
  final GlobalKey _selectedStopKey = GlobalKey();
  
  List<dynamic> _routeAlerts = [];
  String _lastFetchedRoute = '';

  final Map<String, dynamic> _stopWarningCache = {};

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
      
      if (_busCtrl.currentRoute.isNotEmpty) {
        _lastFetchedRoute = _busCtrl.currentRoute;
        _fetchRouteAlerts(_busCtrl.currentRoute);
      }
    });
  }

  Future<void> _fetchRouteAlerts(String route) async {
    if (route.isEmpty) return;
    try {
      final alerts = await BusApiService.fetchRouteAlerts(route);
      if (!mounted) return;
      setState(() {
        _routeAlerts = alerts;
      });
    } catch (e) {
      debugPrint('讀取路線通告失敗: $e');
    }
  }

  bool _hasAnyStopWarning(dynamic stop) {
    return stop.hasAlert == true;
  }

  Future<void> _openStopWarning(dynamic stop) async {
    final alertUrl = stop.alertUrl?.toString() ?? '';
    final stopCode = stop.code?.toString().trim().toUpperCase() ?? '';

    if (alertUrl.isNotEmpty && alertUrl != 'internal_api_call' && !alertUrl.startsWith('internal')) {
      final url = Uri.tryParse(alertUrl);
      if (url != null && await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langCtrl = context.read<LanguageController>();
    final localizedStopName = stop.getLocalizedName(langCtrl.currentLanguage);
    final cacheKey = '${_busCtrl.currentRoute}_${stopCode}_${langCtrl.currentLanguage}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
    );

    Map<String, dynamic>? info;

    try {
      if (_stopWarningCache.containsKey(cacheKey)) {
        info = _stopWarningCache[cacheKey]; 
      } else {
        info = await BusApiService.fetchStopDetour(
          route: _busCtrl.currentRoute,
          stationCode: stopCode,
          lang: langCtrl.currentLanguage,
        );
        if (info != null) {
          _stopWarningCache[cacheKey] = info;
        }
      }
    } catch (e) {
      debugPrint('獲取車站官方通告失敗: $e');
    }

    if (mounted) {
      Navigator.of(context).pop(); 
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(info != null ? Icons.warning_amber_rounded : Icons.warning_rounded, color: info != null ? Colors.redAccent : Colors.amber, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                info != null ? (info['title'] ?? langCtrl.tr('route_notice')) : langCtrl.tr('service_warning'),
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: info != null 
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info['time'] ?? '',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (info['suspendStops'] != null && (info['suspendStops'] as List).isNotEmpty) ...[
                    Text(langCtrl.tr('suspended_stops'), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                    ...((info['suspendStops'] as List).map((s) => Text('• $s', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)))),
                    const SizedBox(height: 8),
                  ],
                  if (info['alternativeStops'] != null && (info['alternativeStops'] as List).isNotEmpty) ...[
                    Text(langCtrl.tr('temp_alt_stops'), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                    ...((info['alternativeStops'] as List).map((s) => Text('• $s', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)))),
                    const SizedBox(height: 8),
                  ],
                  if (info['provider'] != null && info['provider'].toString().isNotEmpty) ...[
                    const Divider(color: Colors.grey),
                    Text(info['provider'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ],
              )
            : Text(
                langCtrl.tr('stop_warning_body').replaceAll('@stop', localizedStopName), 
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(langCtrl.tr('btn_close'), style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _onLocationChanged() {
    if (mounted) {
      _busCtrl.checkAlightingAlarm(_locCtrl.userLocation);
    }
  }

  void _onBusStateChanged() {
    if (_busCtrl.currentRoute.isNotEmpty && _busCtrl.currentRoute != _lastFetchedRoute) {
      _lastFetchedRoute = _busCtrl.currentRoute;
      _fetchRouteAlerts(_busCtrl.currentRoute);
    }

    if (_busCtrl.pendingAlarmTitle != null && mounted) {
      final title = _busCtrl.pendingAlarmTitle!;
      final body = _busCtrl.pendingAlarmBody ?? '';
      
      _busCtrl.clearPendingAlarm();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final langCtrl = context.read<LanguageController>();
      
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
              child: Text(langCtrl.tr('received'), style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
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
    _listScrollController.dispose();
    super.dispose();
  }

  // Jump near the selected row first (builder only mounts visible
  // children), then ensureVisible so the live-tracking card is on screen.
  void _ensureSelectedStopVisible() {
    if (!mounted || !_listScrollController.hasClients) return;
    final seq = _busCtrl.selectedStopSeq;
    if (seq == null) return;
    final index = _busCtrl.stopsList.indexWhere((s) => s.seq == seq);
    if (index < 0) return;

    const compactRowHeight = 56.0;
    final maxExtent = _listScrollController.position.maxScrollExtent;
    final estimate = (index * compactRowHeight).clamp(0.0, maxExtent);
    _listScrollController.jumpTo(estimate);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _selectedStopKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.08,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToNearestStop() {
    if (_locCtrl.userLocation == null) {
      return;
    }
    
    final nearest = _busCtrl.findNearestStop(_locCtrl.userLocation!);
    if (nearest != null && nearest['seq'] != null) {
      int targetSeq = nearest['seq'];
      _busCtrl.selectStop(targetSeq);
      _busCtrl.fetchBusETA();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureSelectedStopVisible();
      });
    } 
  }
  
  void _showFareDialog(BuildContext context, bool isDark) {
    final langCtrl = context.read<LanguageController>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.monetization_on, color: Colors.amber, size: 28),
            const SizedBox(width: 8),
            Text(langCtrl.tr('fare_table'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFareRow(langCtrl.tr('general_fare'), '\$6.0', isDark),
            const SizedBox(height: 12),
            _buildFareRow(langCtrl.tr('macau_pass'), '\$3.0', isDark),
            const SizedBox(height: 12),
            _buildFareRow(langCtrl.tr('student_card'), '\$1.5', isDark),
            const SizedBox(height: 12),
            _buildFareRow(langCtrl.tr('elderly_disabled'), '\$0.0', isDark),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(langCtrl.tr('btn_close'), style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildFareRow(String type, String price, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(type, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15)),
        Text(price, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _showTimetableDialog(BusController busCtrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langCtrl = context.read<LanguageController>();
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
            sections.add({'title': langCtrl.tr('mon_to_sat'), 'items': details['weekday']});
          }
          if (details['holiday'] != null && (details['holiday'] as List).isNotEmpty) {
            sections.add({'title': langCtrl.tr('sun_and_holidays'), 'items': details['holiday']});
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
          title: Row(children: [const Icon(Icons.schedule, color: Colors.amber), const SizedBox(width: 8), Text('$currentRoute ${langCtrl.tr('timetable')}', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18))]),
          content: SizedBox(
            width: double.maxFinite,
            child: sections.isEmpty
                ? Padding(padding: const EdgeInsets.all(30.0), child: Center(child: Text(langCtrl.tr('no_timetable'), style: const TextStyle(color: Colors.grey))))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12), color: Colors.green[700], child: Row(children: [Expanded(child: Center(child: Text(langCtrl.tr('service_hours'), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)))), Expanded(child: Center(child: Text(langCtrl.tr('frequency_mins'), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))))])),
                      Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: sections.map((sec) => _buildTimetableSection(ServiceLabelI18n.translate(sec['title']?.toString() ?? '', langCtrl.currentLanguage), sec['items'], isDark, langCtrl.currentLanguage)).toList()))),
                    ],
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(langCtrl.tr('btn_close'), style: const TextStyle(color: Colors.amber)))],
        );
      },
    );
  }

  Widget _buildTimetableSection(String title, dynamic dataDynamic, bool isDark, String lang) {
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
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[300], child: Text(title, textAlign: TextAlign.center, softWrap: true, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.bold, height: 1.35))),
        ...uniqueData.asMap().entries.map((entry) {
          int idx = entry.key; var item = entry.value; bool isLast = idx == uniqueData.length - 1;
          return Container(
            decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E1E) : Colors.white, border: isLast ? null : Border(bottom: BorderSide(color: isDark ? const Color(0xFF333333) : Colors.grey.shade300, width: 1))),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [Expanded(child: Center(child: Text(ServiceLabelI18n.translate(item['time']?.toString() ?? '', lang), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)))), Expanded(child: Center(child: Text(ServiceLabelI18n.translate(item['freq']?.toString() ?? '', lang), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14))))]),
          );
        })
      ],
    );
  }

  List<Map<String, String>> _getUpcomingBusesInfo(BusController busCtrl, LanguageController langCtrl) {
    if (busCtrl.etaData == null && busCtrl.allBusesList.isEmpty) return [];
    
    String rawEtaStatus = busCtrl.etaData?['status']?.toString() ?? '';
    String cleanEta = rawEtaStatus.replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
    
    bool hasBusesOnRoad = busCtrl.allBusesList.isNotEmpty;

    bool isTerminalNoService = busCtrl.isNoServiceToday || cleanEta.contains('不設服務');
    
    bool endedFromEta = cleanEta.contains('本日服務已結束') ||
        cleanEta.contains('服務已結束') ||
        cleanEta.contains('收車') ||
        cleanEta.contains('尾班車已過') ||
        cleanEta.toLowerCase().contains('service ended') ||
        cleanEta.toLowerCase().contains('terminad');
    bool notStartedFromEta = cleanEta.contains('尚未開始') ||
        cleanEta.contains('未開始') ||
        cleanEta.toLowerCase().contains('not started') ||
        cleanEta.toLowerCase().contains('não iniciado') ||
        cleanEta.toLowerCase().contains('nao iniciado');

    bool isServiceStopped = busCtrl.isServiceNotStarted ||
        busCtrl.isServiceEnded ||
        notStartedFromEta ||
        endedFromEta;

    int? firstBusMins;
    final minMatch = RegExp(r'(?:約\s*|~\s*)?(\d+)\s*(?:分鐘|mins|min)', caseSensitive: false).firstMatch(cleanEta);
    if (minMatch != null) {
      firstBusMins = int.tryParse(minMatch.group(1)!);
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
           
           if (diff == 1) {
             status = estimatedMins > 0 
                 ? langCtrl.tr('arriving_next_mins').replaceAll('@mins', estimatedMins.toString()) 
                 : langCtrl.tr('arriving_next');
           } else {
             status = estimatedMins > 0 
                 ? langCtrl.tr('stops_away_mins').replaceAll('@stops', diff.toString()).replaceAll('@mins', estimatedMins.toString()) 
                 : langCtrl.tr('stops_away').replaceAll('@stops', diff.toString());
           }
        } else {
           status = langCtrl.tr('arriving_soon');
        }
        upcoming.add({'status': status, 'plate': bus.busLicense.trim()});
        if (upcoming.length >= 2) break; 
      }
    }
    
    if (upcoming.isEmpty) {
      if (isTerminalNoService) {
        upcoming.add({'status': langCtrl.tr('no_service_today'), 'plate': ''});
      } else if (hasBusesOnRoad && isServiceStopped) {
        upcoming.add({'status': langCtrl.tr('last_bus_departed'), 'plate': ''});
      } else if (busCtrl.isServiceEnded || endedFromEta) {
        upcoming.add({'status': langCtrl.tr('service_ended'), 'plate': ''});
      } else if (busCtrl.isServiceNotStarted || notStartedFromEta) {
        upcoming.add({'status': langCtrl.tr('service_not_started'), 'plate': ''});
      } else if (isServiceStopped) {
        // No timetable match: late night is still yesterday's last bus.
        upcoming.add({
          'status': DateTime.now().hour < 4
              ? langCtrl.tr('service_ended')
              : langCtrl.tr('service_not_started'),
          'plate': '',
        });
      } else if (busCtrl.etaData != null) {
        upcoming.add({'status': cleanEta.isEmpty ? langCtrl.tr('click_to_update') : AppTranslations.localizeEtaStatus(cleanEta, langCtrl.tr), 'plate': officialPlate.trim()});
      }
    }
    
    bool isStoppedStatus = upcoming.isNotEmpty && 
        ((upcoming.first['status'] ?? '').contains(langCtrl.tr('service_ended')) || 
         (upcoming.first['status'] ?? '').contains(langCtrl.tr('service_not_started')) || 
         (upcoming.first['status'] ?? '').contains(langCtrl.tr('no_service_today')) || 
         (upcoming.first['status'] ?? '').contains(langCtrl.tr('last_bus_departed')) || 
         (upcoming.first['status'] ?? '').contains(langCtrl.tr('waiting_at_terminal')) || 
         (upcoming.first['status'] ?? '').contains('等候總站發車') || 
         (upcoming.first['status'] ?? '').contains(langCtrl.tr('click_to_update')));
         
    if (!isStoppedStatus && upcoming.isNotEmpty && upcoming.length < 2) {
      if (isServiceStopped) {
        upcoming.add({'status': langCtrl.tr('last_bus_departed'), 'plate': ''});
      } else {
        upcoming.add({'status': langCtrl.tr('waiting_at_terminal'), 'plate': ''});
      }
    }
    
    return upcoming;
  }

  void _showAlarmBottomSheet(BuildContext context, dynamic stop, BusController busCtrl, LocationController locCtrl, bool isDark) {
    final langCtrl = context.read<LanguageController>();
    final localizedName = stop.getLocalizedName(langCtrl.currentLanguage);
    
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
                  Text(langCtrl.tr('set_alarm'), style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('${stop.seq}. $localizedName (${stop.code})', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16)),
                  const SizedBox(height: 24),
                  ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.amber.withValues(alpha: 0.2), child: const Icon(Icons.directions_bus, color: Colors.amber)),
                    title: Text(hasBoarding ? langCtrl.tr('cancel_boarding_alarm') : langCtrl.tr('boarding_alarm'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                    subtitle: Text(langCtrl.tr('boarding_alarm_desc'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: Icon(hasBoarding ? Icons.check_circle : Icons.chevron_right, color: hasBoarding ? Colors.amber : Colors.grey),
                    onTap: () {
                      if (hasBoarding) { busCtrl.setBoardingStop(null); } else { busCtrl.setBoardingStop(stop.seq); }
                      Navigator.pop(context);
                    },
                  ),
                  Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                  ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.blueAccent.withValues(alpha: 0.2), child: const Icon(Icons.location_on, color: Colors.blueAccent)),
                    title: Text(hasAlighting ? langCtrl.tr('cancel_alighting_alarm') : langCtrl.tr('alighting_alarm'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                    subtitle: Text(langCtrl.tr('alighting_alarm_desc'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
                              title: Row(children: [const Icon(Icons.location_off, color: Colors.redAccent, size: 24), const SizedBox(width: 10), Expanded(child: Text(langCtrl.tr('need_gps'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold)))]),
                              content: Text(langCtrl.tr('need_gps_desc'), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15, height: 1.4)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text(langCtrl.tr('cancel'), style: const TextStyle(color: Colors.grey, fontSize: 16))),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(dialogCtx); busCtrl.setAlightingStop(stop.seq); 
                                    locCtrl.toggleLocationTracking((loc) { busCtrl.checkAlightingAlarm(loc); });
                                    ScaffoldMessenger.of(context).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: context, content: Text(langCtrl.tr('gps_opened')), backgroundColor: Colors.green));
                                    Navigator.pop(context); 
                                  },
                                  child: Text(langCtrl.tr('open'), style: const TextStyle(color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _buildHeaderIcon(IconData icon, String label, bool isDark, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(icon, color: color ?? (isDark ? Colors.white : Colors.black), size: 24),
            const SizedBox(height: 4), 
            Text(
              label, 
              textAlign: TextAlign.center,
              style: TextStyle(color: color ?? (isDark ? Colors.white70 : Colors.black87), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override 
  Widget build(BuildContext context) {
    final busCtrl = context.watch<BusController>();
    final locCtrl = context.watch<LocationController>();
    final bgCtrl = context.watch<BackgroundController>();
    final langCtrl = context.watch<LanguageController>();
    final isSimpleMode = busCtrl.isSimpleMode;
    
    busCtrl.currentLang = langCtrl.currentLanguage;

    // 🌟 加上呢行：將翻譯機借俾 BusController 用！
    busCtrl.tr = langCtrl.tr;
    // 🌟 加入呢段：當偵測到語言切換，即刻清空快取並重新 Fetch 路線通告
    if (busCtrl.currentLang != _lastFetchedLang) {
      _lastFetchedLang = busCtrl.currentLang;
      // 確保畫面渲染完畢後先執行 API 請求
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _stopWarningCache.clear(); // 清空舊語言的車站通告快取
        _fetchRouteAlerts(busCtrl.currentRoute); // 重新獲取對應語言的路線通告
      });
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    String currentTerminal = busCtrl.currentDirection == 0 ? busCtrl.outboundTerminal : busCtrl.inboundTerminal;
    if (!busCtrl.isLoadingStops && busCtrl.stopsList.isNotEmpty) {
      currentTerminal = busCtrl.stopsList.last.getLocalizedName(langCtrl.currentLanguage)
                               .replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
    }

    final isFavorite = busCtrl.favoriteRoutes.contains(busCtrl.currentRoute);
    final hasRoute = busCtrl.currentRoute.isNotEmpty;

    final alertStops = busCtrl.stopsList.where(_hasAnyStopWarning).toList();

    List<Widget> combinedAlertWidgets = [];

    for (var alert in _routeAlerts) {
      combinedAlertWidgets.add(
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: InkWell(
            onTap: () async {
              if (alert['link'] != null && alert['link'].isNotEmpty) {
                final url = Uri.parse(alert['link']);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BlinkingAlertIcon(),
                const SizedBox(width: 4),
                Text(
                  alert['title'] ?? langCtrl.tr('route_notice'),
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        )
      );
    }

    if (alertStops.isNotEmpty) {
      List<Widget> stationWidgets = [];
      
      for (int i = 0; i < alertStops.length; i++) {
        final stop = alertStops[i];
        
        stationWidgets.add(
          InkWell(
            onTap: () => _openStopWarning(stop), 
            child: Text(
              '${stop.seq}. ${stop.getLocalizedName(langCtrl.currentLanguage)}', 
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none, 
              ),
            ),
          ),
        );

        if (i < alertStops.length - 1) {
          stationWidgets.add(
            Text(
              '、',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none,
              ),
            ),
          );
        }
      }

      combinedAlertWidgets.add(
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const BlinkingAlertIcon(),
              const SizedBox(width: 4),
              Text(
                langCtrl.tr('station_info'),
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
              ...stationWidgets,
            ],
          ),
        )
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          if (bgCtrl.backgroundImagePath == null)
          Positioned.fill(
            child: CustomPaint(
              painter: VirtualMapPainter(isDark: isDark),
            ),
          ),

          Column(
            children: [
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                  child: Container(
                    color: isDark ? Colors.black.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.7),
                    padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasRoute ? busCtrl.currentRoute : '--', 
                              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 64, fontWeight: FontWeight.bold, height: 1.0),
                            ),
                            if (hasRoute) 
                              InkWell(
                                onTap: () => _showFareDialog(context, isDark),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.monetization_on, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                                      const SizedBox(width: 4),
                                      Text(
                                        langCtrl.tr('fare_table'),
                                        style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700], fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        
                        // 🌟 分拆靜止與走馬燈
                        if (hasRoute)
                          Row(
                            children: [
                              Text(
                                '${langCtrl.tr('direction_to')} ',
                                style: const TextStyle(color: Colors.grey, fontSize: 15),
                              ),
                              Expanded(
                                child: FitMarqueeText(
                                  currentTerminal,
                                  style: const TextStyle(color: Colors.grey, fontSize: 15),
                                ),
                              ),
                            ],
                          )
                        else
                          Text(langCtrl.tr('please_search_route'), style: const TextStyle(color: Colors.grey, fontSize: 15)),
                        
                        if (hasRoute) ...[
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildHeaderIcon(Icons.swap_calls, langCtrl.tr('swap_direction'), isDark, () { 
                                  busCtrl.toggleDirection();
                                  busCtrl.fetchStops();
                                  context.read<NavigationController>().clearNavigation(); 
                                }),
                              ),
                              Expanded(
                                child: _buildHeaderIcon(
                                  Icons.my_location, 
                                  langCtrl.tr('location'), 
                                  isDark, 
                                  () {
                                    // 🌟 修正開關 GPS 邏輯，避免彈出多餘白色橫幅
                                    final isTurningOn = !locCtrl.isFollowingUser; 
                                    GpsService.toggleGpsAndAutoSelectStop(context, busCtrl, locCtrl);
                                    if (isTurningOn) {
                                      _scrollToNearestStop();
                                    }
                                  },
                                  color: locCtrl.isFollowingUser ? Colors.green : (isDark ? Colors.white : Colors.black87)
                                ),
                              ),
                              Expanded(
                                child: _buildHeaderIcon(Icons.schedule, langCtrl.tr('timetable'), isDark, () => _showTimetableDialog(busCtrl)),
                              ),
                              if (!isSimpleMode)
                                Expanded(
                                  child: _buildHeaderIcon(
                                    Icons.map,
                                    langCtrl.tr('tab_map'),
                                    isDark,
                                    () {
                                      final nav = context.read<NavigationController>();
                                      nav.clearNavigation();
                                      nav.setPlanningRoute(false);
                                      nav.openMap();
                                    },
                                  ),
                                ),
                              Expanded(
                                child: _buildHeaderIcon(
                                  isFavorite ? Icons.star : Icons.star_border, 
                                  langCtrl.tr('favorite'), 
                                  isDark, 
                                  () => busCtrl.toggleFavorite(busCtrl.currentRoute),
                                  color: isFavorite ? Colors.amber : null
                                ),
                              ),
                            ],
                          ),
                        ],
                        
                        if (combinedAlertWidgets.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: combinedAlertWidgets,
                            ),
                          ),
                        ],
                      ]
                    )
                  ),
                ),
              ),
              Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
              
              Expanded(
                child: busCtrl.isLoadingStops 
                  ? const Center(child: CircularProgressIndicator(color: Colors.amber)) 
                  : busCtrl.stopsList.isNotEmpty
                    ? ListView.builder(
                        controller: _listScrollController,
                        padding: EdgeInsets.only(
                          top: 8,
                          bottom: MediaQuery.paddingOf(context).bottom,
                        ),
                        itemCount: busCtrl.stopsList.length,
                        itemBuilder: (context, index) {
                          final stop = busCtrl.stopsList[index]; 
                          final isSelected = busCtrl.selectedStopSeq == stop.seq;
                          final hasBoardingAlarm = busCtrl.boardingStopSeq == stop.seq;
                          final hasAlightingAlarm = busCtrl.alightingStopSeq == stop.seq;
                          final isAlarmActive = hasBoardingAlarm || hasAlightingAlarm;
                          
                          if (isSelected) {
                            return Column(
                              key: _selectedStopKey,
                              children: [
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1), 
                                        blurRadius: 16, 
                                        offset: const Offset(0, 8)
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 24.0, sigmaY: 24.0), 
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16),
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: isDark ? [
                                              Colors.white.withValues(alpha: 0.15),
                                              Colors.white.withValues(alpha: 0.05),
                                            ] : [
                                              Colors.white.withValues(alpha: 0.85),
                                              Colors.white.withValues(alpha: 0.5),
                                            ],
                                          ),
                                          border: Border.all(
                                            color: isDark ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.7), 
                                            width: 1.2
                                          ),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () { busCtrl.selectStop(stop.seq); busCtrl.fetchBusETA(); },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0), 
                                              child: Builder(
                                                builder: (context) {
                                                  final upcomingInfo = _getUpcomingBusesInfo(busCtrl, langCtrl);
                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      // 🌟 絕對對齊：中心水平對齊
                                                      Row(
                                                        crossAxisAlignment: CrossAxisAlignment.center, 
                                                        children: [
                                                          SizedBox(
                                                            width: 28,
                                                            child: Text('${stop.seq}.', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              '${stop.getLocalizedName(langCtrl.currentLanguage)} (${stop.code})', 
                                                              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold)
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            crossAxisAlignment: CrossAxisAlignment.center,
                                                            children: [
                                                              AnimatedSize(
                                                                duration: const Duration(milliseconds: 350),
                                                                curve: Curves.easeOutCubic,
                                                                child: _hasAnyStopWarning(stop)
                                                                    ? Padding(
                                                                        padding: const EdgeInsets.only(right: 4.0),
                                                                        child: BlinkingWarningIcon(onTap: () => _openStopWarning(stop)),
                                                                      )
                                                                    : const SizedBox.shrink(),
                                                              ),
                                                              IconButton(
                                                                icon: Icon(
                                                                  isAlarmActive ? Icons.notifications_active : Icons.notifications_none, 
                                                                  color: hasBoardingAlarm ? Colors.amber : (hasAlightingAlarm ? Colors.blueAccent : Colors.grey)
                                                                ),
                                                                padding: EdgeInsets.zero, 
                                                                constraints: const BoxConstraints(minHeight: 32, minWidth: 32), 
                                                                tooltip: langCtrl.tr('set_alarm'),
                                                                onPressed: () => _showAlarmBottomSheet(context, stop, busCtrl, locCtrl, isDark),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 8), 
                                                      
                                                      IntrinsicHeight(
                                                        child: Row(
                                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                                          children: [
                                                            Container(
                                                              width: 4, 
                                                              decoration: BoxDecoration(
                                                                color: Colors.amber,
                                                                borderRadius: BorderRadius.circular(2)
                                                              )
                                                            ),
                                                            const SizedBox(width: 10),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                mainAxisAlignment: MainAxisAlignment.center,
                                                                children: [
                                                                  const LiveTrackingBadge(),
                                                                  
                                                                  if (busCtrl.isLoadingETA)
                                                                    const Padding(padding: EdgeInsets.only(top: 8.0), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.amber)))
                                                                  else if (upcomingInfo.isNotEmpty) ...[
                                                                    const SizedBox(height: 8),
                                                                    ...upcomingInfo.asMap().entries.map((entry) {
                                                                      int idx = entry.key; var busInfo = entry.value; bool isSecondBus = idx == 1; 
                                                                      return Padding(
                                                                        padding: EdgeInsets.only(top: isSecondBus ? 6.0 : 0.0),
                                                                        child: Row(
                                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                          crossAxisAlignment: CrossAxisAlignment.center,
                                                                          children: [
                                                                            Expanded(
                                                                              child: Text(
                                                                                busInfo['status'] ?? '', 
                                                                                style: TextStyle(color: isDark ? (isSecondBus ? Colors.amber.shade200 : Colors.amber) : (isSecondBus ? Colors.orange.shade500 : Colors.orange.shade700), fontWeight: FontWeight.bold, fontSize: isSecondBus ? 13 : 15)
                                                                              )
                                                                            ),
                                                                            if (busInfo['plate'] != null && busInfo['plate']!.isNotEmpty) 
                                                                              Text(
                                                                                '${langCtrl.tr('bus_plate')}${busInfo['plate']}', // 🌟 多國語言車牌
                                                                                style: TextStyle(color: isDark ? (isSecondBus ? Colors.grey[500] : Colors.grey[400]) : (isSecondBus ? Colors.grey[600] : Colors.grey[800]), fontSize: 12, fontWeight: FontWeight.normal)
                                                                              ),
                                                                          ],
                                                                        ),
                                                                      );
                                                                    }),
                                                                  ]
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ]
                                                  );
                                                }
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              InkWell(
                                onTap: () { busCtrl.selectStop(stop.seq); busCtrl.fetchBusETA(); },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), 
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start, 
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 28,
                                                  child: Text('${stop.seq}.', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.w500)),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    '${stop.getLocalizedName(langCtrl.currentLanguage)} (${stop.code})', 
                                                    style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.w500)
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ]
                                        )
                                      ),
                                      if (_hasAnyStopWarning(stop)) ...[
                                        const SizedBox(width: 8),
                                        BlinkingWarningIcon(onTap: () => _openStopWarning(stop)),
                                      ],
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: Icon(isAlarmActive ? Icons.notifications_active : Icons.notifications_none, color: hasBoardingAlarm ? Colors.amber : (hasAlightingAlarm ? Colors.blueAccent : Colors.grey)),
                                        padding: EdgeInsets.zero, constraints: const BoxConstraints(), tooltip: langCtrl.tr('set_alarm'),
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
                      )
                    : Center(
                        child: Text(
                          AppTranslations.localizeErrorMessage(busCtrl.errorMessage ?? '', langCtrl.tr),
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class VirtualMapPainter extends CustomPainter {
  final bool isDark;
  VirtualMapPainter({required this.isDark});
  @override
  void paint(Canvas canvas, Size size) {
    final nodeInnerColor = isDark ? const Color(0xFF101010) : const Color(0xFFF7F7F7); 

    final lineColor1 = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05);
    final lineColor2 = isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03);

    final paintLine1 = Paint()..color = lineColor1..strokeWidth = 6.0..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final paintLine2 = Paint()..color = lineColor2..strokeWidth = 4.0..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    
    final paintNodeInner = Paint()..color = nodeInnerColor..style = PaintingStyle.fill;
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