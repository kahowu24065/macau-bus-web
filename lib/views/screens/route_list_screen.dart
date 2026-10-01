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
            child: busCtrl.allRoutesWithDir.isEmpty 
              ? const Center(child: CircularProgressIndicator(color: Colors.amber)) 
              : ListView.separated(
                  padding: EdgeInsets.only(
                    top: 8,
                    bottom: 8 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: busCtrl.allRoutesWithDir.length, 
                  separatorBuilder: (c, i) => Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]), 
                  itemBuilder: (context, index) {
                    final item = busCtrl.allRoutesWithDir[index].toString(); 
                    
                    // 🌟 強化字串拆解邏輯
                    final parts = item.split('|'); 
                    final routeNo = parts[0].trim(); 
                    // 如果有第二部分，就直接顯示 Server 回傳嘅內容（即係翻譯好嘅字）；冇嘅話先用預設字眼
                    final routeDesc = parts.length > 1 && parts[1].trim().isNotEmpty 
                        ? parts[1].trim() 
                        : langCtrl.tr('macau_bus_route_desc'); 
                    
                    return ListTile(
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
                  }
                ),
                ),
        ],
      ),
    );
  }
}