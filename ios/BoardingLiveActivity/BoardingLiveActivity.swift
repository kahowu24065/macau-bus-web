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
/// When content-state carries endsAt, the system Text(timerInterval:) drives
/// the minute display so it keeps ticking without APNs Live Activity pushes.

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
        remainingView(context.state)
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
          remainingBadge(context.state)
            .font(.title2)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 2) {
            if !context.attributes.stopName.isEmpty {
              Text(context.attributes.stopName)
                .font(.headline)
            }
            remainingView(context.state)
              .font(.body)
          }
        }
      } compactLeading: {
        Text(context.attributes.stopName.isEmpty ? context.attributes.route : context.attributes.stopName)
          .font(.caption2)
          .lineLimit(1)
      } compactTrailing: {
        remainingBadge(context.state)
      } minimal: {
        remainingBadge(context.state)
      }
    }
  }
}

@ViewBuilder
private func remainingBadge(_ state: BoardingActivityAttributes.ContentState) -> some View {
  if let ends = endsDate(state), ends > Date() {
    Text(timerInterval: Date()...ends, countsDown: true)
      .monospacedDigit()
      .multilineTextAlignment(.trailing)
  } else {
    Text(minuteLabel(state.minutes))
  }
}

@ViewBuilder
private func remainingView(_ state: BoardingActivityAttributes.ContentState) -> some View {
  if let ends = endsDate(state), ends > Date() {
    // Timer ticks every second on the Lock Screen without a push token.
    Text(timerInterval: Date()...ends, countsDown: true)
      .monospacedDigit()
  } else if !state.text.isEmpty {
    Text(state.text)
  } else {
    Text(minuteLabel(state.minutes))
  }
}

private func endsDate(_ state: BoardingActivityAttributes.ContentState) -> Date? {
  guard let endsAt = state.endsAt, endsAt > 1_000_000_000 else { return nil }
  return Date(timeIntervalSince1970: endsAt)
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
