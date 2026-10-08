import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/language_controller.dart'; 
import '../../services/places_service.dart';
import '../../utils/place_suggestions.dart';
import '../../services/otp_service.dart'; // 🌟 正規化引入獨立嘅 Service
import '../../services/local_timetable.dart';
import '../../models/itinerary.dart';
import '../../utils/venue_entrances.dart';
import 'route_liquid_glass_nav.dart';

class RoutingBottomSheet extends StatefulWidget {
  final LatLng? userLocation;
  final bool isLocationActive; 
  final LatLng? customMapStart;
  final LatLng? customMapEnd;
  final VoidCallback onPickOnMap;
  final VoidCallback onPickEndOnMap;
  final Function(List<Itinerary>, String, bool) onRouteCalculated;

  const RoutingBottomSheet({
    super.key,
    this.userLocation,
    this.isLocationActive = false, 
    this.customMapStart,
    this.customMapEnd,
    required this.onPickOnMap,
    required this.onPickEndOnMap,
    required this.onRouteCalculated,
  });

  @override
  State<RoutingBottomSheet> createState() => _RoutingBottomSheetState();
}

class _RoutingBottomSheetState extends State<RoutingBottomSheet> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  final FocusNode _startFocus = FocusNode();
  final FocusNode _destFocus = FocusNode();

  bool _isRoutingWithOTP = false;
  bool _isSearchingStart = false;
  String? _startPlaceId;
  String? _destPlaceId;
  final String _sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
  List<dynamic> _placeSuggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locCtrl = context.read<LocationController>();
      final langCtrl = context.read<LanguageController>();
      
      if (widget.customMapStart != null) {
        _startController.text = langCtrl.tr('custom_start');
      } else if (locCtrl.userLocation != null && locCtrl.isFollowingUser) {
        _startController.text = langCtrl.tr('current_gps_location');
      }
      if (widget.customMapEnd != null) {
        _destController.text = langCtrl.tr('custom_end');
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _startController.dispose();
    _destController.dispose();
    _startFocus.dispose();
    _destFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query, {required bool isStart}) {
    _isSearchingStart = isStart;
    if (isStart) {
      _startPlaceId = null;
    } else {
      _destPlaceId = null;
    }
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      if (!mounted) return;
      if (query.isEmpty) {
        setState(() => _placeSuggestions = []);
        return;
      }
      final lang = context.read<LanguageController>().currentLanguage;
      final predictions = await PlacesService.autocomplete(query, _sessionToken, language: lang);
      if (mounted) {
        setState(() => _placeSuggestions = PlaceSuggestions.refine(query, lang, predictions));
      }
    });
  }

  void _onSuggestionTapped(String placeName, String placeId) {
    if (_isSearchingStart) {
      _startController.text = placeName;
      _startPlaceId = placeId;
    } else {
      _destController.text = placeName;
      _destPlaceId = placeId;
    }
    setState(() => _placeSuggestions = []);
    FocusScope.of(context).unfocus();
  }


  bool _isServiceUnavailableEta(String eta, LanguageController langCtrl) {
    if (eta.isEmpty) return false;
    final t = eta.trim();
    return t.contains('本日服務已結束') ||
        t.contains('服務已結束') ||
        t.contains('服务已结束') ||
        t.contains('尾班車已過') ||
        t.contains('本日不設服務') ||
        t.contains('不設服務') ||
        t.contains('不设服务') ||
        t.contains('本日服務尚未開始') ||
        t.contains('服務尚未開始') ||
        t.contains('尚未開始') ||
        t.contains('尚未开始') ||
        t == langCtrl.tr('service_ended') ||
        t == langCtrl.tr('no_service_today') ||
        t == langCtrl.tr('service_not_started') ||
        t == langCtrl.tr('last_bus_departed') ||
        t.contains('Service ended') ||
        t.contains('Service not started') ||
        t.contains('No service today') ||
        t.contains('Sem serviço hoje') ||
        t.contains('Servico terminado') ||
        t.contains('Serviço terminado') ||
        t.contains('Serviço não iniciado');
  }

  bool _itineraryHasGhostBus(Itinerary it, LanguageController langCtrl) {
    for (final leg in it.legs) {
      if (leg.mode != 'BUS' && leg.mode != 'TRANSIT') continue;
      if (LocalTimetable.unavailableForPlanning(
        leg.routeName,
        at: leg.boardingTimeMacau,
      )) {
        return true;
      }
      final eta = leg.realtimeEta ?? '';
      if (_isServiceUnavailableEta(eta, langCtrl)) return true;
    }
    return false;
  }

  // ---- Plan ranking -------------------------------------------------------
  // score = total time incl. waiting + extra weight on walking + a penalty per
  // transfer. Long walks / ultra-short transfer rides are dropped when a
  // better bus option exists.
  static const int _walkWeightPercent = 100; // each walk second counts 2x
  static const int _transferPenaltySec = 300;
  static const int _maxWalkLegSec = 12 * 60;
  static const int _minTransferRideSec = 3 * 60;
  static const int _maxPlansToMatch = 8;
  static const int _maxPlansShown = 6;

  static bool _isBusLeg(RouteLeg l) => l.mode == 'BUS' || l.mode == 'TRANSIT';

  static int _busLegCount(Itinerary it) => it.legs.where(_isBusLeg).length;

  static int _planScore(Itinerary it) {
    var walkSec = 0;
    for (final l in it.legs) {
      if (l.mode == 'WALK') walkSec += l.duration;
    }
    final transfers = _busLegCount(it) > 1 ? _busLegCount(it) - 1 : 0;
    return it.totalSecondsInclWait +
        walkSec * _walkWeightPercent ~/ 100 +
        transfers * _transferPenaltySec;
  }

  static bool _hasLongWalk(Itinerary it) =>
      it.legs.any((l) => l.mode == 'WALK' && l.duration > _maxWalkLegSec);

  static bool _hasShortTransferRide(Itinerary it) {
    final bus = it.legs.where(_isBusLeg).toList();
    return bus.length > 1 && bus.any((l) => l.duration < _minTransferRideSec);
  }

  static String _patternOf(Itinerary it) {
    final names = <String>[
      for (final l in it.legs.where(_isBusLeg))
        l.routeName.isNotEmpty ? l.routeName : 'BUS',
    ];
    return names.isEmpty ? 'WALK_ONLY' : names.join('->');
  }

  /// Bus plans arriving more than max(15 min, 30% of the best total) after
  /// the earliest bus arrival are dominated (e.g. a 102→H2 plan on a much
  /// later 102 trip). Walk-only plans are not affected. Never empties.
  static const int _lateMinSec = 15 * 60;
  static const int _latePercent = 30;

  static List<Itinerary> _dropLateBusPlans(List<Itinerary> plans) {
    Itinerary? best;
    for (final it in plans) {
      if (_busLegCount(it) == 0 || it.arriveAtMs == null) continue;
      if (best == null || it.arriveAtMs! < best.arriveAtMs!) best = it;
    }
    if (best == null) return plans;
    final pct = best.totalSecondsInclWait * _latePercent ~/ 100;
    final slackMs = (pct > _lateMinSec ? pct : _lateMinSec) * 1000;
    final limit = best.arriveAtMs! + slackMs;
    final out = plans
        .where((it) =>
            _busLegCount(it) == 0 ||
            it.arriveAtMs == null ||
            it.arriveAtMs! <= limit)
        .toList();
    return out.isEmpty ? plans : out;
  }

  /// Filter, score-sort and dedupe (best plan per bus pattern).
  static List<Itinerary> _rankPlans(List<Itinerary> plans) {
    final bus = plans.where((it) => _busLegCount(it) > 0).toList();
    var keep = plans;
    if (bus.isNotEmpty) {
      final good = bus
          .where((it) => !_hasLongWalk(it) && !_hasShortTransferRide(it))
          .toList();
      if (good.isNotEmpty) {
        // Any bus option exists → drop long-walk plans (incl. long walk-only)
        // and plans with a < 3 min transfer ride.
        keep = plans.where((it) => !_hasLongWalk(it) && !_hasShortTransferRide(it)).toList();
      } else {
        final noShort = plans.where((it) => !_hasShortTransferRide(it)).toList();
        if (noShort.any((it) => _busLegCount(it) > 0)) keep = noShort;
      }
    }
    keep = _dropLateBusPlans(keep);
    final scored = [for (final it in keep) (it: it, score: _planScore(it))]
      ..sort((a, b) => a.score.compareTo(b.score));
    final seen = <String>{};
    final out = <Itinerary>[];
    for (final e in scored) {
      if (seen.add(_patternOf(e.it))) out.add(e.it);
    }
    return out;
  }

  Future<void> _routeWithOTP() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final langCtrl = context.read<LanguageController>();

    final startText = _startController.text.trim();
    final destText = _destController.text.trim();
    
    if (startText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: context, content: Text(langCtrl.tr('pls_enter_start'))));
      return;
    }
    if (destText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: context, content: Text(langCtrl.tr('pls_enter_dest'))));
      return;
    }
    
    final navCtrl = context.read<NavigationController>();
    final locCtrl = context.read<LocationController>();
    
    final currentUserLoc = locCtrl.isFollowingUser ? locCtrl.userLocation : null;

    if ((startText.contains('GPS') || destText.contains('GPS')) && currentUserLoc == null) {
       _showErrorDialog(langCtrl.tr('locating_gps_title'), langCtrl.tr('locating_gps_desc'), langCtrl);
       return;
    }

    setState(() => _isRoutingWithOTP = true);
    
    try {
      unawaited(LocalTimetable.ensureLoaded());
      final startFuture = navCtrl.getCoordinate(
        startText,
        true,
        currentUserLoc,
        widget.customMapStart,
        widget.customMapEnd,
        _sessionToken,
        _startPlaceId,
        langCtrl,
      );
      final destFuture = navCtrl.getCoordinate(
        destText,
        false,
        currentUserLoc,
        widget.customMapStart,
        widget.customMapEnd,
        _sessionToken,
        _destPlaceId,
        langCtrl,
      );
      // Pins inside large venues (威尼斯人) are routed from/to the nearest
      // walk-connected entrance.
      final startRaw = await startFuture;
      final destRaw = await destFuture;
      final startLoc = startRaw == null ? null : VenueEntrances.snap(startRaw);
      final destLoc = destRaw == null ? null : VenueEntrances.snap(destRaw);
      if (startLoc == null) {
        String desc = langCtrl.tr('invalid_start_desc').replaceAll('@text', startText);
        if (mounted) _showErrorDialog(langCtrl.tr('invalid_start_title'), desc, langCtrl);
        setState(() => _isRoutingWithOTP = false);
        return;
      }
      if (destLoc == null) {
        String desc = langCtrl.tr('invalid_dest_desc').replaceAll('@text', destText);
        if (mounted) _showErrorDialog(langCtrl.tr('invalid_dest_title'), desc, langCtrl);
        setState(() => _isRoutingWithOTP = false);
        return;
      }

      final requestedAtMs = DateTime.now().millisecondsSinceEpoch;
      final result = await OTPService.getRoutePlan(
        fromLat: startLoc.latitude,
        fromLng: startLoc.longitude,
        toLat: destLoc.latitude,
        toLng: destLoc.longitude,
        langCtrl: langCtrl,
      );

      List<Itinerary> uniqueItineraries = [];
      if (result is List<dynamic>) {
        await LocalTimetable.ensureLoaded();
        final parsed = <Itinerary>[];
        for (var rawIt in result) {
          final itinerary = Itinerary.fromJson(rawIt as Map<String, dynamic>)
            ..requestedAtMs = requestedAtMs;
          // OTP legs carry their scheduled boarding time at that stop (GTFS
          // per-stop times incl. holidays), so they are trusted; the bundled
          // terminal windows only gate legs without a time.
          final hasNoServiceRoute = itinerary.legs.any((leg) =>
              _isBusLeg(leg) &&
              LocalTimetable.unavailableForPlanning(
                leg.routeName,
                at: leg.boardingTimeMacau,
              ));
          if (hasNoServiceRoute) continue;
          parsed.add(itinerary);
        }
        // Rank on OTP data before matching so only the best few patterns
        // need official stop lists (keeps the pipeline as fast as before).
        uniqueItineraries = _rankPlans(parsed);
        if (uniqueItineraries.length > _maxPlansToMatch) {
          uniqueItineraries = uniqueItineraries.sublist(0, _maxPlansToMatch);
        }
      }

      // Match official board/alight first. ETA is filled after results show.
        final lang = langCtrl.currentLanguage;
        final routesToPrefetch = <String>{};
        for (final itinerary in uniqueItineraries) {
          for (final leg in itinerary.legs) {
            if (leg.mode == 'BUS' || leg.mode == 'TRANSIT') {
              final name = leg.routeName.trim();
              if (name.isNotEmpty &&
                  !LocalTimetable.unavailableForPlanning(
                    name,
                    at: leg.boardingTimeMacau,
                  )) {
                routesToPrefetch.add(name);
              }
            }
          }
        }
        if (routesToPrefetch.isNotEmpty) {
          await Future.wait([
            for (final route in routesToPrefetch)
              navCtrl.prefetchRouteStops(route, lang),
          ]);
        }

        final List<Future<void>> matchTasks = [];
        for (final itinerary in uniqueItineraries) {
          for (final leg in itinerary.legs) {
            if (leg.mode == 'BUS' || leg.mode == 'TRANSIT') {
              matchTasks.add(navCtrl.enrichLeg(leg, langCtrl, includeEta: false));
            }
          }
        }
        if (matchTasks.isNotEmpty) {
          await Future.wait(matchTasks);
        }

        // (1) Keep only itineraries whose bus legs mapped onto official stops
        // and are actually running (not ended / no service today).
        List<Itinerary> officialItineraries = [];
        for (final it in uniqueItineraries) {
          final busLegs = it.legs
              .where((l) => l.mode == 'BUS' || l.mode == 'TRANSIT')
              .toList();
          if (busLegs.isEmpty) {
            officialItineraries.add(it); // walk-only
            continue;
          }
          if (_itineraryHasGhostBus(it, langCtrl)) continue;
          final ok = busLegs.every(
            (l) => l.boardingStopSeq != null && l.alightStopSeq != null,
          );
          if (ok) officialItineraries.add(it);
        }

        List<Itinerary> activeItineraries = [];
        for (final it in officialItineraries) {
          if (_itineraryHasGhostBus(it, langCtrl)) continue;
          activeItineraries.add(it);
        }

        const onlyGhostsLeft = false;

        String patternOf(Itinerary it) => _patternOf(it);

        // Official backup only if OTP left nothing usable — extra nearby/ETA
        // is what made every plan wait on 8s/12s timeouts.
        if (activeItineraries.isEmpty) {
          final existingPatterns = <String>{};
          for (final it in activeItineraries) {
            existingPatterns.add(patternOf(it));
          }

          final fallback = await navCtrl.suggestOfficialDirectBuses(
            fromLat: startLoc.latitude,
            fromLng: startLoc.longitude,
            toLat: destLoc.latitude,
            toLng: destLoc.longitude,
            langCtrl: langCtrl,
            includeTwoTransfers: true,
          );
          for (final it in fallback) {
            final pattern = patternOf(it);
            if (existingPatterns.contains(pattern)) continue;
            if (_itineraryHasGhostBus(it, langCtrl)) continue;
            final busLegs = it.legs
                .where((l) => l.mode == 'BUS' || l.mode == 'TRANSIT')
                .toList();
            if (busLegs.isNotEmpty &&
                busLegs.any((l) => l.boardingStopSeq == null || l.alightStopSeq == null)) {
              continue;
            }
            existingPatterns.add(pattern);
            activeItineraries.add(it);
          }
        }

        for (final it in activeItineraries) {
          it.requestedAtMs ??= requestedAtMs;
        }
        activeItineraries = _rankPlans(activeItineraries);
        if (activeItineraries.length > _maxPlansShown) {
          activeItineraries = activeItineraries.sublist(0, _maxPlansShown);
        }

        if (activeItineraries.isEmpty) {
          final noValidTitle = langCtrl.tr('no_valid_route');
          final noValidDesc = langCtrl.tr('no_valid_route_desc');
          if (mounted) _showErrorDialog(noValidTitle, noValidDesc, langCtrl);
          return;
        }

        if (mounted) {
          navCtrl.clearNavigation();
          widget.onRouteCalculated(activeItineraries, destText, onlyGhostsLeft);
          unawaited(navCtrl.fillItinerariesEta(activeItineraries, langCtrl));
        }
    } catch (e) {
      if (mounted) _showErrorDialog(langCtrl.tr('app_crash_title'), e.toString(), langCtrl);
    } finally {
      if (mounted) setState(() => _isRoutingWithOTP = false);
    }
  }

  void _showErrorDialog(String title, String message, LanguageController langCtrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        title: Row(children: [const Icon(Icons.error_outline, color: Colors.redAccent), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(color: Colors.redAccent, fontSize: 18)))]),
        content: Text(message, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(langCtrl.tr('received'), style: const TextStyle(color: Colors.amber)))],
      ),
    );
  }

  Widget _buildSuggestionsList(bool isDark) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))
        ],
        border: Border.all(color: isDark ? Colors.white24 : Colors.grey[300]!),
      ),
      child: Material(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: _placeSuggestions.length,
          separatorBuilder: (context, index) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey[200]),
          itemBuilder: (context, index) {
            final prediction = _placeSuggestions[index];
            final mainText = prediction['structured_formatting']?['main_text'] ?? prediction['description'];
            final secondaryText = prediction['structured_formatting']?['secondary_text'] ?? '';
            return ListTile(
              dense: true,
              leading: const Icon(Icons.place, color: Colors.amber, size: 20),
              title: Text(mainText, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: secondaryText.isNotEmpty ? Text(secondaryText, style: const TextStyle(color: Colors.grey, fontSize: 12)) : null,
              onTap: () => _onSuggestionTapped(prediction['description'], prediction['place_id']),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locCtrl = context.watch<LocationController>();
    final langCtrl = context.watch<LanguageController>(); 

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16, 
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
              ),
              Text(langCtrl.tr('routing_title'), style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              Row(
                children: [
                  const Icon(Icons.trip_origin, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _startController,
                      focusNode: _startFocus,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      onChanged: (val) => _onSearchChanged(val, isStart: true),
                      decoration: InputDecoration(
                        hintText: langCtrl.tr('hint_start'),
                        hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[200],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                          onPressed: () {
                            _startController.clear();
                            _startPlaceId = null;
                            setState(() => _placeSuggestions = []);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.my_location, 
                      color: locCtrl.isFollowingUser ? Colors.green : Colors.amber.shade700
                    ),
                    tooltip: langCtrl.tr('locate_position'),
                    onPressed: () {
                      if (!locCtrl.isFollowingUser) {
                        locCtrl.toggleLocationTracking((_) {}); 
                        ScaffoldMessenger.of(context).showSnackBar(
                          RouteLiquidGlassNavStyle.snackBar(
                            context: context,
                            content: Text(langCtrl.tr('start_gps_tracking')),
                          ),
                        );
                      }
                      
                      _startController.text = langCtrl.tr('current_gps_location');
                      _startPlaceId = null;
                      setState(() => _placeSuggestions = []);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.map, color: Colors.blueAccent),
                    tooltip: langCtrl.tr('select_on_map_start'),
                    onPressed: widget.onPickOnMap,
                  ),
                ],
              ),

              if (_isSearchingStart && _placeSuggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildSuggestionsList(isDark),
              ],

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Divider(color: isDark ? const Color(0xFF333333) : Colors.grey[300]),
              ),

              Row(
                children: [
                  const Icon(Icons.trip_origin, color: Colors.redAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _destController,
                      focusNode: _destFocus,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      onChanged: (val) => _onSearchChanged(val, isStart: false),
                      decoration: InputDecoration(
                        hintText: langCtrl.tr('hint_dest'),
                        hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[200],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                          onPressed: () {
                            _destController.clear();
                            _destPlaceId = null;
                            setState(() => _placeSuggestions = []);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.map, color: Colors.blueAccent),
                    tooltip: langCtrl.tr('select_on_map_end'),
                    onPressed: widget.onPickEndOnMap,
                  ),
                ],
              ),

              if (!_isSearchingStart && _placeSuggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildSuggestionsList(isDark),
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isRoutingWithOTP
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Icon(Icons.assistant_direction, color: Colors.black),
                  label: Text(
                    _isRoutingWithOTP ? langCtrl.tr('brain_computing') : langCtrl.tr('brain_nav'),
                    style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isRoutingWithOTP ? null : _routeWithOTP,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[200],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.navigation, color: Colors.blueAccent),
                  label: Text(langCtrl.tr('open_amap'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16)),
                  onPressed: () async {
                    final navCtrl = context.read<NavigationController>();
                    final currentUserLoc = locCtrl.isFollowingUser ? locCtrl.userLocation : null;
                    
                    final errorMsg = await navCtrl.launchThirdPartyMap(
                      false,
                      _startController.text.trim(),
                      _destController.text.trim(),
                      currentUserLoc,
                      widget.customMapStart,
                      widget.customMapEnd,
                      _sessionToken,
                      _startPlaceId,
                      _destPlaceId,
                      langCtrl,
                    );
                    if (!context.mounted) return;
                    if (errorMsg != null) {
                      ScaffoldMessenger.of(context).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: context, content: Text(errorMsg)));
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[200],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.location_on, color: Colors.redAccent),
                  label: Text(langCtrl.tr('open_gmap'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16)),
                  onPressed: () async {
                    final navCtrl = context.read<NavigationController>();
                    final currentUserLoc = locCtrl.isFollowingUser ? locCtrl.userLocation : null;
                    
                    final errorMsg = await navCtrl.launchThirdPartyMap(
                      true,
                      _startController.text.trim(),
                      _destController.text.trim(),
                      currentUserLoc,
                      widget.customMapStart,
                      widget.customMapEnd,
                      _sessionToken,
                      _startPlaceId,
                      _destPlaceId,
                      langCtrl,
                    );
                    if (!context.mounted) return;
                    if (errorMsg != null) {
                      ScaffoldMessenger.of(context).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: context, content: Text(errorMsg)));
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}