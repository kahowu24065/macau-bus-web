import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../services/places_service.dart';
import '../../models/itinerary.dart';

class OTPService {
  static const String baseUrl = 'https://api.macaubus-kat1.com/otp/routers/default/index/graphql';
  static Future<dynamic> getRoutePlan({required double fromLat, required double fromLng, required double toLat, required double toLng}) async {
    try {
      final now = DateTime.now();
      final timeString = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final dateString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final String graphqlQuery = '''{ plan(from: {lat: $fromLat, lon: $fromLng} to: {lat: $toLat, lon: $toLng} date: "$dateString" time: "$timeString" numItineraries: 5 maxWalkDistance: 2000.0 walkReluctance: 8.0 transportModes: [{mode: WALK}, {mode: TRANSIT}]) { itineraries { duration legs { mode duration startTime endTime route { gtfsId, shortName } from { name, lat, lon } to { name, lat, lon } legGeometry { points } } } } }''';
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'query': graphqlQuery}),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['errors'] != null) {
          return "GraphQL 語法錯誤";
        }
        if (data['data'] != null && data['data']['plan'] != null) {
          final itineraries = data['data']['plan']['itineraries'] as List;
          if (itineraries.isNotEmpty) {
            itineraries.sort((a, b) => (a['duration'] as num).compareTo(b['duration'] as num));
            return itineraries;
          }
          return "大腦話呢個距離/時間搵唔到路線！(可能步行距離太遠)";
        }
      }
      return "OTP 伺服器錯誤";
    } catch (e) {
      return "網絡連線失敗: $e";
    }
  }
}

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
    final locCtrl = context.read<LocationController>();
    
    if (widget.customMapStart != null) {
      _startController.text = '地圖自選起點 🟢';
    } else if (locCtrl.userLocation != null && locCtrl.isFollowingUser) {
      _startController.text = '目前位置 (GPS)';
    }
    if (widget.customMapEnd != null) {
      _destController.text = '地圖自選終點 🔴';
    }
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
      if (query.isEmpty) {
        if (mounted) {
          setState(() => _placeSuggestions = []);
        }
        return;
      }
      final predictions = await PlacesService.autocomplete(query, _sessionToken);
      if (mounted) {
        setState(() => _placeSuggestions = predictions);
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

  Future<void> _routeWithOTP() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final startText = _startController.text.trim();
    final destText = _destController.text.trim();
    if (startText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先輸入起點')));
      return;
    }
    if (destText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先輸入目的地')));
      return;
    }
    
    final navCtrl = context.read<NavigationController>();
    final locCtrl = context.read<LocationController>();
    
    final currentUserLoc = locCtrl.isFollowingUser ? locCtrl.userLocation : null;

    if ((startText == '目前位置 (GPS)' || destText == '目前位置 (GPS)') && currentUserLoc == null) {
       _showErrorDialog('GPS 定位中', '系統正在獲取您的實時位置，請確保已開啟定位權限，稍等幾秒後再重試。');
       return;
    }

    setState(() => _isRoutingWithOTP = true);
    
    try {
      final startLoc = await navCtrl.getCoordinate(startText, true, currentUserLoc, widget.customMapStart, widget.customMapEnd, _sessionToken, _startPlaceId);
      if (startLoc == null) {
        if (mounted) _showErrorDialog('起點無效', '大腦搵唔到「$startText」嘅座標。');
        setState(() => _isRoutingWithOTP = false);
        return;
      }
      
      final destLoc = await navCtrl.getCoordinate(destText, false, currentUserLoc, widget.customMapStart, widget.customMapEnd, _sessionToken, _destPlaceId);
      if (destLoc == null) {
        if (mounted) _showErrorDialog('目的地無效', '大腦搵唔到「$destText」嘅座標。');
        setState(() => _isRoutingWithOTP = false);
        return;
      }
      
      final result = await OTPService.getRoutePlan(fromLat: startLoc.latitude, fromLng: startLoc.longitude, toLat: destLoc.latitude, toLng: destLoc.longitude);
      
      if (result is List<dynamic>) {
        List<Itinerary> uniqueItineraries = [];
        Set<String> seenPatterns = {};
        
        for (var rawIt in result) {
          final itinerary = Itinerary.fromJson(rawIt as Map<String, dynamic>);
          List<String> routeNames = [];
          for (var leg in itinerary.legs) {
            if (leg.mode == 'BUS' || leg.mode == 'TRANSIT') {
              routeNames.add(leg.routeName.isNotEmpty ? leg.routeName : 'BUS');
            }
          }
          String pattern = routeNames.join('->');
          if (pattern.isEmpty) pattern = 'WALK_ONLY';
          if (!seenPatterns.contains(pattern)) {
            seenPatterns.add(pattern);
            uniqueItineraries.add(itinerary);
          }
        }
        
        List<Future<void>> enrichmentTasks = [];
        for (var itinerary in uniqueItineraries) {
          for (var leg in itinerary.legs) {
            if (leg.mode == 'BUS' || leg.mode == 'TRANSIT') {
              enrichmentTasks.add(navCtrl.enrichLeg(leg));
            }
          }
        }
        await Future.wait(enrichmentTasks);
        
        List<Itinerary> activeItineraries = [];
        for (var it in uniqueItineraries) {
          bool hasGhost = false;
          for (var leg in it.legs) {
            if (leg.mode == 'BUS' || leg.mode == 'TRANSIT') {
              final eta = leg.realtimeEta ?? '';
              if (eta.contains('未有') || eta.contains('失敗') || eta == 'null' || 
                  eta.contains('不設服務') || eta.contains('已結束') || eta.contains('尾班車已過')) {
                hasGhost = true;
                break;
              }
            }
          }
          if (!hasGhost) activeItineraries.add(it);
        }

        bool onlyGhostsLeft = false;
        if (activeItineraries.isEmpty && uniqueItineraries.isNotEmpty) {
          activeItineraries = uniqueItineraries; 
          onlyGhostsLeft = true;
        }

        if (mounted) {
          navCtrl.clearNavigation(); 
          widget.onRouteCalculated(activeItineraries, destText, onlyGhostsLeft); 
        }
      } else {
        if (mounted) _showErrorDialog('OTP 大腦連線異常', result.toString());
      }
    } catch (e) {
      if (mounted) _showErrorDialog('App 內部發生崩潰', e.toString());
    } finally {
      if (mounted) setState(() => _isRoutingWithOTP = false);
    }
  }

  void _showErrorDialog(String title, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        title: Row(children: [const Icon(Icons.error_outline, color: Colors.redAccent), const SizedBox(width: 8), Text(title, style: const TextStyle(color: Colors.redAccent, fontSize: 18))]),
        content: Text(message, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('收到', style: TextStyle(color: Colors.amber)))],
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
              const Text('路線規劃', style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
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
                        hintText: '輸入起點、選擇定位或地圖',
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
                    // 🌟 統一圖示：永遠顯示實心點嘅 Icons.my_location，色調同主畫面完全一致
                    icon: Icon(
                      Icons.my_location, 
                      color: locCtrl.isFollowingUser ? Colors.green : Colors.amber.shade700
                    ),
                    tooltip: '用目前定位',
                    onPressed: () {
                      if (!locCtrl.isFollowingUser) {
                        locCtrl.toggleLocationTracking((_) {}); 
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('啟動實時 GPS 定位中...'), 
                            duration: Duration(seconds: 2)
                          )
                        );
                      }
                      
                      _startController.text = '目前位置 (GPS)';
                      _startPlaceId = null;
                      setState(() => _placeSuggestions = []);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.map, color: Colors.blueAccent),
                    tooltip: '在地圖選起點',
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
                        hintText: '輸入目的地 (例如：大三巴)',
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
                    tooltip: '在地圖選終點',
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
                    _isRoutingWithOTP ? '大腦運算中...' : '使用 專屬大腦 導航 (首選)',
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
                  label: Text('打開 高德地圖', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16)),
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
                    );
                    if (!context.mounted) return;
                    if (errorMsg != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
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
                  label: Text('打開 Google Maps', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16)),
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
                    );
                    if (!context.mounted) return;
                    if (errorMsg != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
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