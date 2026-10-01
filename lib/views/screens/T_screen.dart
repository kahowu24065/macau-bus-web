import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/gps_service.dart';
import '../../controllers/purchase_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/bus_controller.dart';
import '../widgets/custom_banner_ad.dart';
import '../../controllers/background_controller.dart';
import '../../controllers/language_controller.dart'; 

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _defaultTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDefaultTab();
  }

  Future<void> _loadDefaultTab() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _defaultTabIndex = prefs.getInt('default_tab_index') ?? 0;
      });
    }
  }

  // 🌟 非同步讀取 Markdown 檔案內容
  Future<String> _loadMarkdownContent(String filePrefix, String langCode) async {
    try {
      return await rootBundle.loadString('assets/i18n/${filePrefix}_$langCode.md');
    } catch (e) {
      // 容錯機制：如果搵唔到對應語言，退回英文或中文預設檔
      try {
        return await rootBundle.loadString('assets/i18n/${filePrefix}_en.md');
      } catch (e2) {
        try {
          return await rootBundle.loadString('assets/i18n/${filePrefix}_zh.md');
        } catch (e3) {
          return 'Content not found. / 找不到對應的文本內容。';
        }
      }
    }
  }

  // 🌟 通用 Markdown 彈窗函數
  void _showMarkdownDialog(BuildContext context, bool isDark, LanguageController langCtrl, String titleKey, String filePrefix, IconData icon, Color iconColor) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 8),
            // 🌟 加入 Expanded 包住 Text
            Expanded(
              child: Text(
                langCtrl.tr(titleKey), 
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 18 // 保持 18 都可以，因為而家識得自動換行喇
                ),
                softWrap: true, // 允許自動換行
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<String>(
            future: _loadMarkdownContent(filePrefix, langCtrl.currentLanguage),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: Colors.amber)));
              }
              if (snapshot.hasError) {
                return Text('載入失敗\n${snapshot.error}', style: const TextStyle(color: Colors.redAccent));
              }
              
              // 使用 MarkdownBody 渲染，配合 SingleChildScrollView 確保滾動順暢
              return SingleChildScrollView(
                child: MarkdownBody(
                  data: snapshot.data ?? '',
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14, height: 1.5),
                    h1: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                    h2: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                    listBullet: TextStyle(color: isDark ? Colors.amber : Colors.orange),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(langCtrl.tr('btn_close'), style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
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

    final availableTabs = busCtrl.isSimpleMode ? [0, 2, 4, 5] : [0, 1, 2, 3, 4, 5];
    final tabMap = {
      0: langCtrl.tr('tab_search'), 
      1: langCtrl.tr('tab_route'), 
      2: langCtrl.tr('tab_station'), 
      3: langCtrl.tr('tab_map'), 
      4: langCtrl.tr('tab_favorite'), 
      5: langCtrl.tr('tab_settings')
    };
    final safeDefaultIndex = availableTabs.contains(_defaultTabIndex) ? _defaultTabIndex : 0;

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
                        langCtrl.tr('settings_title'), 
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black, 
                          fontSize: 18, 
                          fontWeight: FontWeight.bold
                        )
                      )
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          Divider(
            height: 1, 
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)
          ),

          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                top: 8, 
                bottom: 8.0,
              ), 
              children: [
                if (!purchaseCtrl.isPro) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.amber.shade700, Colors.orange.shade800],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(langCtrl.tr('upgrade_pro'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(langCtrl.tr('upgrade_desc'), style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity, height: 44,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.orange.shade900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              onPressed: purchaseCtrl.isLoading ? null : () => purchaseCtrl.buySubscription(context),
                              child: purchaseCtrl.isLoading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(langCtrl.tr('buy_coffee'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                ListTile(
                  leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                  title: Text(langCtrl.tr('pro_title'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                  subtitle: Text(purchaseCtrl.isPro ? langCtrl.tr('pro_subtitle_active') : langCtrl.tr('pro_subtitle_inactive'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: purchaseCtrl.isPro ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: purchaseCtrl.isPro ? Colors.green : Colors.grey, width: 1)),
                    child: Text(purchaseCtrl.isPro ? langCtrl.tr('status_active') : langCtrl.tr('status_inactive'), style: TextStyle(color: purchaseCtrl.isPro ? Colors.green : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  onTap: purchaseCtrl.isPro ? null : () => purchaseCtrl.buySubscription(context),
                ),
                Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

                ListTile(
                  leading: const Icon(Icons.restore, color: Colors.blueAccent),
                  title: Text(langCtrl.tr('restore_purchase'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                  subtitle: Text(langCtrl.tr('restore_desc'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: purchaseCtrl.isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: purchaseCtrl.isLoading ? null : () => purchaseCtrl.restorePurchases(context),
                ),
                Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

                ListTile(
                  leading: const Icon(Icons.language, color: Colors.blue),
                  title: Text(langCtrl.tr('display_language'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                  subtitle: Text(langCtrl.tr('display_language_desc'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF333333) : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                    child: DropdownButton<String>(
                      isDense: true,
                      value: langCtrl.currentLanguage,
                      dropdownColor: isDark ? const Color(0xFF333333) : Colors.white,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      items: [
                        DropdownMenuItem(value: 'zh', child: Text('繁體中文', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
                        DropdownMenuItem(value: 'zhHans', child: Text('简体中文', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
                        DropdownMenuItem(value: 'pt', child: Text('Português', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
                        DropdownMenuItem(value: 'en', child: Text('English', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
                      ],
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          langCtrl.changeLanguage(newValue);
                        }
                      },
                    ),
                  ),
                ),
                Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

                ListTile(
                  leading: Icon(
                    themeCtrl.themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode, 
                    color: themeCtrl.themeMode == ThemeMode.dark ? Colors.orange : Colors.amber
                  ),
                  title: Text(langCtrl.tr('switch_theme'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                  trailing: Switch(
                    value: themeCtrl.themeMode == ThemeMode.dark, 
                    onChanged: (val) => themeCtrl.toggleTheme(), 
                    activeThumbColor: Colors.orange,
                    inactiveThumbColor: isDark ? Colors.white : Colors.black,
                  ),
                  onTap: () => themeCtrl.toggleTheme(),
                ),
                Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

                ListTile(
                  leading: Icon(Icons.my_location, color: locCtrl.isFollowingUser ? Colors.green : Colors.amber),
                  title: Text(langCtrl.tr('locate_position'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                  subtitle: Text(langCtrl.tr('locate_desc'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: Switch(
                    value: locCtrl.isFollowingUser,
                    onChanged: (val) => GpsService.toggleGpsAndAutoSelectStop(context, busCtrl, locCtrl),
                    activeThumbColor: Colors.green,
                    inactiveThumbColor: isDark ? Colors.white : Colors.black,
                  ),
                  onTap: () => GpsService.toggleGpsAndAutoSelectStop(context, busCtrl, locCtrl),
                ),
                Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

                ListTile(
                  leading: Icon(busCtrl.isSimpleMode ? Icons.bolt : Icons.public, color: Colors.green),
                  title: Text(busCtrl.isSimpleMode ? langCtrl.tr('simple_mode_on') : langCtrl.tr('simple_mode_off'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                  subtitle: Text(busCtrl.isSimpleMode ? langCtrl.tr('simple_mode_desc_on') : langCtrl.tr('simple_mode_desc_off'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: Switch(
                    value: busCtrl.isSimpleMode,
                    onChanged: (val) => busCtrl.toggleSimpleMode(val),
                    activeThumbColor: Colors.green,
                  ),
                  onTap: () => busCtrl.toggleSimpleMode(!busCtrl.isSimpleMode),
                ),
                Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),
                
                ListTile(
                  leading: const Icon(Icons.home, color: Colors.purpleAccent),
                  title: Text(langCtrl.tr('default_page'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                  subtitle: Text(langCtrl.tr('default_page_desc'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF333333) : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                    child: DropdownButton<int>(
                      isDense: true,
                      value: safeDefaultIndex,
                      dropdownColor: isDark ? const Color(0xFF333333) : Colors.white,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      items: availableTabs.map((idx) => DropdownMenuItem(value: idx, child: Text(tabMap[idx]!, style: TextStyle(color: isDark ? Colors.white : Colors.black)))).toList(),
                      onChanged: (int? newValue) async {
                        if (newValue != null) {
                          setState(() => _defaultTabIndex = newValue);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt('default_tab_index', newValue);
                          
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${langCtrl.tr('default_page_changed')}${tabMap[newValue]}'), duration: const Duration(seconds: 2)));
                          }
                        }
                      },
                    ),
                  ),
                ),
                Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

                ListTile(
                  leading: const Icon(Icons.wallpaper, color: Colors.blueAccent),
                  title: Text(langCtrl.tr('custom_bg')),
                  subtitle: Text(
                    bgCtrl.backgroundImagePath == null 
                        ? langCtrl.tr('custom_bg_default') 
                        : langCtrl.tr('custom_bg_applied'),
                  ),
                  trailing: bgCtrl.backgroundImagePath != null
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          tooltip: '還原預設',
                          onPressed: () => bgCtrl.clearBackground(),
                        )
                      : null,
                  onTap: () => bgCtrl.pickAndSaveBackground(),
                ),
                
                if (bgCtrl.backgroundImagePath != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          langCtrl.tr('bg_blur'),
                          style: TextStyle(
                            color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                        Slider(
                          value: bgCtrl.bgBlur,
                          min: 0.0,
                          max: 20.0,
                          divisions: 20,
                          activeColor: Colors.amber,
                          label: bgCtrl.bgBlur.toInt().toString(),
                          onChanged: (value) {
                            bgCtrl.setBlur(value);
                          },
                        ),
                      ],
                    ),
                  ),

                ListTile(
                  leading: const Icon(Icons.bug_report, color: Colors.grey),
                  title: Text(langCtrl.tr('test_ad_free'), style: const TextStyle(color: Colors.grey)),
                  subtitle: Text(langCtrl.tr('test_ad_free_desc'), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  trailing: Switch(value: purchaseCtrl.isPro, onChanged: (_) => purchaseCtrl.toggleDebugProStatus(), activeThumbColor: Colors.amber),
                ),

                const SizedBox(height: 32), 

                // 🌟 更新咗跳轉邏輯嘅底部區塊：呼叫 Markdown 彈窗
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          InkWell(
                            onTap: () => _showMarkdownDialog(context, isDark, langCtrl, 'about_us', 'about', Icons.info_outline, Colors.blueAccent), 
                            child: Text(langCtrl.tr('about_us'), style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12, decoration: TextDecoration.underline))
                          ),
                          Text('   |   ', style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 12)),
                          
                          InkWell(
                            onTap: () => _showMarkdownDialog(context, isDark, langCtrl, 'disclaimer', 'disclaimer', Icons.gavel, Colors.redAccent), 
                            child: Text(langCtrl.tr('disclaimer'), style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12, decoration: TextDecoration.underline))
                          ),
                          Text('   |   ', style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 12)),
                          
                          InkWell(
                            onTap: () => _showMarkdownDialog(context, isDark, langCtrl, 'privacy_policy', 'privacy', Icons.privacy_tip, Colors.amber), 
                            child: Text(langCtrl.tr('privacy_policy'), style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12, decoration: TextDecoration.underline))
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('v 1.0.0 (Build 1)', style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 10), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const CustomBannerAd(),
          const SizedBox(height: kBottomNavigationBarHeight), 
        ],
      ),
    );
  }
}