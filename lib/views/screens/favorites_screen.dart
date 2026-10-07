import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/bus_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/language_controller.dart';
import '../../utils/elderly_access.dart';
import '../widgets/preserve_chrome.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  /// Last language we already requested routes for.
  /// Prevents re-fetch on every BusController notify (ETA etc.) while
  /// still refreshing when the user switches language.
  String? _fetchedForLang;

  void _ensureRoutesForLang(String lang) {
    if (_fetchedForLang == lang) return;
    _fetchedForLang = lang;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BusController>().fetchAllRoutes(lang: lang);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Still watch BusController — favorite list / route dirs must update.
    final busCtrl = context.watch<BusController>();
    final lang = context.select<LanguageController, String>(
      (c) => c.currentLanguage,
    );
    final langCtrl = context.read<LanguageController>();

    // Fetch once per language (not on every rebuild).
    _ensureRoutesForLang(lang);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          PreserveChrome(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
              child: Container(
                color: isDark ? Colors.black.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.7),
                padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 16),
                child: Center(
                  child: Text(
                    langCtrl.tr('fav_routes_title'),
                    style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
          ),
          Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
          Expanded(
            child: busCtrl.favoriteRoutes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_border, size: 64, color: isDark ? Colors.white24 : Colors.black26),
                      const SizedBox(height: 16),
                      Text(langCtrl.tr('no_fav_routes'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 16, height: 1.5)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    12 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: busCtrl.favoriteRoutes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return Material(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: _FavoriteRouteRow(
                        route: busCtrl.favoriteRoutes[index],
                        isDark: isDark,
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteRouteRow extends StatelessWidget {
  final String route;
  final bool isDark;

  const _FavoriteRouteRow({required this.route, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final busCtrl = context.read<BusController>();
    final langCtrl = context.read<LanguageController>();
    final elderly = ElderlyAccess.enabled(context);

    String routeDesc = langCtrl.tr('unknown_dir');
    for (final r in busCtrl.allRoutesWithDir) {
      final parts = r.split('|');
      final code = parts.isNotEmpty ? parts[0].trim() : '';
      if (code.toUpperCase() == route.toUpperCase() && parts.length > 1 && parts[1].trim().isNotEmpty) {
        routeDesc = parts[1].trim();
        break;
      }
    }

    return InkWell(
      onTap: () {
        busCtrl.setRoute(route);
        busCtrl.fetchStops();
        context.read<NavigationController>().changeTab(2);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: elderly ? 16 : 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 52),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2E) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
              ),
              alignment: Alignment.center,
              child: Text(
                route,
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                routeDesc,
                softWrap: true,
                style: TextStyle(
                  color: elderly
                      ? (isDark ? Colors.white : const Color(0xFF111111))
                      : (isDark ? const Color(0xFFC7C7CC) : Colors.black54),
                  fontSize: elderly ? 16 : 13,
                  fontWeight: elderly ? FontWeight.w700 : FontWeight.normal,
                  height: 1.3,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.star, color: Colors.amber, size: 22),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => busCtrl.toggleFavorite(route),
            ),
          ],
        ),
      ),
    );
  }
}
