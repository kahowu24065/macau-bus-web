/// Temporary compliance switches.
///
/// Route shape (GPX) stays off until that data source is replaced.
/// Published timetables are official DSAT frequency bands
/// (`assets/dsat_timetables.json`), not motransportinfo / debug_details.
class FeatureFlags {
  /// Route map polylines / GPX trajectories, including the route map button
  /// and the planner "show on map" shape overlay.
  static const bool showRouteTrajectory = false;

  /// Published route timetables (時間表) from DSAT frequency bands.
  static const bool showTimetable = true;
}
