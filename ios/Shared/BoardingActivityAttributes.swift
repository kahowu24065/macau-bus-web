import ActivityKit

/// One attributes type for the boarding reminder.
///
/// This file is compiled into both the Runner app and the BoardingLiveActivity
/// extension. ActivityKit matches the activity to the widget by this type.
@available(iOS 16.1, *)
struct BoardingActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var minutes: Int
    var text: String
  }

  var route: String
  var stopName: String
}
