/// Temporary compliance switches.
///
/// Route shape (GPX) and published timetables stay off until those data
/// sources are replaced. Set either flag back to true to restore that UI.
class FeatureFlags {
  /// Route map polylines / GPX trajectories, including the route map button
  /// and the planner "show on map" shape overlay.
  static const bool showRouteTrajectory = false;

  /// Published route timetables (時間表) from debug_details / timetable sections.
  static const bool showTimetable = false;
}
