import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/bus_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../services/bus_api_service.dart';
import '../widgets/fare_dialog.dart';

class RouteCatalogLine {
  const RouteCatalogLine(this.code, this.description);

  final String code;
  final String description;

  static List<RouteCatalogLine> parse(List<String> raw) {
    final lines = <RouteCatalogLine>[];
    for (final item in raw) {
      final parts = item.split('|');
      final code = parts.first.trim();
      if (code.isEmpty) continue;
      final description = parts.length > 1 ? parts.sublist(1).join('|').trim() : '';
      lines.add(RouteCatalogLine(code, description));
    }
    return lines;
  }
}

void openBusRoute(BuildContext context, String routeNo) {
  final busCtrl = context.read<BusController>();
  final navCtrl = context.read<NavigationController>();
  busCtrl.setRoute(routeNo);
  busCtrl.fetchStops();
  navCtrl.clearNavigation();
  navCtrl.changeTab(2);
  Navigator.of(context).popUntil((route) => route.isFirst);
}

class EasyReadMoreScreen extends StatelessWidget {
  const EasyReadMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                iconSize: 32,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            Text(
              lang.tr('more_options'),
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF111111),
                fontSize: 32,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            _MoreCard(
              icon: Icons.star_outline,
              title: lang.tr('routes_special'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _SpecialRoutesPage()),
              ),
            ),
            _MoreCard(
              icon: Icons.list_alt,
              title: lang.tr('all_routes_title'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _AllRoutesPage()),
              ),
            ),
            _MoreCard(
              icon: Icons.monetization_on_outlined,
              title: lang.tr('fare_table'),
              onTap: () => showBusFareDialog(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreCard extends StatelessWidget {
  const _MoreCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : const Color(0xFF111111);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: fg, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: fg, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    softWrap: true,
                    style: TextStyle(
                      color: fg,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteListPage extends StatelessWidget {
  const _RouteListPage({required this.title, required this.lines});

  final String title;
  final List<RouteCatalogLine> lines;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : const Color(0xFF111111);
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              iconSize: 32,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back, color: fg),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                title,
                softWrap: true,
                style: TextStyle(color: fg, fontSize: 28, fontWeight: FontWeight.w800, height: 1.25),
              ),
            ),
            Expanded(
              child: lines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        context.read<LanguageController>().tr('easy_read_list_empty'),
                        softWrap: true,
                        style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w700, height: 1.35),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: lines.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        return Material(
                          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: fg, width: 2),
                          ),
                          child: InkWell(
                            onTap: () => openBusRoute(context, line.code),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.code,
                                    softWrap: true,
                                    style: TextStyle(color: fg, fontSize: 28, fontWeight: FontWeight.w800),
                                  ),
                                  if (line.description.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      line.description,
                                      softWrap: true,
                                      style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w700, height: 1.35),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllRoutesPage extends StatelessWidget {
  const _AllRoutesPage();

  @override
  Widget build(BuildContext context) {
    final busCtrl = context.watch<BusController>();
    final lang = context.watch<LanguageController>();
    return _RouteListPage(
      title: lang.tr('all_routes_title'),
      lines: RouteCatalogLine.parse(busCtrl.allRoutesWithDir),
    );
  }
}

class _SpecialRoutesPage extends StatelessWidget {
  const _SpecialRoutesPage();

  @override
  Widget build(BuildContext context) {
    final busCtrl = context.watch<BusController>();
    final lang = context.watch<LanguageController>();
    final special = busCtrl.specialRoutes.map((e) => e.trim().toUpperCase()).toSet();
    final fromCatalog = RouteCatalogLine.parse(busCtrl.allRoutesWithDir)
        .where((line) => special.contains(line.code.toUpperCase()))
        .toList();
    final known = fromCatalog.map((line) => line.code.toUpperCase()).toSet();
    final extra = [
      for (final code in busCtrl.specialRoutes)
        if (!known.contains(code.trim().toUpperCase()) && code.trim().isNotEmpty)
          RouteCatalogLine(code.trim(), ''),
    ];
    return _RouteListPage(
      title: lang.tr('routes_special'),
      lines: [...fromCatalog, ...extra],
    );
  }
}

/// One stop's diversion notice: suspended stops and temporary replacements.
class StopDetourDetailPage extends StatefulWidget {
  const StopDetourDetailPage({
    super.key,
    required this.stopCode,
    required this.stopName,
  });

  final String stopCode;
  final String stopName;

  /// Tests supply a notice here so the page does not call the network.
  static Future<Map<String, dynamic>?> Function({
    required String route,
    required String stationCode,
    required String lang,
  })? debugLoad;

  @override
  State<StopDetourDetailPage> createState() => _StopDetourDetailPageState();
}

class _StopDetourDetailPageState extends State<StopDetourDetailPage> {
  late final Future<Map<String, dynamic>?> _detail;

  @override
  void initState() {
    super.initState();
    final route = context.read<BusController>().currentRoute;
    final lang = context.read<LanguageController>().currentLanguage;
    final load = StopDetourDetailPage.debugLoad;
    _detail = load != null
        ? load(route: route, stationCode: widget.stopCode, lang: lang)
        : BusApiService.fetchStopDetour(
            route: route,
            stationCode: widget.stopCode,
            lang: lang,
          );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : const Color(0xFF111111);
    final style = TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w700, height: 1.4);
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _detail,
          builder: (context, snapshot) {
            final info = snapshot.data;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    iconSize: 32,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: fg),
                  ),
                ),
                Text(
                  widget.stopName,
                  softWrap: true,
                  style: TextStyle(color: fg, fontSize: 28, fontWeight: FontWeight.w800, height: 1.25),
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: Colors.amber)),
                  )
                else if (info == null)
                  Text(
                    lang.tr('stop_warning_body').replaceAll('@stop', widget.stopName),
                    softWrap: true,
                    style: style,
                  )
                else ...[
                  if ((info['title'] ?? '').toString().isNotEmpty)
                    Text(info['title'].toString(), softWrap: true, style: style),
                  if ((info['time'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(info['time'].toString(), softWrap: true, style: style),
                  ],
                  if (info['suspendStops'] is List && (info['suspendStops'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(lang.tr('suspended_stops'), softWrap: true, style: const TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3)),
                    for (final stop in info['suspendStops'] as List) ...[
                      const SizedBox(height: 6),
                      Text('$stop', softWrap: true, style: style),
                    ],
                  ],
                  if (info['alternativeStops'] is List && (info['alternativeStops'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(lang.tr('temp_alt_stops'), softWrap: true, style: const TextStyle(color: Colors.green, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3)),
                    for (final stop in info['alternativeStops'] as List) ...[
                      const SizedBox(height: 6),
                      Text('$stop', softWrap: true, style: style),
                    ],
                  ],
                  if ((info['provider'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(info['provider'].toString(), softWrap: true, style: style),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
