import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/bus_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/language_controller.dart';

class RouteListScreen extends StatefulWidget {
  const RouteListScreen({super.key});

  @override
  State<RouteListScreen> createState() => _RouteListScreenState();
}

/// Natural route-number order: digit runs compare numerically, letter runs
/// lexicographically, a shorter prefix first (1 < 1A < 10 < 101X,
/// 3 < 3A < 3AS < 3AX < 3X, 17S < 17S1).
int compareRouteNo(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final ta = re.allMatches(a.toUpperCase()).map((m) => m.group(0)!).toList();
  final tb = re.allMatches(b.toUpperCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < ta.length && i < tb.length; i++) {
    final x = ta[i], y = tb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    int c;
    if (nx != null && ny != null) {
      c = nx.compareTo(ny);
    } else if (nx != null) {
      c = -1; // digits before letters
    } else if (ny != null) {
      c = 1;
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  return ta.length.compareTo(tb.length);
}

class _RouteEntry {
  final String routeNo;
  final String desc;
  const _RouteEntry(this.routeNo, this.desc);
}

/// Route categories: '★' (special / festival services, from the server's
/// specialRoutes), then one per leading character ('1'..'9', 'A'..'Z').
/// Computed once per route-list / special-list object (BusController replaces
/// the lists on update), shared by the category list and the sub-pages.
class _RouteGroups {
  static const String special = '★';
  static List<String>? _src;
  static List<String>? _srcSpecial;
  static List<String> _keys = const [];
  static Map<String, List<_RouteEntry>> _byKey = const {};

  static void _ensure(List<String> source, List<String> specialRoutes) {
    if (identical(source, _src) && identical(specialRoutes, _srcSpecial)) return;
    final specialSet = specialRoutes.map((e) => e.trim().toUpperCase()).toSet();
    final by = <String, List<_RouteEntry>>{};
    for (final raw in source) {
      final parts = raw.toString().split('|');
      final routeNo = parts[0].trim().toUpperCase();
      if (routeNo.isEmpty) continue;
      final desc = parts.length > 1 ? parts.sublist(1).join('|').trim() : '';
      final key = specialSet.contains(routeNo) ? special : routeNo[0];
      by.putIfAbsent(key, () => []).add(_RouteEntry(routeNo, desc));
    }
    for (final l in by.values) {
      l.sort((a, b) => compareRouteNo(a.routeNo, b.routeNo));
    }
    final digit = RegExp(r'[0-9]');
    _keys = by.keys.toList()
      ..sort((a, b) {
        if (a == special || b == special) return a == b ? 0 : (a == special ? -1 : 1);
        final da = digit.hasMatch(a), db = digit.hasMatch(b);
        if (da != db) return da ? -1 : 1;
        return a.compareTo(b);
      });
    _byKey = by;
    _src = source;
    _srcSpecial = specialRoutes;
  }

  static List<String> keys(BusController c) {
    _ensure(c.allRoutesWithDir, c.specialRoutes);
    return _keys;
  }

  static List<_RouteEntry> routes(BusController c, String key) {
    _ensure(c.allRoutesWithDir, c.specialRoutes);
    return _byKey[key] ?? const [];
  }
}

String _categoryTitle(LanguageController lang, String key) => key == _RouteGroups.special
    ? lang.tr('routes_special')
    : lang.tr('routes_starting_with').replaceAll('{c}', key);

Widget _badge(String text) => CircleAvatar(
      backgroundColor: Colors.amber.withValues(alpha: 0.2),
      child: Text(text, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
    );

class _RouteListScreenState extends State<RouteListScreen> {
  // 🌟 將 initState 徹底刪除，因為底部導航欄切換時唔會觸發 initState

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final busCtrl = context.watch<BusController>();
    final langCtrl = context.watch<LanguageController>();

    // 🌟 關鍵修復：將拉取資料嘅檢查放喺 build 入面
    // 當 langCtrl 改變 (用家轉語言)，呢個畫面會自動 rebuild，然後觸發呢度。
    // BusController 內部已經有檢查機制，如果語言冇變係會自動 return，唔會浪費 API！
    WidgetsBinding.instance.addPostFrameCallback((_) {
      busCtrl.fetchAllRoutes(lang: langCtrl.currentLanguage); 
    });

    final keys = _RouteGroups.keys(busCtrl);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
              child: Container(
                color: isDark ? Colors.black.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.7),
                padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(
                      child: Text(
                        langCtrl.tr('all_routes_title'), 
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black, 
                          fontSize: 18, 
                          fontWeight: FontWeight.bold
                        )
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
          Expanded(
            child: keys.isEmpty 
              ? const Center(child: CircularProgressIndicator(color: Colors.amber)) 
              : ListView.separated(
                  padding: EdgeInsets.only(
                    top: 8,
                    bottom: 8 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: keys.length, 
                  separatorBuilder: (c, i) => Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]), 
                  itemBuilder: (context, index) {
                    final key = keys[index];
                    final count = _RouteGroups.routes(busCtrl, key).length;
                    return ListTile(
                      dense: true, 
                      leading: _badge(key), 
                      title: Text(_categoryTitle(langCtrl, key), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 15)), 
                      subtitle: Text(langCtrl.tr('routes_count').replaceAll('{n}', '$count'), style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13)), 
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18), 
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => _RouteCategoryPage(categoryKey: key)),
                      ),
                    );
                  }
                ),
          ),
        ],
      ),
    );
  }
}

/// Routes of one category, natural-sorted, in the existing route-row style.
class _RouteCategoryPage extends StatelessWidget {
  final String categoryKey;
  const _RouteCategoryPage({required this.categoryKey});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final busCtrl = context.watch<BusController>();
    final langCtrl = context.watch<LanguageController>();
    final routes = _RouteGroups.routes(busCtrl, categoryKey);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Column(
        children: [
          Container(
            color: isDark ? Colors.black.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.7),
            padding: EdgeInsets.fromLTRB(4, MediaQuery.of(context).padding.top + 4, 4, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.amber, size: 20),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    _categoryTitle(langCtrl, categoryKey),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 48), // balances the back button so the title stays centred
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.paddingOf(context).bottom),
              itemCount: routes.length,
              separatorBuilder: (c, i) => Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),
              itemBuilder: (context, index) {
                final r = routes[index];
                // 如果有第二部分，就直接顯示 Server 回傳嘅內容（即係翻譯好嘅字）；冇嘅話先用預設字眼
                final routeDesc = r.desc.isNotEmpty ? r.desc : langCtrl.tr('macau_bus_route_desc');
                return ListTile(
                  dense: true, 
                  leading: _badge(r.routeNo), 
                  title: Text(r.routeNo, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 15)), 
                  subtitle: Text(routeDesc, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13)), 
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18), 
                  onTap: () { 
                    final bus = context.read<BusController>();
                    final nav = context.read<NavigationController>();
                    Navigator.of(context).pop();
                    bus.setRoute(r.routeNo);
                    bus.fetchStops();
                    nav.changeTab(2);
                  }
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
