import ActivityKit
import SwiftUI
import WidgetKit

/// Dynamic Island / Lock Screen UI for the boarding reminder.
///
/// This file is not a member of the Runner target. Add an iOS Widget Extension
/// named BoardingLiveActivity (bundle id mo.mbka.bus.BoardingLiveActivity),
/// enable Live Activities on the App ID, and compile this file plus
/// BoardingActivityAttributes into that extension. The attributes struct must
/// stay identical to ios/Runner/BoardingLiveActivityBridge.swift.
///
/// The view shows the predicted minutes only. It does not show a stop count.

@available(iOS 16.1, *)
struct BoardingActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var minutes: Int
    var text: String
  }

  var route: String
  var stopName: String
}

@available(iOS 16.1, *)
struct BoardingLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BoardingActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 4) {
        Text(context.attributes.route)
          .font(.headline)
        Text(context.state.text)
          .font(.body)
      }
      .padding()
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.route)
            .font(.headline)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(minuteLabel(context.state.minutes))
            .font(.title2)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.text)
        }
      } compactLeading: {
        Text(context.attributes.route)
      } compactTrailing: {
        Text(minuteLabel(context.state.minutes))
      } minimal: {
        Text(minuteLabel(context.state.minutes))
      }
    }
  }
}

@available(iOS 16.1, *)
private func minuteLabel(_ minutes: Int) -> String {
  "\(minutes)m"
}
