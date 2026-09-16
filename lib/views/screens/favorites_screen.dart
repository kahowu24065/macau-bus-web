import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/bus_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../widgets/custom_banner_ad.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final busCtrl = context.watch<BusController>();

    return Column(
      children: [
        AppBar(
          title: Text('⭐ 我的收藏路線', style: TextStyle(color: isDark ? Colors.white : Colors.black)), 
          centerTitle: true, 
          automaticallyImplyLeading: false
        ),
        Expanded(
          child: busCtrl.favoriteRoutes.isEmpty 
            ? const Center(child: Text('暫無收藏路線，快啲去車站頁面收藏啦！', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                itemCount: busCtrl.favoriteRoutes.length,
                itemBuilder: (context, index) {
                  final route = busCtrl.favoriteRoutes[index];
                  return ListTile(
                    leading: const Icon(Icons.directions_bus, color: Colors.amber),
                    title: Text('巴士路線 $route', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () => busCtrl.toggleFavorite(route),
                    ),
                    onTap: () {
                      busCtrl.setRoute(route);
                      busCtrl.fetchStops();
                      context.read<NavigationController>().changeTab(1); // 跳去車站 Tab
                    },
                  );
                },
              ),
        ),

        const CustomBannerAd(),
      ],
    );
  }
}