import ActivityKit
import SwiftUI
import WidgetKit

/// One Live Activity for the boarding reminder.
///
/// Lock Screen shows 「預測到站時間尚餘」 and a remaining time taken from
/// endsAt. A plain 「9 分鐘」 string is drawn once and stays frozen, so the
/// big line is Text's live relative date, which the system keeps moving.
/// Compact Dynamic Island uses 「預測」 plus a ticking countdown.

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
          liveClock(context.state, label: label, font: .title3)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 2) {
            Text(label)
              .font(.subheadline.weight(.semibold))
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
            timeRow(context.state, label: label, prominent: false)
            if !context.attributes.stopName.isEmpty {
              Text(context.attributes.stopName)
                .font(.caption)
                .lineLimit(1)
            }
          }
        }
      } compactLeading: {
        Text(shortLabel(label))
          .font(.caption.weight(.semibold))
          .lineLimit(1)
      } compactTrailing: {
        liveClock(context.state, label: label, font: .caption)
      } minimal: {
        liveClock(context.state, label: label, font: .caption2)
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

/// Remaining time under the phrase. endsAt uses a system-updated relative
/// date so the minutes move as time passes. A computed 「N 分鐘」 is only the
/// fallback when endsAt is missing.
@ViewBuilder
private func timeRow(
  _ state: BoardingActivityAttributes.ContentState,
  label: String,
  prominent: Bool = true
) -> some View {
  let font: Font = prominent ? .title.weight(.bold) : .title3.weight(.bold)
  if let ends = endsDate(state), ends > Date() {
    Text(ends, style: .relative)
      .font(font)
      .monospacedDigit()
      .lineLimit(2)
      .minimumScaleFactor(0.6)
      .frame(maxWidth: .infinity, alignment: .leading)
  } else if state.minutes <= 0, !state.text.isEmpty {
    Text(state.text)
      .font(.subheadline)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
  } else {
    Text(minuteWords(max(0, state.minutes), label: label))
      .font(font)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.6)
  }
}

/// Short countdown for the island. timerInterval ticks without a new push.
@ViewBuilder
private func liveClock(
  _ state: BoardingActivityAttributes.ContentState,
  label: String,
  font: Font
) -> some View {
  if let ends = endsDate(state), ends > Date() {
    Text(timerInterval: Date()...ends, countsDown: true)
      .font(font.weight(.bold).monospacedDigit())
      .lineLimit(1)
      .minimumScaleFactor(0.6)
  } else {
    Text(compactTime(max(0, state.minutes), label: label))
      .font(font.weight(.bold).monospacedDigit())
      .lineLimit(1)
      .minimumScaleFactor(0.6)
  }
}

@main
struct BoardingLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    BoardingLiveActivityWidget()
  }
}
