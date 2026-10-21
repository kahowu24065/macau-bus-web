import AppIntents

/// Expanded Dynamic Island tap target.
///
/// A compact or minimal tap is handled by iOS and opens the app. Touch and
/// hold, or a sideways swipe, is what expands the island. This intent is only
/// for the expanded card: the button runs here, in the background, and does
/// not bring MBKa forward. `openAppWhenRun` stays false. There is no URL.
@available(iOS 17.0, *)
public struct BoardingIslandStayIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Boarding reminder"
  public static var openAppWhenRun: Bool = false
  public static var isDiscoverable: Bool = false

  public init() {}

  public func perform() async throws -> some IntentResult {
    .result()
  }
}
