import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/bus_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../services/bus_api_service.dart';
import '../routing/open_route_planner.dart';
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

class ElderlyMoreScreen extends StatelessWidget {
  const ElderlyMoreScreen({super.key});

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
              icon: Icons.directions,
              title: lang.tr('routing_title'),
              onTap: () => openRoutePlanner(context),
            ),
            _MoreCard(
              icon: Icons.star_outline,
              title: lang.tr('routes_special'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _SpecialRoutesPage()),
              ),
            ),
            _MoreCard(
              icon: Icons.warning_amber_rounded,
              title: lang.tr('elderly_diversion'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _DiversionPage()),
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
              icon: Icons.info_outline,
              title: lang.tr('timetable'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _SourceNotesPage()),
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
                        context.read<LanguageController>().tr('elderly_list_empty'),
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

class _SourceNotesPage extends StatelessWidget {
  const _SourceNotesPage();

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : const Color(0xFF111111);
    final style = TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w700, height: 1.4);
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
                icon: Icon(Icons.arrow_back, color: fg),
              ),
            ),
            Text(
              lang.tr('timetable'),
              softWrap: true,
              style: TextStyle(color: fg, fontSize: 32, fontWeight: FontWeight.w800, height: 1.2),
            ),
            const SizedBox(height: 20),
            Text(lang.tr('timetable_source_note'), softWrap: true, style: style),
            const SizedBox(height: 20),
            Text(lang.tr('route_shape_source_note'), softWrap: true, style: style),
          ],
        ),
      ),
    );
  }
}

class _DiversionPage extends StatefulWidget {
  const _DiversionPage();

  @override
  State<_DiversionPage> createState() => _DiversionPageState();
}

class _DiversionPageState extends State<_DiversionPage> {
  Future<RouteAlertsFetch>? _alerts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = context.read<BusController>().currentRoute;
    _alerts ??= route.isEmpty ? null : BusApiService.fetchRouteAlerts(route);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageController>();
    final busCtrl = context.watch<BusController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : const Color(0xFF111111);
    final route = busCtrl.currentRoute;
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
                lang.tr('elderly_diversion'),
                softWrap: true,
                style: TextStyle(color: fg, fontSize: 32, fontWeight: FontWeight.w800, height: 1.2),
              ),
            ),
            Expanded(
              child: route.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        lang.tr('elderly_pick_route'),
                        softWrap: true,
                        style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w700, height: 1.35),
                      ),
                    )
                  : FutureBuilder<RouteAlertsFetch>(
                      future: _alerts,
                      builder: (context, snapshot) {
                        final alerts = snapshot.data?.alerts ?? const <Map<String, dynamic>>[];
                        final closures = busCtrl.stopsList.where((stop) => stop.hasAlert).toList();
                        if (snapshot.connectionState == ConnectionState.waiting && alerts.isEmpty && closures.isEmpty) {
                          return const Center(child: CircularProgressIndicator(color: Colors.amber));
                        }
                        if (alerts.isEmpty && closures.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              lang.tr('elderly_no_diversion'),
                              softWrap: true,
                              style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w700, height: 1.35),
                            ),
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: [
                            for (final stop in closures) ...[
                              Text(
                                '${stop.seq}. ${stop.getLocalizedName(lang.currentLanguage)}',
                                softWrap: true,
                                style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w800, height: 1.3),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                lang.tr('elderly_stop_closed'),
                                softWrap: true,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => _DetourDetailPage(stopCode: stop.code, stopName: stop.getLocalizedName(lang.currentLanguage)),
                                    ),
                                  ),
                                  child: Text(lang.tr('elderly_diversion')),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                            for (final alert in alerts) ...[
                              Text(
                                (alert['title'] ?? lang.tr('route_notice')).toString(),
                                softWrap: true,
                                style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w800, height: 1.3),
                              ),
                              if ((alert['link'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FilledButton(
                                    onPressed: () async {
                                      final url = Uri.tryParse(alert['link'].toString());
                                      if (url == null) return;
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                    child: Text(lang.tr('open')),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                            ],
                          ],
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

class _DetourDetailPage extends StatefulWidget {
  const _DetourDetailPage({required this.stopCode, required this.stopName});

  final String stopCode;
  final String stopName;

  @override
  State<_DetourDetailPage> createState() => _DetourDetailPageState();
}

class _DetourDetailPageState extends State<_DetourDetailPage> {
  late final Future<Map<String, dynamic>?> _detail;

  @override
  void initState() {
    super.initState();
    final route = context.read<BusController>().currentRoute;
    final lang = context.read<LanguageController>().currentLanguage;
    _detail = BusApiService.fetchStopDetour(
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
