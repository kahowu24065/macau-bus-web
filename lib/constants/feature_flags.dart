/// Temporary compliance switches.
///
/// Route polylines come from the DSAT open-data shapefile
/// (`ROUTE_NETWORK` joined through `BUS_ROUTE_SEQ`), via `/api/route-shape`.
/// Published timetables are official DSAT frequency bands
/// (`assets/dsat_timetables.json`), not motransportinfo / debug_details.
class FeatureFlags {
  /// Route map polylines, including the route map button and the planner
  /// "show on map" shape overlay.
  static const bool showRouteTrajectory = true;

  /// Published route timetables (時間表) from DSAT frequency bands.
  static const bool showTimetable = true;
}
