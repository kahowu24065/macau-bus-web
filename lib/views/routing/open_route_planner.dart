import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/bus_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/location_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../utils/elderly_access.dart';
import '../../utils/route_result_helper.dart';
import '../widgets/route_liquid_glass_nav.dart';
import '../widgets/routing_bottom_sheet.dart';

void openRoutePlanner(BuildContext parentContext) {
  final busCtrl = parentContext.read<BusController>();
  if (busCtrl.isSimpleMode) return;
  final navCtrl = parentContext.read<NavigationController>();
  final locCtrl = parentContext.read<LocationController>();
  final langCtrl = parentContext.read<LanguageController>();
  final elderly = ElderlyAccess.enabled(parentContext, listen: false);

  bool wasRouteCalculated = false;
  navCtrl.setPlanningRoute(true);

  showModalBottomSheet(
    context: parentContext,
    isScrollControlled: true,
    backgroundColor: Theme.of(parentContext).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: RoutingBottomSheet(
        userLocation: locCtrl.isFollowingUser ? locCtrl.userLocation : null,
        isLocationActive: locCtrl.isFollowingUser,
        customMapStart: busCtrl.customMapStart,
        customMapEnd: busCtrl.customMapEnd,
        onPickOnMap: () {
          Navigator.pop(sheetContext);
          busCtrl.startPickingMapStart();
          navCtrl.captureRouteForRestore(busCtrl.currentRoute);
          navCtrl.clearNavigation();
          navCtrl.setPlanningRoute(true);
          navCtrl.openMap();
        },
        onPickEndOnMap: () {
          Navigator.pop(sheetContext);
          busCtrl.startPickingMapEnd();
          navCtrl.captureRouteForRestore(busCtrl.currentRoute);
          navCtrl.clearNavigation();
          navCtrl.setPlanningRoute(true);
          navCtrl.openMap();
        },
        onRouteCalculated: (itineraries, destination, onlyGhostsLeft) {
          wasRouteCalculated = true;
          Navigator.pop(sheetContext);
          busCtrl.clearCustomMapPoints();
          if (itineraries.isNotEmpty) {
            if (onlyGhostsLeft && !elderly) {
              ScaffoldMessenger.of(parentContext).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: parentContext, content: Text(langCtrl.tr('warning_offline')), backgroundColor: Colors.redAccent));
            }
            navCtrl.addHistory(itineraries, destination, onlyGhostsLeft);
            Future.delayed(const Duration(milliseconds: 350), () {
              if (parentContext.mounted) {
                RouteResultHelper.showOTPResultBottomSheet(parentContext, itineraries, destination, navCtrl, langCtrl);
              }
            });
          } else {
            ScaffoldMessenger.of(parentContext).showSnackBar(RouteLiquidGlassNavStyle.snackBar(context: parentContext, content: Text(langCtrl.tr('calc_route_failed'))));
            navCtrl.setPlanningRoute(false);
          }
        },
      ),
    ),
  ).whenComplete(() {
    if (!busCtrl.isPickingMapStart && !busCtrl.isPickingMapEnd && !wasRouteCalculated) {
      busCtrl.clearCustomMapPoints();
      navCtrl.setPlanningRoute(false);
    }
  });
}
