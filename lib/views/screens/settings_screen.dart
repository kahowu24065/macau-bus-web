import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/app_strings.dart';
import '../../controllers/purchase_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/bus_controller.dart';
import '../widgets/custom_banner_ad.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _defaultTabIndex = 1;

  @override
  void initState() {
    super.initState();
    _loadDefaultTab();
  }

  Future<void> _loadDefaultTab() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _defaultTabIndex = prefs.getInt('default_tab_index') ?? 1;
      });
    }
  }

  // 🌟 彈出視窗：關於我們
  void _showAboutApp(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Text('關於我們', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            AppStrings.aboutApp,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  // 🌟 彈出視窗：免責聲明
  void _showDisclaimer(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        title: Row(
          children: [
            const Icon(Icons.gavel, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text('免責聲明', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            AppStrings.disclaimer,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  // 🌟 彈出視窗：隱私權政策
  void _showPrivacyPolicy(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        title: Row(
          children: [
            const Icon(Icons.privacy_tip, color: Colors.amber),
            const SizedBox(width: 8),
            Text('隱私權政策', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              AppStrings.privacyPolicy,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉', style: TextStyle(color: Colors.amber)),
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

    return Column(
      children: [
        AppBar(
          title: Text('⚙️ 設定', style: TextStyle(color: isDark ? Colors.white : Colors.black)), 
          centerTitle: true, 
          automaticallyImplyLeading: false,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
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
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '👑 升級為巴士預報-MBKa贊助人',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '每月只需要 \$5 就可以去除所有廣告，請我飲杯咖啡，支持呢個app持續更新，開發，進步。',
                          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.orange.shade900,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: purchaseCtrl.isLoading ? null : () => purchaseCtrl.buySubscription(context),
                            child: purchaseCtrl.isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('請我飲杯咖啡 (\$5 / 月)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              ListTile(
                leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                title: Text(
                  '巴士預報-MBKa贊助人',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  purchaseCtrl.isPro ? '感謝支持！已開通去除廣告權益' : '開通月費支持開發並去除所有廣告',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: purchaseCtrl.isPro
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: purchaseCtrl.isPro ? Colors.green : Colors.grey,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    purchaseCtrl.isPro ? '已開通' : '未開通',
                    style: TextStyle(
                      color: purchaseCtrl.isPro ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                onTap: purchaseCtrl.isPro
                    ? null
                    : () => purchaseCtrl.buySubscription(context),
              ),
              Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

              ListTile(
                leading: const Icon(Icons.restore, color: Colors.blueAccent),
                title: Text('回復已購買項目', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                subtitle: const Text('更換裝置或重新安裝後可在此回復訂閱', style: TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: purchaseCtrl.isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: purchaseCtrl.isLoading ? null : () => purchaseCtrl.restorePurchases(context),
              ),
              Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

              ListTile(
                leading: Icon(themeCtrl.themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode, color: Colors.amber),
                title: Text('切換日夜模式', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                trailing: Switch(
                  value: themeCtrl.themeMode == ThemeMode.dark,
                  onChanged: (val) => themeCtrl.toggleTheme(),
                  activeThumbColor: Colors.amber,
                ),
                onTap: () => themeCtrl.toggleTheme(),
              ),
              Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

              ListTile(
                leading: const Icon(Icons.my_location, color: Colors.blueAccent),
                title: Text('定位目前位置', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                subtitle: const Text('尋找並跳轉至距離您最近的巴士站', style: TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  context.read<NavigationController>().changeTab(1);
                  locCtrl.toggleLocationTracking((loc) {});
                },
              ),
              Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

              ListTile(
                leading: Icon(busCtrl.isSimpleMode ? Icons.unfold_more : Icons.unfold_less, color: Colors.green),
                title: Text(busCtrl.isSimpleMode ? '切換至詳細版' : '切換至簡潔版', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                subtitle: Text(busCtrl.isSimpleMode ? '顯示所有進階導航與設定按鈕' : '隱藏搜尋列旁的進階按鈕，保持介面清爽', style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
                title: Text(
                  '設定預設主頁',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  '選擇開啟 App 時顯示的第一個頁面',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF333333) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<int>(
                    isDense: true,
                    value: _defaultTabIndex,
                    dropdownColor: isDark ? const Color(0xFF333333) : Colors.white,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    items: [
                      DropdownMenuItem(value: 0, child: Text('路線', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
                      DropdownMenuItem(value: 1, child: Text('車站', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
                      DropdownMenuItem(value: 2, child: Text('地圖', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
                      DropdownMenuItem(value: 3, child: Text('收藏', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
                    ],
                    onChanged: (int? newValue) async {
                      if (newValue != null) {
                        setState(() {
                          _defaultTabIndex = newValue;
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setInt('default_tab_index', newValue);
                        
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已將預設主頁更改為 ${["路線", "車站", "地圖", "收藏"][newValue]}'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
              Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]),

              ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.grey),
                title: const Text('測試開關：免廣告狀態', style: TextStyle(color: Colors.grey)),
                subtitle: const Text('供測試環境手動模擬 Pro 用戶狀態', style: TextStyle(color: Colors.grey, fontSize: 11)),
                trailing: Switch(
                  value: purchaseCtrl.isPro,
                  onChanged: (_) => purchaseCtrl.toggleDebugProStatus(),
                  activeThumbColor: Colors.amber,
                ),
              ),

              const SizedBox(height: 32), 

              // 🌟 重新排版：關於、聲明與私隱權政策 (置底超連結)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => _showAboutApp(context, isDark),
                          child: Text(
                            '關於我們',
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        Text(
                          '   |   ',
                          style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 12),
                        ),
                        InkWell(
                          onTap: () => _showDisclaimer(context, isDark),
                          child: Text(
                            '免責聲明',
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        Text(
                          '   |   ',
                          style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 12),
                        ),
                        InkWell(
                          onTap: () => _showPrivacyPolicy(context, isDark),
                          child: Text(
                            '隱私權政策',
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'v 1.0.0 (Build 1)',
                      style: TextStyle(
                        color: isDark ? Colors.grey[600] : Colors.grey[400],
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40), 
                  ],
                ),
              ),
            ],
          ),
        ),

        const CustomBannerAd(),
      ],
    );
  }
}