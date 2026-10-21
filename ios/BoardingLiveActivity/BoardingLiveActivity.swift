import ActivityKit
import SwiftUI
import WidgetKit

/// One Live Activity for the boarding reminder.
///
/// Lock Screen shows 「預測到站時間尚餘」 and a remaining time taken from
/// endsAt. A plain 「9 分鐘」 string is drawn once and stays frozen, so the
/// big line is Text's live relative date, which the system keeps moving.
/// Compact Dynamic Island keeps a short label beside a ticking countdown.
/// Minimal shows that countdown on its own. The timer's width is fixed so the
/// island cannot clip it away. The last minute and arrival replace it with
/// 「快將到達」 and 「已到達」 in the selected language.
///
/// Those system timers keep running after endsAt. The activity's stale date
/// is that instant, so the widget reloads into the arrived phrase. A stale
/// flag while the arrival is still ahead does not hide the countdown.

struct BoardingLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BoardingActivityAttributes.self) { context in
      let label = fullLabel(state: context.state, attributes: context.attributes)
      let phase = arrivalPhase(state: context.state, isStale: context.isStale)
      VStack(alignment: .leading, spacing: 4) {
        Text(context.attributes.route)
          .font(.headline)
          .lineLimit(1)
        if phase == .counting {
          Text(label)
            .font(.headline)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
          timeRow(context.state, label: label)
        } else {
          statusLine(
            statusPhrase(state: context.state, attributes: context.attributes, label: label, phase: phase),
            font: .title.weight(.bold)
          )
        }
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
      let phase = arrivalPhase(state: context.state, isStale: context.isStale)
      let phrase = statusPhrase(
        state: context.state,
        attributes: context.attributes,
        label: label,
        phase: phase
      )
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.route)
            .font(.headline)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          if phase == .counting {
            liveClock(context.state, label: label, font: .title3, width: 72)
          } else {
            statusLine(phrase, font: .title3.weight(.bold))
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 2) {
            if phase == .counting {
              Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
              timeRow(context.state, label: label, prominent: false)
            } else {
              statusLine(phrase, font: .title3.weight(.bold))
            }
            if !context.attributes.stopName.isEmpty {
              Text(context.attributes.stopName)
                .font(.caption)
                .lineLimit(1)
            }
          }
        }
      } compactLeading: {
        Text(phase == .counting ? shortLabel(label) : phrase)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(phase == .counting ? 1 : 0.4)
      } compactTrailing: {
        // Always a view. An empty trailing region lets the island drop the
        // countdown that used to sit here (「14分」 / the live timer).
        islandCompactTrailing(
          state: context.state,
          label: label,
          phase: phase
        )
      } minimal: {
        islandMinimal(
          state: context.state,
          label: label,
          phase: phase,
          phrase: phrase
        )
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

private let imminentWindow: TimeInterval = 60

private enum ArrivalPhase { case counting, imminent, arrived }

/// Arrived once endsAt is reached, so the timers are taken out of the tree
/// and cannot run past zero. The minute before that is 「快將到達」.
/// `isStale` is the reload at that instant. It must not replace a countdown
/// that still has minutes left.
private func arrivalPhase(
  state: BoardingActivityAttributes.ContentState,
  isStale: Bool
) -> ArrivalPhase {
  guard let ends = state.predictedArrival() else { return .counting }
  let remaining = ends.timeIntervalSinceNow
  if remaining <= 0 || (isStale && remaining <= 1) { return .arrived }
  if remaining <= imminentWindow { return .imminent }
  return .counting
}

@ViewBuilder
private func islandCompactTrailing(
  state: BoardingActivityAttributes.ContentState,
  label: String,
  phase: ArrivalPhase
) -> some View {
  switch phase {
  case .counting:
    liveClock(state, label: label, font: .caption, width: 52)
  case .imminent, .arrived:
    EmptyView()
  }
}

@ViewBuilder
private func islandMinimal(
  state: BoardingActivityAttributes.ContentState,
  label: String,
  phase: ArrivalPhase,
  phrase: String
) -> some View {
  switch phase {
  case .counting:
    liveClock(state, label: label, font: .caption2, minScale: 0.4)
  case .imminent, .arrived:
    Text(phrase)
      .font(.caption2.weight(.bold))
      .lineLimit(1)
      .minimumScaleFactor(0.35)
  }
}

private func statusPhrase(
  state: BoardingActivityAttributes.ContentState,
  attributes: BoardingActivityAttributes,
  label: String,
  phase: ArrivalPhase
) -> String {
  let explicit = phase == .arrived
    ? (state.arrivedText ?? attributes.arrivedText)
    : (state.imminentText ?? attributes.imminentText)
  let trimmed = explicit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  if !trimmed.isEmpty { return trimmed }
  return phase == .arrived ? fallbackArrived(label) : fallbackImminent(label)
}

@ViewBuilder
private func statusLine(_ phrase: String, font: Font) -> some View {
  Text(phrase)
    .font(font)
    .lineLimit(2)
    .minimumScaleFactor(0.5)
    .fixedSize(horizontal: false, vertical: true)
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

private func fallbackArrived(_ label: String) -> String {
  if usesSimplified(label) { return "已到达" }
  if usesEnglish(label) { return "Arrived" }
  if label.hasPrefix("Chegada") || label.localizedCaseInsensitiveContains("prevista") {
    return "Chegou"
  }
  return "已到達"
}

private func fallbackImminent(_ label: String) -> String {
  if usesSimplified(label) { return "即将到达" }
  if usesEnglish(label) { return "Arriving soon" }
  if label.hasPrefix("Chegada") || label.localizedCaseInsensitiveContains("prevista") {
    return "Quase a chegar"
  }
  return "快將到達"
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
  if let ends = state.predictedArrival(), ends > Date() {
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
/// Hours are hidden so a 14-minute ride stays 「14:00」 wide, not 「0:14:00」,
/// which the compact island was clipping to nothing. A fixed width keeps
/// that trailing time on screen next to the short label.
@ViewBuilder
private func liveClock(
  _ state: BoardingActivityAttributes.ContentState,
  label: String,
  font: Font,
  width: CGFloat? = nil,
  minScale: CGFloat = 0.5
) -> some View {
  if let ends = state.predictedArrival(), ends > Date() {
    Text(timerInterval: Date()...ends, countsDown: true, showsHours: false)
      .font(font.weight(.bold).monospacedDigit())
      .multilineTextAlignment(.trailing)
      .lineLimit(1)
      .minimumScaleFactor(minScale)
      .frame(width: width, alignment: .trailing)
  } else {
    Text(compactTime(max(0, state.minutes), label: label))
      .font(font.weight(.bold).monospacedDigit())
      .lineLimit(1)
      .minimumScaleFactor(minScale)
      .frame(width: width, alignment: .trailing)
  }
}

@main
struct BoardingLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    BoardingLiveActivityWidget()
  }
}
