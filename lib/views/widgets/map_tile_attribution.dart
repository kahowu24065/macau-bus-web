import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/map_tiles.dart';

/// Credit line for the basemap that is actually on screen.
class MapTileAttribution extends StatefulWidget {
  const MapTileAttribution({super.key, required this.credit});

  final MapTileCredit credit;

  @override
  State<MapTileAttribution> createState() => _MapTileAttributionState();
}

class _MapTileAttributionState extends State<MapTileAttribution> {
  late final TapGestureRecognizer _host;
  late final TapGestureRecognizer _openMapTiles;
  late final TapGestureRecognizer _openStreetMap;

  @override
  void initState() {
    super.initState();
    _host = TapGestureRecognizer()..onTap = _openHost;
    _openMapTiles = TapGestureRecognizer()
      ..onTap = () => _open(MapTiles.openMapTilesTerms);
    _openStreetMap = TapGestureRecognizer()
      ..onTap = () => _open(MapTiles.openStreetMapCopyright);
  }

  @override
  void dispose() {
    _host.dispose();
    _openMapTiles.dispose();
    _openStreetMap.dispose();
    super.dispose();
  }

  void _openHost() {
    final url = switch (widget.credit) {
      MapTileCredit.openFreeMap => MapTiles.openFreeMapTerms,
      MapTileCredit.mierune => MapTiles.mieruneTerms,
    };
    _open(url);
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 10, height: 1.25, color: Colors.black87);
    final link = style.copyWith(decoration: TextDecoration.underline);
    final host = switch (widget.credit) {
      MapTileCredit.openFreeMap => '© OpenFreeMap',
      MapTileCredit.mierune => '© MIERUNE Inc.',
    };
    return Material(
      color: Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(4),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(text: host, style: link, recognizer: _host),
                const TextSpan(text: ' '),
                TextSpan(
                  text: '© OpenMapTiles',
                  style: link,
                  recognizer: _openMapTiles,
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: '© OpenStreetMap contributors',
                  style: link,
                  recognizer: _openStreetMap,
                ),
              ],
            ),
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    );
  }
}
