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
    /// Unix seconds when the bus is predicted to arrive. Values above
    /// 10_000_000_000 are treated as milliseconds. The widget uses this, then
    /// falls back to [minutes], so a missing endsAt still shows a time.
    var endsAt: Double?
    /// Phrase in front of the remaining time, e.g. 「預測到站時間尚餘」.
    /// Content-state wins over the attribute copy so each push can refresh it.
    var etaLabel: String?

    init(minutes: Int, text: String, endsAt: Double? = nil, etaLabel: String? = nil) {
      self.minutes = minutes
      self.text = text
      self.endsAt = endsAt
      self.etaLabel = etaLabel
    }

    private enum CodingKeys: String, CodingKey {
      case minutes, text, endsAt, etaLabel
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
      text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
      if let seconds = try? container.decode(Double.self, forKey: .endsAt) {
        endsAt = seconds
      } else if let seconds = try? container.decode(Int.self, forKey: .endsAt) {
        endsAt = Double(seconds)
      } else {
        endsAt = nil
      }
      etaLabel = try container.decodeIfPresent(String.self, forKey: .etaLabel)
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(minutes, forKey: .minutes)
      try container.encode(text, forKey: .text)
      try container.encodeIfPresent(endsAt, forKey: .endsAt)
      try container.encodeIfPresent(etaLabel, forKey: .etaLabel)
    }
  }

  var route: String
  var stopName: String
  /// Same phrase, kept from activity start when a push omits content-state etaLabel.
  var etaLabel: String? = nil
}
