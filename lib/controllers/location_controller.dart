import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationController extends ChangeNotifier {
  LatLng? userLocation;
  double userHeading = 0.0;
  bool isLocating = false;
  bool isFollowingUser = false;
  StreamSubscription<Position>? _positionStream;

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> toggleLocationTracking(Function(LatLng) onLocationUpdated) async {
    if (isFollowingUser) {
      // 🌟 升級 1：加入 await 確保 Android 底層完全釋放，並清空變數
      await _positionStream?.cancel();
      _positionStream = null;
      isFollowingUser = false;
      notifyListeners();
      return;
    }

    isLocating = true;
    notifyListeners();

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          isLocating = false;
          notifyListeners();
          throw Exception('定位權限被拒絕');
        }
      }

      Position pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      _updateLocation(pos);
      onLocationUpdated(LatLng(pos.latitude, pos.longitude));

      // 🌟 升級 2：在建立全新監聽前，強制終止並清除任何可能殘留嘅幽靈 Stream
      await _positionStream?.cancel();
      _positionStream = null;

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2),
      ).listen((Position position) {
        _updateLocation(position);
        if (isFollowingUser) onLocationUpdated(LatLng(position.latitude, position.longitude));
      });

      isFollowingUser = true;
      isLocating = false;
      notifyListeners();
    } catch (e) {
      isLocating = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Location updates for the alighting reminder. [background] is only used
  /// after Always authorization, so map following stays While Using.
  Future<void> trackForAlighting(
    void Function(LatLng) onLocationUpdated, {
    required bool background,
  }) async {
    isLocating = true;
    notifyListeners();
    try {
      final bool useBackground = background && defaultTargetPlatform == TargetPlatform.iOS;
      final LocationSettings settings = useBackground
          ? AppleSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 2,
              allowBackgroundLocationUpdates: true,
              showBackgroundLocationIndicator: true,
              pauseLocationUpdatesAutomatically: false,
            )
          : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2);
      final Position pos = await Geolocator.getCurrentPosition(locationSettings: settings);
      _updateLocation(pos);
      onLocationUpdated(LatLng(pos.latitude, pos.longitude));
      await _positionStream?.cancel();
      _positionStream = null;
      _positionStream = Geolocator.getPositionStream(locationSettings: settings).listen((Position position) {
        _updateLocation(position);
        if (isFollowingUser) onLocationUpdated(LatLng(position.latitude, position.longitude));
      });
      isFollowingUser = true;
      isLocating = false;
      notifyListeners();
    } catch (e) {
      isLocating = false;
      notifyListeners();
      rethrow;
    }
  }

  void _updateLocation(Position position) {
    userLocation = LatLng(position.latitude, position.longitude);
    if (position.heading > 0) userHeading = position.heading;
    notifyListeners();
  }
}