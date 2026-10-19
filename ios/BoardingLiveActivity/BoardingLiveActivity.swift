import ActivityKit
import SwiftUI
import WidgetKit

/// One Live Activity for the boarding reminder.
///
/// Phones with a Dynamic Island show this configuration there. Phones without
/// one show the same activity on the Lock Screen and in the notification list.
/// There is no second notification. The countdown is labeled as a predicted
/// arrival (預測到站時間尚餘), never a remaining-stop count.
///
/// When content-state carries endsAt, the system Text(timerInterval:) drives
/// the minute display so it keeps ticking without APNs Live Activity pushes.
/// The label sits on the same line, in front of that countdown.

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
        remainingView(context.state, label: predictedLabel(context.attributes))
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
            remainingView(context.state, label: predictedLabel(context.attributes))
              .font(.body)
          }
        }
      } compactLeading: {
        Text(predictedLabel(context.attributes))
          .font(.caption2)
          .lineLimit(1)
          .minimumScaleFactor(0.55)
      } compactTrailing: {
        remainingBadge(context.state)
      } minimal: {
        remainingBadge(context.state)
      }
    }
  }
}

private let defaultPredictedLabel = "預測到站時間尚餘"

private func predictedLabel(_ attributes: BoardingActivityAttributes) -> String {
  let custom = attributes.etaLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  return custom.isEmpty ? defaultPredictedLabel : custom
}

@ViewBuilder
private func remainingBadge(_ state: BoardingActivityAttributes.ContentState) -> some View {
  remainingTime(state)
    .multilineTextAlignment(.trailing)
}

/// Label, then the remaining time, on one line so the island and banner stay short.
@ViewBuilder
private func remainingView(_ state: BoardingActivityAttributes.ContentState, label: String) -> some View {
  if state.minutes <= 0, !state.text.isEmpty, endsDate(state).map({ $0 > Date() }) != true {
    Text(state.text)
  } else {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(label)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
      Spacer(minLength: 4)
      remainingTime(state)
        .layoutPriority(1)
    }
  }
}

@ViewBuilder
private func remainingTime(_ state: BoardingActivityAttributes.ContentState) -> some View {
  if let ends = endsDate(state), ends > Date() {
    // Timer ticks every second on the Lock Screen without a push token.
    Text(timerInterval: Date()...ends, countsDown: true)
      .monospacedDigit()
  } else if state.minutes <= 0, !state.text.isEmpty {
    Text(state.text)
      .lineLimit(1)
  } else {
    Text(minuteLabel(state.minutes))
      .monospacedDigit()
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
