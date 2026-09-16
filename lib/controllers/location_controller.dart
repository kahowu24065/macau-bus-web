import 'dart:async';
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
      _positionStream?.cancel();
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

  void _updateLocation(Position position) {
    userLocation = LatLng(position.latitude, position.longitude);
    if (position.heading > 0) userHeading = position.heading;
    notifyListeners();
  }
}