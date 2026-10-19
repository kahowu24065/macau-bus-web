import ActivityKit
import Foundation

/// One attributes type for the boarding reminder.
///
/// This file is compiled into both the Runner app and the BoardingLiveActivity
/// extension. ActivityKit matches the activity to the widget by this type.
@available(iOS 16.1, *)
struct BoardingActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// Predicted whole minutes at the last push/local update. Kept for older
    /// payloads and as a fallback when [endsAt] is missing.
    var minutes: Int
    var text: String
    /// Unix seconds when the bus is predicted to arrive. The widget counts
    /// down from this with Text(timerInterval:) so the Lock Screen ticks
    /// even when no Live Activity push token was ever posted to the server.
    var endsAt: Double?

    init(minutes: Int, text: String, endsAt: Double? = nil) {
      self.minutes = minutes
      self.text = text
      self.endsAt = endsAt
    }
  }

  var route: String
  var stopName: String
  /// Phrase shown before the countdown, e.g. 「預測到站時間尚餘」.
  /// Nil on older or server-started activities; the widget then uses Traditional Chinese.
  var etaLabel: String? = nil
}
