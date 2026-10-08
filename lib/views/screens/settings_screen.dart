import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:flutter/services.dart' show rootBundle, Clipboard, ClipboardData;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/gps_service.dart';
import '../../controllers/purchase_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/bus_controller.dart';
import '../../controllers/background_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/easy_read_mode_controller.dart';
import '../../utils/easy_read_access.dart';
import '../widgets/preserve_chrome.dart';
import '../../services/open_data_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _defaultTabIndex = 0;
  String? _versionLabel;

  // 🌟 UI 顏色定義
  final Color _darkBase = const Color(0xFF0A0A0B);
  final Color _cardColor = const Color(0xFF161618);
  final Color _mutedWell = const Color(0xFF2A2A2E);
  final Color _subText = const Color(0xFF8A8A93);

  @override
  void initState() {
    super.initState();
    _loadDefaultTab();
    _loadPackageVersion();
  }

  Future<void> _loadPackageVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final version = info.version.split('+').first.trim();
      if (version.isEmpty) return;
      setState(() => _versionLabel = 'Version $version');
    } catch (_) {}
  }

  Future<void> _loadDefaultTab() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _defaultTabIndex = prefs.getInt('default_tab_index') ?? 0;
      });
    }
  }

  Future<String> _loadMarkdownContent(String filePrefix, String langCode) async {
    try {
      return await rootBundle.loadString('assets/i18n/${filePrefix}_$langCode.md');
    } catch (e) {
      try { return await rootBundle.loadString('assets/i18n/${filePrefix}_en.md'); } 
      catch (e2) {
        try { return await rootBundle.loadString('assets/i18n/${filePrefix}_zh.md'); } 
        catch (e3) { return 'Content not found.'; }
      }
    }
  }

  void _showMarkdownDialog(BuildContext context, bool isDark, LanguageController langCtrl, String titleKey, String filePrefix, IconData icon, Color iconColor) {
    final showAttribution = filePrefix == 'disclaimer';
    if (showAttribution) {
      unawaited(OpenDataConfig.instance.ensureLoaded(force: true));
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF161618) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 8),
            Expanded(child: Text(langCtrl.tr(titleKey), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18))),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<String>(
            future: _loadMarkdownContent(filePrefix, langCtrl.currentLanguage),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 100, child: Center(child: CupertinoActivityIndicator()));
              if (snapshot.hasError) return Text('Error\n${snapshot.error}', style: const TextStyle(color: Colors.redAccent));
              
              final bodyStyle = TextStyle(color: isDark ? const Color(0xFFD1D1D6) : Colors.black87, fontSize: 14, height: 1.5, fontFamily: 'Inter');
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarkdownBody(
                      data: snapshot.data ?? '',
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: bodyStyle,
                        h1: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Inter'),
                        h2: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Inter'),
                        listBullet: TextStyle(color: isDark ? Colors.amber : Colors.orange),
                      ),
                    ),
                    if (showAttribution) ...[
                      const SizedBox(height: 16),
                      ListenableBuilder(
                        listenable: OpenDataConfig.instance,
                        builder: (context, _) => Text(
                          OpenDataConfig.instance.attributionBlock(langCtrl.currentLanguage),
                          softWrap: true,
                          style: bodyStyle,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(langCtrl.tr('btn_close'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showActionSheet(BuildContext context, LanguageController langCtrl, {required String title, required List<Widget> actions}) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: Text(title, style: const TextStyle(fontFamily: 'Inter')),
        actions: actions,
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          isDefaultAction: true,
          child: Text(langCtrl.tr('cancel'), style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  Color get _readable {
    if (!EasyReadAccess.enabled(context)) return _subText;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? Colors.white : const Color(0xFF111111);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8, top: 24),
      child: Text(
        title.toUpperCase(),
        softWrap: true,
        style: TextStyle(color: _readable, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontFamily: 'Inter'),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children, bool isDark = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: isDark ? _cardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: children.asMap().entries.map((entry) {
            int idx = entry.key;
            Widget child = entry.value;
            return Column(
              children: [
                child,
                if (idx < children.length - 1)
                  Divider(height: 1, indent: 64, color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _settingsSwitch({
    required bool value,
    required bool isDark,
    required ValueChanged<bool> onChanged,
  }) {
    final control = CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: isDark ? Colors.white : Colors.black,
      inactiveTrackColor: _mutedWell,
      thumbColor: isDark ? Colors.black : Colors.white,
    );
    if (!EasyReadAccess.enabled(context)) return control;
    return Transform.scale(scale: 1.2, alignment: Alignment.centerRight, child: control);
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    String? trailingText,
    VoidCallback? onTap,
    bool isDark = true,
  }) {
    final easyRead = EasyReadAccess.enabled(context);
    final sub = _readable;
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: easyRead ? 12 : 4),
      onTap: onTap,
      splashColor: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06),
      hoverColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
      leading: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: isDark ? _mutedWell : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: isDark ? const Color(0xFFD1D1D6) : Colors.black87, size: 18),
      ),
      title: Text(title, softWrap: true, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15, fontWeight: easyRead ? FontWeight.w700 : FontWeight.w500, fontFamily: 'Inter')),
      subtitle: subtitle != null ? Text(subtitle, softWrap: true, style: TextStyle(color: sub, fontSize: 13, fontFamily: 'Inter', fontWeight: easyRead ? FontWeight.w700 : null, height: easyRead ? 1.35 : null)) : null,
      trailing: trailing ?? (trailingText != null 
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(trailingText, softWrap: true, style: TextStyle(color: sub, fontSize: 14, fontFamily: 'Inter')),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: sub, size: 18),
              ],
            ) 
          : Icon(Icons.chevron_right, color: sub, size: 18)),
    );
  }

  Widget _statusPill(bool isPro, LanguageController langCtrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isPro ? const Color(0xFF1A3B28) : _mutedWell,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPro) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF34C759),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0xFF34C759), blurRadius: 4)],
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            isPro ? langCtrl.tr('status_active') : langCtrl.tr('status_inactive'),
            style: TextStyle(
              color: isPro ? const Color(0xFF34C759) : _readable,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  static const String _eulaUrl = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  String get _storeName =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ? 'App Store' : 'Google Play';

  static const String _contactEmail = 'akar.554426@gmail.com';

  Future<void> _copyContactEmail(BuildContext context, LanguageController langCtrl) async {
    await Clipboard.setData(const ClipboardData(text: _contactEmail));
    if (!context.mounted) return;
    if (!EasyReadAccess.enabled(context, listen: false)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(langCtrl.tr('email_copied')), duration: const Duration(seconds: 2)));
    }
  }

  Future<void> _openContactEmail(BuildContext context, LanguageController langCtrl) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _contactEmail,
      query: 'subject=${Uri.encodeComponent(langCtrl.tr('contact_subject'))}',
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    // 冇郵件 App 就改為複製電郵地址
    if (!opened && context.mounted) await _copyContactEmail(context, langCtrl);
  }

  Future<void> _openTerms() async {
    try {
      await launchUrl(Uri.parse(_eulaUrl), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String _planInfo(LanguageController langCtrl, String? price) {
    final hasPrice = price != null && price.isNotEmpty;
    return langCtrl
        .tr(hasPrice ? 'sub_plan_info_priced' : 'sub_plan_info')
        .replaceAll('{title}', langCtrl.tr('pro_title'))
        .replaceAll('{price}', price ?? '');
  }

  Widget _legalLinks(BuildContext context, bool isDark, LanguageController langCtrl) {
    // Same grey in both modes. Easy Read does not lift these two links.
    final style = TextStyle(
      color: _subText,
      fontSize: 12,
      decoration: TextDecoration.none,
      fontFamily: 'Inter',
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InkWell(onTap: _openTerms, child: Text(langCtrl.tr('terms_of_use'), style: style)),
        Text('   •   ', style: TextStyle(color: _subText, fontSize: 12)),
        InkWell(
          onTap: () => _showMarkdownDialog(context, isDark, langCtrl, 'privacy_policy', 'privacy', Icons.privacy_tip, Colors.amber),
          child: Text(langCtrl.tr('privacy_policy'), style: style),
        ),
      ],
    );
  }

  String _buyLabel(LanguageController langCtrl, String? price) {
    if (price == null || price.isEmpty) return langCtrl.tr('buy_coffee');
    return langCtrl.tr('buy_coffee_priced').replaceAll('{price}', price);
  }

  String _upgradeDesc(LanguageController langCtrl, String? price) {
    if (price == null || price.isEmpty) return langCtrl.tr('upgrade_desc');
    return langCtrl.tr('upgrade_desc_priced').replaceAll('{price}', price);
  }

  Widget _buildPremiumHero(
    BuildContext context,
    bool isDark,
    PurchaseController purchaseCtrl,
    LanguageController langCtrl,
  ) {
    final isPro = purchaseCtrl.isPro;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? _cardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.amber.withValues(alpha: 0.18), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.amber.shade300, Colors.orange.shade400],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.workspace_premium, color: Colors.black87, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPro ? langCtrl.tr('pro_title') : langCtrl.tr('upgrade_pro'),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              height: 1.25,
                              fontFamily: 'Inter',
                            ),
                          ),
                          const SizedBox(height: 8),
                          _statusPill(isPro, langCtrl),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  isPro ? langCtrl.tr('pro_subtitle_active') : _upgradeDesc(langCtrl, purchaseCtrl.removeAdsPrice),
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                    height: 1.5,
                    fontFamily: 'Inter',
                  ),
                ),
                if (!isPro) ...[
                  const SizedBox(height: 16),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: purchaseCtrl.isLoading ? null : () => purchaseCtrl.buySubscription(context),
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.amber.shade300, Colors.orange.shade400],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SizedBox(
                          height: 46,
                          child: Center(
                            child: purchaseCtrl.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                                  )
                                : Text(
                                    _buyLabel(langCtrl, purchaseCtrl.removeAdsPrice),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Inter',
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _planInfo(langCtrl, purchaseCtrl.removeAdsPrice),
                    style: TextStyle(
                      color: _readable,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    langCtrl.tr('sub_renew_note').replaceAll('{store}', _storeName),
                    style: TextStyle(
                      color: _readable,
                      fontSize: 11.5,
                      height: 1.45,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _legalLinks(context, isDark, langCtrl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeCtrl = context.watch<ThemeController>();
    final locCtrl = context.watch<LocationController>();
    final busCtrl = context.watch<BusController>();
    final purchaseCtrl = context.watch<PurchaseController>();
    final bgCtrl = context.watch<BackgroundController>();
    final langCtrl = context.watch<LanguageController>();
    final easyReadCtrl = context.watch<EasyReadModeController>();

    final availableTabs = (busCtrl.isSimpleMode || easyReadCtrl.enabled) ? [0, 2, 4, 5] : [0, 1, 2, 4, 5];
    final tabMap = { 
      0: langCtrl.tr('tab_search'), 
      1: langCtrl.tr('tab_route'), 
      2: langCtrl.tr('tab_station'), 
      4: langCtrl.tr('tab_favorite'), 
      5: langCtrl.tr('tab_settings') 
    };
    final safeDefaultIndex = availableTabs.contains(_defaultTabIndex)
        ? _defaultTabIndex
        : (_defaultTabIndex == 3 ? 2 : 0);
    final langMap = { 'zh': '繁體中文', 'zhHans': '简体中文', 'pt': 'Português', 'en': 'English' };

    return Scaffold(
      // 💡 關鍵：如果設定咗自訂背景圖片，Scaffold 背景必須為透明
      backgroundColor: bgCtrl.backgroundImagePath != null 
          ? Colors.transparent 
          : (isDark ? _darkBase : const Color(0xFFF2F2F7)),
          
      // 💡 結構改為 Column，分開固定 Header 同 滑動內容
      body: Column(
        children: [
          // 🌟 從 Source 1 移植嘅 Frosted Glass (毛玻璃) Header，並加入齒輪 Icon
          PreserveChrome(
            child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
              child: Container(
                color: isDark ? Colors.black.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.7),
                // 利用 MediaQuery 獲取系統頂部安全距離，完美取代 SafeArea
                padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center, // 置中對齊
                  children: [                    
                    const SizedBox(width: 8),
                    Text(
                      langCtrl.tr('settings_title'), 
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black, 
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Inter'
                      )
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
          
          Divider(
            height: 1, 
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: 24 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- 1. SUBSCRIPTION ---
                    _buildSectionHeader(langCtrl.tr('section_subscription')),

                    _buildPremiumHero(context, isDark, purchaseCtrl, langCtrl),                    
                                       
                    _buildCard(
                      isDark: isDark,
                      children: [
                        _buildTile(
                          icon: Icons.restore, title: langCtrl.tr('restore_purchase'), isDark: isDark,
                          trailing: purchaseCtrl.isLoading ? const CupertinoActivityIndicator() : null,
                          onTap: purchaseCtrl.isLoading ? null : () => purchaseCtrl.restorePurchases(context),
                        ),
                      ]
                    ),

                    // --- 2. PREFERENCES ---
                    _buildSectionHeader(langCtrl.tr('section_preferences')),
                    _buildCard(
                      isDark: isDark,
                      children: [
                        _buildTile(
                          icon: Icons.translate, title: langCtrl.tr('display_language'), subtitle: langCtrl.tr('display_language_desc'), trailingText: langMap[langCtrl.currentLanguage], isDark: isDark,
                          onTap: () {
                            _showActionSheet(
                              context, langCtrl,
                              title: langCtrl.tr('select_language'),
                              actions: langMap.entries.map((e) => CupertinoActionSheetAction(
                                onPressed: () { langCtrl.changeLanguage(e.key); Navigator.pop(context); },
                                child: Text(e.value, style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                              )).toList(),
                            );
                          }
                        ),
                        _buildTile(
                          icon: Icons.grid_view, title: langCtrl.tr('default_page'), subtitle: langCtrl.tr('default_page_desc'), trailingText: tabMap[safeDefaultIndex], isDark: isDark,
                          onTap: () {
                            _showActionSheet(
                              context, langCtrl,
                              title: langCtrl.tr('select_default_page'),
                              actions: availableTabs.map((idx) => CupertinoActionSheetAction(
                                onPressed: () async {
                                  setState(() => _defaultTabIndex = idx);
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setInt('default_tab_index', idx);
                                  if (context.mounted) Navigator.pop(context);
                                },
                                child: Text(tabMap[idx]!, style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                              )).toList(),
                            );
                          }
                        ),
                        _buildTile(
                          icon: Icons.wallpaper, title: langCtrl.tr('custom_bg'), subtitle: bgCtrl.backgroundImagePath == null ? langCtrl.tr('custom_bg_default') : langCtrl.tr('custom_bg_applied'), isDark: isDark,
                          onTap: () => bgCtrl.pickAndSaveBackground(),
                          trailing: bgCtrl.backgroundImagePath != null 
                              ? IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18), onPressed: () => bgCtrl.clearBackground())
                              : null,
                        ),
                        if (bgCtrl.backgroundImagePath != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  langCtrl.tr('bg_blur'),
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                                Slider(
                                  value: bgCtrl.bgBlur.clamp(0.0, 20.0),
                                  min: 0.0,
                                  max: 20.0,
                                  divisions: 20,
                                  activeColor: Colors.amber,
                                  inactiveColor: isDark ? _mutedWell : Colors.grey[300],
                                  label: bgCtrl.bgBlur.toInt().toString(),
                                  onChanged: (value) => bgCtrl.setBlur(value),
                                ),
                              ],
                            ),
                          ),
                      ]
                    ),

                    // --- 3. APP EXPERIENCE ---
                    _buildSectionHeader(langCtrl.tr('section_app_experience')),
                    _buildCard(
                      isDark: isDark,
                      children: [
                        _buildTile(
                          icon: Icons.format_size, title: langCtrl.tr('easy_read_mode'), subtitle: langCtrl.tr('easy_read_mode_desc'), isDark: isDark,
                          trailing: _settingsSwitch(
                            value: easyReadCtrl.enabled,
                            isDark: isDark,
                            onChanged: easyReadCtrl.setEnabled,
                          ),
                        ),
                        _buildTile(
                          icon: Icons.volume_up_outlined,
                          title: langCtrl.tr('easy_read_speak_arrivals'),
                          isDark: isDark,
                          trailing: _settingsSwitch(
                            value: easyReadCtrl.speakArrivals,
                            isDark: isDark,
                            onChanged: easyReadCtrl.setSpeakArrivals,
                          ),
                        ),
                        _buildTile(
                          icon: Icons.dark_mode_outlined, title: langCtrl.tr('switch_theme'), subtitle: langCtrl.tr('easier_on_eyes'), isDark: isDark,
                          trailing: CupertinoSwitch(
                            value: themeCtrl.themeMode == ThemeMode.dark,
                            onChanged: (_) => themeCtrl.toggleTheme(),
                            activeTrackColor: isDark ? Colors.white : Colors.black, 
                            inactiveTrackColor: _mutedWell,
                            thumbColor: isDark ? Colors.black : Colors.white,
                          ),
                        ),
                        _buildTile(
                          icon: Icons.near_me_outlined, title: langCtrl.tr('locate_position'), subtitle: langCtrl.tr('locate_desc'), isDark: isDark,
                          trailing: CupertinoSwitch(
                            value: locCtrl.isFollowingUser,
                            onChanged: (_) => GpsService.toggleGpsAndAutoSelectStop(context, busCtrl, locCtrl),
                            activeTrackColor: isDark ? Colors.white : Colors.black, 
                            inactiveTrackColor: _mutedWell,
                            thumbColor: isDark ? Colors.black : Colors.white,
                          ),
                        ),
                        _buildTile(
                          icon: Icons.bolt_outlined, title: langCtrl.tr('simple_mode_off'), subtitle: langCtrl.tr('simple_mode_desc_off'), isDark: isDark,
                          trailing: CupertinoSwitch(
                            value: busCtrl.isSimpleMode,
                            onChanged: (val) {
                              busCtrl.toggleSimpleMode(val);
                              if (val) {
                                context.read<NavigationController>().closeMap(busCtrl: busCtrl);
                              }
                            },
                            activeTrackColor: isDark ? Colors.white : Colors.black, 
                            inactiveTrackColor: _mutedWell,
                            thumbColor: isDark ? Colors.black : Colors.white,
                          ),
                        ),
                        if (kDebugMode)
                          _buildTile(
                            icon: Icons.bug_report_outlined, title: langCtrl.tr('test_ad_free'), subtitle: langCtrl.tr('simulate_pro_status'), isDark: isDark,
                            trailing: CupertinoSwitch(
                              value: purchaseCtrl.isPro,
                              onChanged: (_) => purchaseCtrl.toggleDebugProStatus(),
                              activeTrackColor: isDark ? Colors.white : Colors.black,
                              inactiveTrackColor: _mutedWell,
                              thumbColor: isDark ? Colors.black : Colors.white,
                            ),
                          ),
                      ]
                    ),

                    // --- 4. CONTACT ---
                    _buildSectionHeader(langCtrl.tr('section_contact')),
                    _buildCard(
                      isDark: isDark,
                      children: [
                        GestureDetector(
                          onLongPress: () => _copyContactEmail(context, langCtrl),
                          child: _buildTile(
                            icon: Icons.mail_outline, title: langCtrl.tr('contact_email_title'), subtitle: '$_contactEmail\n${langCtrl.tr('contact_hint')}', isDark: isDark,
                            onTap: () => _openContactEmail(context, langCtrl),
                            trailing: IconButton(
                              icon: Icon(Icons.copy_rounded, color: _readable, size: 18),
                              tooltip: langCtrl.tr('copy_email'),
                              onPressed: () => _copyContactEmail(context, langCtrl),
                            ),
                          ),
                        ),
                      ]
                    ),

                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          InkWell(onTap: () => _showMarkdownDialog(context, isDark, langCtrl, 'about_us', 'about', Icons.info_outline, Colors.blueAccent), child: Text(langCtrl.tr('about_us'), style: TextStyle(color: _readable, fontSize: 12))),
                          Text('   •   ', style: TextStyle(color: _readable, fontSize: 12)),
                          InkWell(onTap: () => _showMarkdownDialog(context, isDark, langCtrl, 'disclaimer', 'disclaimer', Icons.gavel, Colors.redAccent), child: Text(langCtrl.tr('disclaimer'), style: TextStyle(color: _readable, fontSize: 12))),
                        ],
                      ),
                    ),
                    if (_versionLabel != null) ...[
                      const SizedBox(height: 12),
                      Center(child: Text(_versionLabel!, style: TextStyle(color: EasyReadAccess.enabled(context) ? _readable : (isDark ? const Color(0xFF3A3A3C) : Colors.grey[400]), fontSize: 11, fontFamily: 'Inter', letterSpacing: 0.5))),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}