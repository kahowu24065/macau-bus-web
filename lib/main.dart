import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const MacauBusApp());
}

class MacauBusApp extends StatelessWidget {
  const MacauBusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '澳門巴士實時報站與地圖',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum BusDirection { outbound, inbound }

class _HomeScreenState extends State<HomeScreen> {
  // 本地/遠端伺服器 URL (建議本地測試使用 http://localhost:3000)
  static const String baseUrl = 'https://macau-bus-api.onrender.com';

  final TextEditingController _routeController = TextEditingController(text: '2');
  final MapController _mapController = MapController();

  List<dynamic> _stopsList = [];
  List<dynamic> _allBusesList = []; // 全線即時巴士位置列表
  List<String> _suggestedRoutes = []; // 搜尋建議列表
  bool _showSuggestions = false;       // 是否顯示下拉選單

  int? _selectedStopSeq;
  BusDirection _selectedDirection = BusDirection.outbound;

  String _outboundTerminal = '去程';
  String _inboundTerminal = '回程';

  bool _isLoadingStops = false;
  bool _isLoadingETA = false;
  
  Map<String, dynamic>? _etaData;
  String? _errorMessage;

  Timer? _debounceTimer;
  Timer? _autoRefreshTimer;
  int _countdownSeconds = 10;

  List<String> _favoriteRoutes = [];
  int _currentBottomNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _fetchStops();
  }

  @override
  void dispose() {
    _routeController.dispose();
    _mapController.dispose();
    _debounceTimer?.cancel();
    _stopAutoRefresh();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favoriteRoutes = prefs.getStringList('favorite_routes') ?? [];
    });
  }

  Future<void> _toggleFavorite(String route) async {
    final cleanRoute = route.trim().toUpperCase();
    if (cleanRoute.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteRoutes.contains(cleanRoute)) {
        _favoriteRoutes.remove(cleanRoute);
      } else {
        _favoriteRoutes.add(cleanRoute);
      }
    });
    await prefs.setStringList('favorite_routes', _favoriteRoutes);
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  void _startAutoRefresh() {
    _stopAutoRefresh();
    setState(() {
      _countdownSeconds = 10;
    });

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() {
          _countdownSeconds--;
        });
      } else {
        setState(() {
          _countdownSeconds = 10;
        });
        _getBusETA(isAutoRefresh: true);
      }
    });
  }

  String _formatStopName(dynamic raw) {
    if (raw == null) return '';
    String name = raw.toString().trim();
    if (name.isEmpty) return '';

    final cleanName = name.replaceAll(RegExp(r'^[A-Z0-9/_\-\s]+'), '').trim();
    return cleanName.isNotEmpty ? cleanName : name;
  }

  // 計算路線的中心座標點
  LatLng get _mapCenter {
    final points = _routePoints;
    if (points.isNotEmpty) {
      double sumLat = 0;
      double sumLng = 0;
      for (var p in points) {
        sumLat += p.latitude;
        sumLng += p.longitude;
      }
      return LatLng(sumLat / points.length, sumLng / points.length);
    }
    return const LatLng(22.1987, 113.5439); // 澳門預設中心點
  }

  // 取得有效站點的經緯度點位 (以繪製地圖路線軌跡 Polyline)
  List<LatLng> get _routePoints {
    List<LatLng> points = [];
    for (var stop in _stopsList) {
      final double lat = (stop['lat'] as num?)?.toDouble() ?? 0.0;
      final double lng = (stop['lng'] as num?)?.toDouble() ?? 0.0;
      if (lat != 0.0 && lng != 0.0) {
        points.add(LatLng(lat, lng));
      }
    }
    return points;
  }

  // 1. 搜尋輸入時觸發：獲取關鍵字建議
  void _onRouteChanged(String value) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final input = value.trim();
      if (input.isNotEmpty) {
        try {
          final res = await http.get(Uri.parse('$baseUrl/api/search-routes?q=$input'));
          final json = jsonDecode(res.body);
          if (json['success'] == true) {
            setState(() {
              _suggestedRoutes = List<String>.from(json['routes']);
              _showSuggestions = _suggestedRoutes.isNotEmpty;
            });
          }
        } catch (_) {}
      } else {
        setState(() {
          _suggestedRoutes = [];
          _showSuggestions = false;
        });
      }
    });
  }

  // 2. 點擊下拉選單的路線項目
  void _selectSuggestedRoute(String route) {
    _routeController.text = route;
    setState(() {
      _showSuggestions = false;
      _suggestedRoutes = [];
    });
    _fetchStops();
  }

  Future<void> _fetchStops() async {
    final route = _routeController.text.trim();
    if (route.isEmpty) return;

    _stopAutoRefresh();

    setState(() {
      _showSuggestions = false;
      _isLoadingStops = true;
      _stopsList = [];
      _allBusesList = [];
      _selectedStopSeq = null;
      _errorMessage = null;
      _etaData = null;
    });

    try {
      final outboundFuture = http
          .get(Uri.parse('$baseUrl/api/bus-stops?route=$route&dir=0'))
          .timeout(const Duration(seconds: 30));
      final inboundFuture = http
          .get(Uri.parse('$baseUrl/api/bus-stops?route=$route&dir=1'))
          .timeout(const Duration(seconds: 30));

      final results = await Future.wait([outboundFuture, inboundFuture]);

      final outboundJson = jsonDecode(results[0].body);
      final inboundJson = jsonDecode(results[1].body); // 👈 確實為 results.body

      List<dynamic> outboundStops = outboundJson['success'] == true ? (outboundJson['stops'] ?? []) : [];
      List<dynamic> inboundStops = inboundJson['success'] == true ? (inboundJson['stops'] ?? []) : [];

      String newOutboundTerminal = '去程';
      String newInboundTerminal = '回程';

      if (outboundStops.isNotEmpty) {
        final outFirstName = _formatStopName(outboundStops.first['name']);
        final outLastName = _formatStopName(outboundStops.last['name']);

        newOutboundTerminal = outLastName;

        if (inboundStops.isNotEmpty) {
          final inLastName = _formatStopName(inboundStops.last['name']);
          newInboundTerminal = (inLastName != outLastName && inLastName.isNotEmpty) ? inLastName : (outFirstName.isNotEmpty ? outFirstName : '回程');
        } else {
          newInboundTerminal = outFirstName.isNotEmpty ? outFirstName : '回程';
        }
      }

      final currentDirValue = _selectedDirection == BusDirection.outbound ? 0 : 1;
      final activeJson = currentDirValue == 0 ? outboundJson : inboundJson;

      if (activeJson['success'] == true && (activeJson['stops'] as List).isNotEmpty) {
        final List<dynamic> fetchedStops = activeJson['stops'];
        setState(() {
          _stopsList = fetchedStops;
          if (_stopsList.isNotEmpty) {
            _selectedStopSeq = _stopsList[0]['seq'];
          }
          _outboundTerminal = newOutboundTerminal;
          _inboundTerminal = newInboundTerminal;
          _isLoadingStops = false;
        });

        // 動態聚焦移動地圖至路線中心
        if (_routePoints.isNotEmpty) {
          try {
            _mapController.move(_mapCenter, 13.5);
          } catch (_) {}
        }

        _getBusETA();
      } else {
        setState(() {
          _isLoadingStops = false;
          _outboundTerminal = newOutboundTerminal;
          _inboundTerminal = newInboundTerminal;
          _errorMessage = activeJson['message'] ?? '查無此路線或方向之站點';
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingStops = false;
        _errorMessage = '連線伺服器逾時，請點擊重試 (或嘗試本地執行 server.js)';
      });
    }
  }

  Future<void> _getBusETA({bool isAutoRefresh = false}) async {
    final route = _routeController.text.trim();
    if (route.isEmpty) return;

    if (_stopsList.isEmpty && !isAutoRefresh) {
      _fetchStops();
      return;
    }

    if (!isAutoRefresh) {
      setState(() {
        _isLoadingETA = true;
        _errorMessage = null;
      });
    }

    try {
      final dirValue = _selectedDirection == BusDirection.outbound ? 0 : 1;
      final seqParam = _selectedStopSeq != null ? '&targetStopSeq=$_selectedStopSeq' : '';
      final uri = Uri.parse('$baseUrl/api/bus-eta?route=$route&dir=$dirValue$seqParam');
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      final jsonResponse = jsonDecode(response.body);

      setState(() {
        _isLoadingETA = false;
        if (jsonResponse['success'] == true) {
          _etaData = jsonResponse['data'];
          _allBusesList = jsonResponse['allBuses'] ?? [];
          if (!isAutoRefresh) {
            _startAutoRefresh();
          }
        } else {
          _etaData = null;
          _allBusesList = [];
          _errorMessage = jsonResponse['message'] ?? '查詢失敗';
          _stopAutoRefresh();
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingETA = false;
        _etaData = null;
        _allBusesList = [];
        _errorMessage = '伺服器回應異常';
        _stopAutoRefresh();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _currentBottomNavIndex,
          children: [
            _buildBusRouteScreen(),
            _buildMapScreen(),
            _buildFavoritesScreen(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentBottomNavIndex,
        onTap: (index) {
          setState(() {
            _currentBottomNavIndex = index;
            _showSuggestions = false;
          });
        },
        backgroundColor: Colors.black,
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.directions_bus), label: '車站'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: '地圖'),
          BottomNavigationBarItem(icon: Icon(Icons.star), label: '收藏'),
        ],
      ),
    );
  }

  // 1. 車站與 ETA 列表頁面
  Widget _buildBusRouteScreen() {
    final currentRoute = _routeController.text.trim().toUpperCase();
    final isFavorite = _favoriteRoutes.contains(currentRoute);
    final currentTerminal = _selectedDirection == BusDirection.outbound ? _outboundTerminal : _inboundTerminal;

    return Stack(
      children: [
        Column(
          children: [
            // 頂部搜尋與路線資訊列
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _routeController,
                            onChanged: _onRouteChanged,
                            onSubmitted: (_) => _fetchStops(),
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                            decoration: InputDecoration(
                              hintText: '輸入路線 (例如 2)',
                              hintStyle: const TextStyle(color: Colors.grey),
                              prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                              suffixIcon: _isLoadingStops
                                  ? Transform.scale(scale: 0.4, child: const CircularProgressIndicator(color: Colors.amber))
                                  : null,
                              filled: true,
                              fillColor: const Color(0xFF222222),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 快捷地圖按鈕
                      IconButton(
                        icon: const Icon(Icons.map, color: Colors.amber),
                        tooltip: '在地圖查看路線',
                        onPressed: () {
                          setState(() {
                            _currentBottomNavIndex = 1;
                            _showSuggestions = false;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 路線名稱與切換方向
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDirection = _selectedDirection == BusDirection.outbound
                                ? BusDirection.inbound
                                : BusDirection.outbound;
                          });
                          _fetchStops();
                        },
                        child: const Column(
                          children: [
                            Icon(Icons.swap_calls, color: Colors.white),
                            SizedBox(height: 2),
                            Text('對頭線', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),

                      Column(
                        children: [
                          Text(
                            currentRoute.isEmpty ? '---' : currentRoute,
                            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                          ),
                          Text(
                            '往 $currentTerminal',
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),

                      InkWell(
                        onTap: () => _toggleFavorite(currentRoute),
                        child: Column(
                          children: [
                            Icon(
                              isFavorite ? Icons.star : Icons.star_border,
                              color: isFavorite ? Colors.amber : Colors.white,
                            ),
                            const SizedBox(height: 2),
                            Text('收藏', style: TextStyle(color: isFavorite ? Colors.amber : Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFF333333)),

            // 站點時間軸清單
            Expanded(
              child: _isLoadingStops
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.amber),
                          SizedBox(height: 16),
                          Text('正連線至伺服器讀取站點...', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _fetchStops,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                                child: const Text('重試連線', style: TextStyle(color: Colors.black)),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _stopsList.length,
                          itemBuilder: (context, index) {
                            final stop = _stopsList[index];
                            final seq = stop['seq'];
                            final stopName = _formatStopName(stop['name']);
                            final stopCode = stop['code'] ?? '';
                            final isSelected = _selectedStopSeq == seq;

                            return Column(
                              children: [
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedStopSeq = seq;
                                      _showSuggestions = false;
                                    });
                                    _getBusETA();
                                  },
                                  child: Container(
                                    color: isSelected ? const Color(0xFF222222) : Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 4,
                                          height: 36,
                                          color: isSelected ? Colors.amber : Colors.transparent,
                                        ),
                                        const SizedBox(width: 12),

                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '$seq. $stopName ${stopCode.isNotEmpty ? "($stopCode)" : ""}',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              const Text('車費: \$6.0', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                            ],
                                          ),
                                        ),

                                        if (isSelected)
                                          _isLoadingETA
                                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber))
                                              : Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      _etaData != null ? '${_etaData!['status']}' : '點擊更新',
                                                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15),
                                                    ),
                                                    if (_autoRefreshTimer != null)
                                                      Text('$_countdownSeconds 秒後更新', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                                  ],
                                                ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Divider(height: 1, color: Color(0xFF222222)),
                              ],
                            );
                          },
                        ),
            ),
          ],
        ),

        // 即時搜尋建議下拉清單
        if (_showSuggestions)
          Positioned(
            top: 50,
            left: 16,
            right: 60,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF2A2A2A),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _suggestedRoutes.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFF383838)),
                  itemBuilder: (context, index) {
                    final routeOption = _suggestedRoutes[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.directions_bus, color: Colors.amber, size: 18),
                      title: Text(
                        routeOption,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      onTap: () => _selectSuggestedRoute(routeOption),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  // 2. 實時地圖與巴士路線圖頁面 (功能 1: 站點標記, 功能 2: 路線軌跡 Polyline, 功能 4: 車牌與車速標記)
  Widget _buildMapScreen() {
    final currentRoute = _routeController.text.trim().toUpperCase();
    final currentTerminal = _selectedDirection == BusDirection.outbound ? _outboundTerminal : _inboundTerminal;
    final points = _routePoints;

    // 若在地圖頁面時站點為空，自動觸發一次數據載入
    if (_stopsList.isEmpty && !_isLoadingStops && _errorMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchStops();
      });
    }

    // 1. 站點標記 (Station Markers)
    final List<Marker> stopMarkers = [];
    for (var stop in _stopsList) {
      final double lat = (stop['lat'] as num?)?.toDouble() ?? 0.0;
      final double lng = (stop['lng'] as num?)?.toDouble() ?? 0.0;
      final seq = stop['seq'];
      final name = _formatStopName(stop['name']);

      if (lat != 0.0 && lng != 0.0) {
        stopMarkers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 24,
            height: 24,
            child: GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('站點 $seq: $name'), duration: const Duration(seconds: 2)),
                );
              },
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.blueAccent,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$seq',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // 4. 實時巴士動態標記 (包含真實 GPS 座標、車牌號碼、即時車速)
    final List<Marker> busMarkers = [];
    for (var bus in _allBusesList) {
      final double lat = (bus['lat'] as num?)?.toDouble() ?? 0.0;
      final double lng = (bus['lng'] as num?)?.toDouble() ?? 0.0;
      final String plate = bus['busLicense'] ?? '巴士';
      final speed = bus['speed'] ?? 0;

      if (lat != 0.0 && lng != 0.0) {
        busMarkers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 75,
            height: 48,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                  ),
                  child: Text(
                    '$plate\n${speed}km/h',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold, height: 1.0),
                  ),
                ),
                const Icon(Icons.directions_bus, color: Colors.amber, size: 20),
              ],
            ),
          ),
        );
      }
    }

    return Column(
      children: [
        // 頂部狀態列
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '路線 $currentRoute 往 $currentTerminal',
                style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.swap_calls, color: Colors.white),
                    tooltip: '切換方向',
                    onPressed: () {
                      setState(() {
                        _selectedDirection = _selectedDirection == BusDirection.outbound
                            ? BusDirection.inbound
                            : BusDirection.outbound;
                      });
                      _fetchStops();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.amber),
                    tooltip: '手動刷新',
                    onPressed: () {
                      if (_stopsList.isEmpty) {
                        _fetchStops();
                      } else {
                        _getBusETA();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // 地圖呈現區塊
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _mapCenter,
                  initialZoom: 13.5,
                ),
                children: [
                  // OpenStreetMap 地圖瓦片層
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.macau.bus_app',
                  ),

                  // 2. 巴士路線軌跡 (Polyline)
                  if (points.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: points,
                          strokeWidth: 5.0,
                          color: Colors.amber,
                        ),
                      ],
                    ),

                  // 1 & 4. 站點與實時巴士標記層 (Markers)
                  MarkerLayer(
                    markers: [
                      ...stopMarkers,
                      ...busMarkers,
                    ],
                  ),
                ],
              ),

              // 載入狀態 Overlay
              if (_isLoadingStops)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.amber),
                        SizedBox(height: 12),
                        Text('正連線伺服器載入路線與巴士實時位置...', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // 底部資訊卡
        Container(
          color: const Color(0xFF1E1E1E),
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('站點數: ${points.length}', style: const TextStyle(color: Colors.white)),
              Text('即時營運巴士: ${busMarkers.length} 輛', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              if (_stopsList.isEmpty && !_isLoadingStops)
                InkWell(
                  onTap: _fetchStops,
                  child: const Text('點擊重試連線', style: TextStyle(color: Colors.amber, decoration: TextDecoration.underline)),
                )
              else if (_autoRefreshTimer != null)
                Text('$_countdownSeconds 秒後更新', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  // 3. 收藏路線頁面
  Widget _buildFavoritesScreen() {
    return Column(
      children: [
        AppBar(
          title: const Text('⭐ 我的收藏路線'),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        Expanded(
          child: _favoriteRoutes.isEmpty
              ? const Center(child: Text('暫無收藏路線', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _favoriteRoutes.length,
                  itemBuilder: (context, index) {
                    final route = _favoriteRoutes[index];
                    return ListTile(
                      leading: const Icon(Icons.directions_bus, color: Colors.amber),
                      title: Text('巴士路線 $route', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () => _toggleFavorite(route),
                      ),
                      onTap: () {
                        _routeController.text = route;
                        setState(() {
                          _currentBottomNavIndex = 0;
                        });
                        _fetchStops();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}