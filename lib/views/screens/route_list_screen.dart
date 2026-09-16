import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/bus_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../widgets/custom_banner_ad.dart';

class RouteListScreen extends StatefulWidget {
  const RouteListScreen({super.key});

  @override
  State<RouteListScreen> createState() => _RouteListScreenState();
}

class _RouteListScreenState extends State<RouteListScreen> {
  @override
  void initState() {
    super.initState();
    // 畫面載入時，自動叫 Controller 去攞全澳路線
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final busCtrl = context.read<BusController>();
      if (busCtrl.allRoutesWithDir.isEmpty && !busCtrl.isLoadingAllRoutes) {
        busCtrl.fetchAllRoutes();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final busCtrl = context.watch<BusController>();

    return Column(
      children: [
        AppBar(
          title: Text('🚌 全澳巴士路線總覽', style: TextStyle(color: isDark ? Colors.white : Colors.black)), 
          centerTitle: true, automaticallyImplyLeading: false
        ),
        Expanded(
          child: busCtrl.isLoadingAllRoutes 
            ? const Center(child: CircularProgressIndicator(color: Colors.amber)) 
            : ListView.separated(
                itemCount: busCtrl.allRoutesWithDir.length, 
                separatorBuilder: (c, i) => Divider(height: 1, color: isDark ? const Color(0xFF333333) : Colors.grey[300]), 
                itemBuilder: (context, index) {
                  final item = busCtrl.allRoutesWithDir[index].toString(); 
                  final parts = item.split('|'); 
                  final routeNo = parts[0]; 
                  final routeDesc = parts.length > 1 ? parts[1] : '澳門巴士路線'; 
                  
                  return ListTile(
                    dense: true, 
                    leading: CircleAvatar(backgroundColor: Colors.amber.withValues(alpha: 0.2), child: Text(routeNo, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12))), 
                    title: Text(routeNo, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 15)), 
                    subtitle: Text(routeDesc, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13)), 
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18), 
                    onTap: () { 
                      // 🛡️ 完美解耦：改路線 -> 叫車站 Controller 攞數據 -> 叫導航 Controller 跳頁
                      context.read<BusController>().setRoute(routeNo);
                      context.read<BusController>().fetchStops();
                      context.read<NavigationController>().changeTab(1);
                    }
                  );
                }
              ),
        ),

        const CustomBannerAd(),
      ],
    );
  }
}