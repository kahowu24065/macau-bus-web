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

/// One row of the grouped route list: a section header (leading character)
/// or a route entry.
class _RouteRow {
  final String? header; // '★' (festival / special), '1'..'9', 'A'..'Z'
  final String routeNo;
  final String desc;
  const _RouteRow.header(String this.header) : routeNo = '', desc = '';
  const _RouteRow.route(this.routeNo, this.desc) : header = null;
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

class _RouteListScreenState extends State<RouteListScreen> {
  // 🌟 將 initState 徹底刪除，因為底部導航欄切換時唔會觸發 initState

  // Sections by leading character (1-9, then A-Z), recomputed only when the
  // route list object changes (BusController replaces the list on update).
  static const String _specialKey = '★';
  List<String>? _groupedSource;
  List<String>? _groupedSpecial;
  List<_RouteRow> _rows = const [];
  List<String> _sections = const [];
  Map<String, int> _sectionIndex = const {};
  final Map<String, GlobalKey> _headerKeys = {};
  final ScrollController _scroll = ScrollController();

  static const double _headerExtent = 34; // estimate, corrected after the jump
  static const double _tileExtent = 61;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _regroup(List<String> source, List<String> special) {
    if (identical(source, _groupedSource) && identical(special, _groupedSpecial)) return;
    final specialSet = special.map((e) => e.trim().toUpperCase()).toSet();
    final bySection = <String, List<_RouteRow>>{};
    for (final raw in source) {
      final parts = raw.toString().split('|');
      final routeNo = parts[0].trim().toUpperCase();
      if (routeNo.isEmpty) continue;
      final desc = parts.length > 1 ? parts.sublist(1).join('|').trim() : '';
      final section = specialSet.contains(routeNo) ? _specialKey : routeNo[0];
      bySection.putIfAbsent(section, () => []).add(_RouteRow.route(routeNo, desc));
    }
    final keys = bySection.keys.toList()
      ..sort((a, b) {
        if (a == _specialKey || b == _specialKey) return a == b ? 0 : (a == _specialKey ? -1 : 1);
        final da = RegExp(r'[0-9]').hasMatch(a), db = RegExp(r'[0-9]').hasMatch(b);
        if (da != db) return da ? -1 : 1;
        return a.compareTo(b);
      });
    final rows = <_RouteRow>[];
    final index = <String, int>{};
    for (final k in keys) {
      final list = bySection[k]!..sort((a, b) => compareRouteNo(a.routeNo, b.routeNo));
      index[k] = rows.length;
      rows.add(_RouteRow.header(k));
      rows.addAll(list);
      _headerKeys.putIfAbsent(k, () => GlobalKey());
    }
    _rows = rows;
    _sections = keys;
    _sectionIndex = index;
    _groupedSource = source;
    _groupedSpecial = special;
  }

  void _jumpTo(String section) {
    final idx = _sectionIndex[section];
    if (idx == null || !_scroll.hasClients) return;
    // Rough offset (rows before it), then snap exactly onto the header once built.
    var offset = 0.0;
    for (var i = 0; i < idx; i++) {
      offset += _rows[i].header != null ? _headerExtent : _tileExtent;
    }
    _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _headerKeys[section]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0, duration: Duration.zero);
    });
  }

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

    _regroup(busCtrl.allRoutesWithDir, busCtrl.specialRoutes);
    final rows = _rows;
    final dividerColor = isDark ? const Color(0xFF333333) : Colors.grey[300];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
              child: Container(
                color: isDark ? Colors.black.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.7),
                padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, _sections.length > 1 ? 10 : 16),
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
                    if (_sections.length > 1) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 28,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _sections.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, i) {
                            final s = _sections[i];
                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _jumpTo(s),
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 28),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                ),
                                child: Text(s, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
          Expanded(
            child: rows.isEmpty 
              ? const Center(child: CircularProgressIndicator(color: Colors.amber)) 
              : ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.only(
                    top: 0,
                    bottom: 8 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row.header != null) {
                      return Container(
                        key: _headerKeys[row.header],
                        height: _headerExtent,
                        alignment: Alignment.bottomLeft,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 5),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.amber.withValues(alpha: 0.06),
                          border: Border(bottom: BorderSide(color: Colors.amber.withValues(alpha: 0.35), width: 1)),
                        ),
                        child: Text(
                          row.header == _specialKey ? '★ ${langCtrl.tr('routes_special')}' : row.header!,
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                        ),
                      );
                    }
                    final routeNo = row.routeNo;
                    // 如果有第二部分，就直接顯示 Server 回傳嘅內容（即係翻譯好嘅字）；冇嘅話先用預設字眼
                    final routeDesc = row.desc.isNotEmpty ? row.desc : langCtrl.tr('macau_bus_route_desc');
                    final nextIsRoute = index + 1 < rows.length && rows[index + 1].header == null;

                    final tile = ListTile(
                      dense: true, 
                      leading: CircleAvatar(backgroundColor: Colors.amber.withValues(alpha: 0.2), child: Text(routeNo, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12))), 
                      title: Text(routeNo, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 15)), 
                      subtitle: Text(routeDesc, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13)), 
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18), 
                      onTap: () { 
                        context.read<BusController>().setRoute(routeNo);
                        context.read<BusController>().fetchStops();
                        context.read<NavigationController>().changeTab(2);
                      }
                    );
                    if (!nextIsRoute) return tile;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [tile, Divider(height: 1, color: dividerColor)],
                    );
                  }
                ),
          ),
        ],
      ),
    );
  }
}
