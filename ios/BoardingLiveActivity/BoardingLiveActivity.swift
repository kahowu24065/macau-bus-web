import ActivityKit
import SwiftUI
import WidgetKit

/// One Live Activity for the boarding reminder.
///
/// Phones with a Dynamic Island show this configuration there. Phones without
/// one show the same activity on the Lock Screen and in the notification list.
/// There is no second notification. The text is the predicted-minutes sentence
/// from the app, never a remaining-stop count.
///
/// BoardingActivityAttributes must stay identical to the copy in
/// ios/Runner/BoardingLiveActivityBridge.swift.

struct BoardingActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var minutes: Int
    var text: String
  }

  var route: String
  var stopName: String
}

struct BoardingLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BoardingActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 6) {
        Text(context.attributes.route)
          .font(.headline)
        Text(context.state.text)
          .font(.body)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
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
            .font(.body)
        }
      } compactLeading: {
        Image(systemName: "bus")
      } compactTrailing: {
        Text(minuteLabel(context.state.minutes))
      } minimal: {
        Text(minuteLabel(context.state.minutes))
      }
    }
  }
}

private func minuteLabel(_ minutes: Int) -> String {
  "\(minutes)m"
}

@main
struct BoardingLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    BoardingLiveActivityWidget()
  }
}
