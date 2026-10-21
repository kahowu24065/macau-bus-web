import ActivityKit
import SwiftUI
import WidgetKit

/// One Live Activity for the boarding reminder.
///
/// The predicted-arrival phrase is its own line. A system timer on the same
/// row claims the width and clips the label, which is what 1.0.46 did.
/// Lock Screen shows 「預測到站時間尚餘」 and a large 「N 分鐘」. Compact
/// Dynamic Island uses the short form 「預測」 so the time still fits.

struct BoardingLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BoardingActivityAttributes.self) { context in
      let label = fullLabel(state: context.state, attributes: context.attributes)
      VStack(alignment: .leading, spacing: 4) {
        Text(context.attributes.route)
          .font(.headline)
          .lineLimit(1)
        Text(label)
          .font(.headline)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        timeRow(context.state, label: label)
        if !context.attributes.stopName.isEmpty {
          Text(context.attributes.stopName)
            .font(.subheadline)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    } dynamicIsland: { context in
      let label = fullLabel(state: context.state, attributes: context.attributes)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.route)
            .font(.headline)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(minuteWords(displayMinutes(context.state), label: label))
            .font(.title2.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 2) {
            Text(label)
              .font(.subheadline.weight(.semibold))
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
            if !context.attributes.stopName.isEmpty {
              Text(context.attributes.stopName)
                .font(.caption)
                .lineLimit(1)
            }
            if let ends = endsDate(context.state), ends > Date() {
              Text(timerInterval: Date()...ends, countsDown: true)
                .font(.body.monospacedDigit())
                .lineLimit(1)
            }
          }
        }
      } compactLeading: {
        Text(shortLabel(label))
          .font(.caption.weight(.semibold))
          .lineLimit(1)
      } compactTrailing: {
        Text(compactTime(displayMinutes(context.state), label: label))
          .font(.caption.weight(.bold))
          .monospacedDigit()
          .lineLimit(1)
      } minimal: {
        Text(compactTime(displayMinutes(context.state), label: label))
          .font(.caption2.weight(.bold))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
    }
  }
}

private let defaultPredictedLabel = "預測到站時間尚餘"

private func fullLabel(
  state: BoardingActivityAttributes.ContentState,
  attributes: BoardingActivityAttributes
) -> String {
  for candidate in [state.etaLabel, attributes.etaLabel] {
    let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmed.isEmpty { return trimmed }
  }
  return defaultPredictedLabel
}

/// Two characters for the compact island. The full phrase does not fit there.
private func shortLabel(_ label: String) -> String {
  if label.contains("预测") { return "预计" }
  if label.hasPrefix("Predicted") || label.localizedCaseInsensitiveContains("arrival") {
    return "ETA"
  }
  if label.hasPrefix("Chegada") || label.localizedCaseInsensitiveContains("prevista") {
    return "ETA"
  }
  return "預測"
}

private func endsDate(_ state: BoardingActivityAttributes.ContentState) -> Date? {
  guard let raw = state.endsAt, raw > 1_000_000_000 else { return nil }
  let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
  return Date(timeIntervalSince1970: seconds)
}

/// Whole minutes still to show. endsAt wins; otherwise the last pushed minutes.
private func displayMinutes(_ state: BoardingActivityAttributes.ContentState) -> Int {
  if let ends = endsDate(state) {
    let seconds = ends.timeIntervalSinceNow
    if seconds <= 0 { return 0 }
    return max(1, Int((seconds / 60).rounded()))
  }
  return max(0, state.minutes)
}

private func usesSimplified(_ label: String) -> Bool {
  label.contains("预测") || label.contains("分钟")
}

private func usesEnglish(_ label: String) -> Bool {
  label.hasPrefix("Predicted") || label.localizedCaseInsensitiveContains("arrival")
}

private func minuteWords(_ minutes: Int, label: String) -> String {
  if usesSimplified(label) { return "\(minutes) 分钟" }
  if usesEnglish(label) || label.hasPrefix("Chegada") {
    return minutes == 1 ? "1 min" : "\(minutes) min"
  }
  return "\(minutes) 分鐘"
}

private func compactTime(_ minutes: Int, label: String) -> String {
  if usesEnglish(label) || label.hasPrefix("Chegada") { return "\(minutes)m" }
  return "\(minutes)分"
}

/// Large 「N 分鐘」 plus a bounded timer. The timer never shares a row with the phrase.
@ViewBuilder
private func timeRow(
  _ state: BoardingActivityAttributes.ContentState,
  label: String
) -> some View {
  let minutes = displayMinutes(state)
  HStack(alignment: .firstTextBaseline, spacing: 8) {
    Text(minuteWords(minutes, label: label))
      .font(.title.weight(.bold))
      .monospacedDigit()
      .lineLimit(1)
      .layoutPriority(1)
    if let ends = endsDate(state), ends > Date() {
      Text(timerInterval: Date()...ends, countsDown: true)
        .font(.title3.monospacedDigit())
        .lineLimit(1)
        .frame(maxWidth: 96, alignment: .leading)
        .clipped()
    } else if minutes == 0, !state.text.isEmpty {
      Text(state.text)
        .font(.subheadline)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

@main
struct BoardingLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    BoardingLiveActivityWidget()
  }
}
