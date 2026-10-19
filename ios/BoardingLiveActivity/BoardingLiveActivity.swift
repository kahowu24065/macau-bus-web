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
/// BoardingActivityAttributes is ios/Shared/BoardingActivityAttributes.swift,
/// compiled into this extension and into the app.

struct BoardingLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BoardingActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 6) {
        Text(context.attributes.route)
          .font(.headline)
        if !context.attributes.stopName.isEmpty {
          Text(context.attributes.stopName)
            .font(.subheadline)
        }
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
          VStack(alignment: .leading, spacing: 2) {
            if !context.attributes.stopName.isEmpty {
              Text(context.attributes.stopName)
                .font(.headline)
            }
            Text(context.state.text)
              .font(.body)
          }
        }
      } compactLeading: {
        Text(context.attributes.stopName.isEmpty ? context.attributes.route : context.attributes.stopName)
          .font(.caption2)
          .lineLimit(1)
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
