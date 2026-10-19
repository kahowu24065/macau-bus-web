import ActivityKit
import Flutter
import Foundation

/// Live Activity for the boarding reminder.
///
/// Content state is predicted minutes and a localized sentence. The activity
/// label (etaLabel) is shown before that countdown. It does not carry a stop
/// count. The same activity is rendered by the BoardingLiveActivity
/// widget extension: Dynamic Island on phones that have one, and the Lock Screen
/// plus the notification list on phones that do not.
///
/// BoardingActivityAttributes lives in ios/Shared and is compiled into both
/// targets.
enum BoardingLiveActivityBridge {
  static let channelName = "mbka/boarding_live_activity"
  private static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "pushToStartToken":
        pushToStartToken(result: result)
      case "startActivity":
        let args = call.arguments as? [String: Any] ?? [:]
        startActivity(args: args, result: result)
      case "updateActivity":
        let args = call.arguments as? [String: Any] ?? [:]
        updateActivity(args: args, result: result)
      case "endActivity":
        endActivity(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    observeActivityTokens()
  }

  private static func pushToStartToken(result: @escaping FlutterResult) {
    if #available(iOS 17.2, *) {
      BoardingActivityTokenStore.shared.waitForPushToStartToken(result: result)
    } else {
      result(nil)
    }
  }

  /// Tells Dart whether the activity is on screen. A push token, when it
  /// exists, is delivered separately on `activityToken` so this result is not
  /// held open by the token stream.
  private static func finishStart(
    _ result: @escaping FlutterResult,
    started: Bool,
    token: String?,
    error: String?
  ) {
    var payload: [String: Any] = ["started": started]
    if let token, !token.isEmpty {
      payload["token"] = token
    }
    if let error, !error.isEmpty {
      payload["error"] = error
    }
    result(payload)
  }

  private static func startActivity(args: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      log("start skipped: iOS < 16.1")
      finishStart(result, started: false, token: nil, error: "unsupported_os")
      return
    }
    let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
    log("areActivitiesEnabled=\(enabled)")
    if !enabled {
      finishStart(result, started: false, token: nil, error: "activities_disabled")
      return
    }
    let route = args["route"] as? String ?? ""
    let stopName = args["stopName"] as? String ?? ""
    let minutes = args["minutes"] as? Int ?? 0
    let text = args["text"] as? String ?? ""
    let etaLabel = args["etaLabel"] as? String
    let endsAt = (args["endsAt"] as? Double)
      ?? (args["endsAt"] as? NSNumber)?.doubleValue
    let state = BoardingActivityAttributes.ContentState(
      minutes: minutes,
      text: text,
      endsAt: endsAt
    )
    let attributes = BoardingActivityAttributes(route: route, stopName: stopName, etaLabel: etaLabel)

    let activity: Activity<BoardingActivityAttributes>
    let wantsPushToken: Bool
    do {
      activity = try requestActivity(attributes: attributes, state: state, pushToken: true)
      wantsPushToken = true
    } catch {
      logRequestFailure(error, context: "pushType.token")
      // A thrown .token request never creates the activity, so the Lock Screen
      // stays empty. Retry without a push type so the activity can still appear.
      do {
        activity = try requestActivity(attributes: attributes, state: state, pushToken: false)
        wantsPushToken = false
        log("started without a push token after token request failed")
      } catch {
        logRequestFailure(error, context: "pushType.nil")
        finishStart(result, started: false, token: nil, error: errorCode(error))
        return
      }
    }

    let store = BoardingActivityTokenStore.shared
    store.activity = activity
    let immediate = activity.pushToken.flatMap { data in
      data.isEmpty ? nil : hex(data)
    }
    log("started id=\(activity.id) state=\(activity.activityState) push=\(wantsPushToken ? "token" : "none")")
    // The activity is already visible. Do not wait out the token stream before
    // telling Dart; a missing token must not look like a failed start.
    finishStart(result, started: true, token: immediate, error: nil)

    guard wantsPushToken else { return }
    // One reader of this activity's pushTokenUpdates. activityUpdates often
    // never replays the activity Activity.request just returned. If that
    // observer already claimed this id, it delivers the token.
    guard store.claim(activity.id) else {
      log("token reader already claimed id=\(activity.id)")
      return
    }
    let methodChannel = channel
    Task {
      let token = await store.waitForPushToken(activity: activity)
      DispatchQueue.main.async {
        if let token, !token.isEmpty {
          methodChannel?.invokeMethod("activityToken", arguments: token)
        } else {
          log("no push token within 30s id=\(activity.id)")
        }
      }
    }
  }

  @available(iOS 16.1, *)
  private static func requestActivity(
    attributes: BoardingActivityAttributes,
    state: BoardingActivityAttributes.ContentState,
    pushToken: Bool
  ) throws -> Activity<BoardingActivityAttributes> {
    // Current ActivityKit exposes PushType on its own. Activity<T>.PushType
    // does not compile on the Xcode Codemagic uses.
    if #available(iOS 16.2, *) {
      if pushToken {
        return try Activity.request(
          attributes: attributes,
          content: ActivityContent(state: state, staleDate: nil),
          pushType: .token
        )
      }
      return try Activity.request(
        attributes: attributes,
        content: ActivityContent(state: state, staleDate: nil),
        pushType: nil
      )
    }
    if pushToken {
      return try Activity.request(
        attributes: attributes,
        contentState: state,
        pushType: .token
      )
    }
    return try Activity.request(
      attributes: attributes,
      contentState: state,
      pushType: nil
    )
  }

  private static func log(_ message: String) {
    NSLog("%@", "[BoardingLiveActivity] \(message)" as NSString)
  }

  private static func logRequestFailure(_ error: Error, context: String) {
    let ns = error as NSError
    log("\(context) failed domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) raw=\(error)")
  }

  /// Stable code for Dart. The full NSError is already in the device log.
  private static func errorCode(_ error: Error) -> String {
    let text = String(describing: error)
    let known = [
      "denied",
      "unentitled",
      "unsupported",
      "visibility",
      "persistenceFailure",
      "attributesTooLarge",
      "globalMaximumExceeded",
      "targetMaximumExceeded",
    ]
    for name in known where text.contains(name) {
      if name == "globalMaximumExceeded" || name == "targetMaximumExceeded" {
        return "maximum"
      }
      return name
    }
    return "request_failed"
  }

  private static func updateActivity(args: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *),
          let activity = BoardingActivityTokenStore.shared.activity else {
      result(nil)
      return
    }
    let minutes = args["minutes"] as? Int ?? 0
    let text = args["text"] as? String ?? ""
    let endsAt = (args["endsAt"] as? Double)
      ?? (args["endsAt"] as? NSNumber)?.doubleValue
    let state = BoardingActivityAttributes.ContentState(
      minutes: minutes,
      text: text,
      endsAt: endsAt
    )
    Task {
      if #available(iOS 16.2, *) {
        await activity.update(ActivityContent(state: state, staleDate: nil))
      } else {
        await activity.update(using: state)
      }
      DispatchQueue.main.async { result(nil) }
    }
  }

  private static func endActivity(result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *),
          let activity = BoardingActivityTokenStore.shared.activity else {
      result(nil)
      return
    }
    let state = BoardingActivityAttributes.ContentState(minutes: 0, text: "")
    Task {
      if #available(iOS 16.2, *) {
        await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
      } else {
        await activity.end(using: state, dismissalPolicy: .immediate)
      }
      BoardingActivityTokenStore.shared.activity = nil
      DispatchQueue.main.async { result(nil) }
    }
  }

  private static func observeActivityTokens() {
    guard #available(iOS 16.1, *) else { return }
    BoardingActivityTokenStore.shared.observeNewActivities { token in
      channel?.invokeMethod("activityToken", arguments: token)
    }
  }
}

@available(iOS 16.1, *)
final class BoardingActivityTokenStore {
  static let shared = BoardingActivityTokenStore()
  var activity: Activity<BoardingActivityAttributes>?
  private var observeTask: Task<Void, Never>?

  private var claimedIds: Set<String> = []
  private let claimLock = NSLock()

  /// Returns false when this activity's push-token stream is already being read.
  /// Two readers on one `pushTokenUpdates` sequence can drop the token.
  func claim(_ activityId: String) -> Bool {
    claimLock.lock()
    defer { claimLock.unlock() }
    if claimedIds.contains(activityId) { return false }
    claimedIds.insert(activityId)
    return true
  }

  /// Hex APNs token for this activity, or nil after a few seconds.
  ///
  /// Reads `activity.pushToken` and then that same activity's `pushTokenUpdates`.
  /// The wait is bounded so a silent stream still returns.
  func waitForPushToken(activity: Activity<BoardingActivityAttributes>) async -> String? {
    if let existing = activity.pushToken, !existing.isEmpty {
      return hex(existing)
    }
    return await Self.firstToken(from: activity.pushTokenUpdates, timeoutSeconds: 30)
  }

  func observeNewActivities(onToken: @escaping (String) -> Void) {
    observeTask?.cancel()
    observeTask = Task {
      do {
        for try await activity in Activity<BoardingActivityAttributes>.activityUpdates {
          guard claim(activity.id) else { continue }
          let watched = activity
          Task {
            if let token = await self.waitForPushToken(activity: watched), !token.isEmpty {
              DispatchQueue.main.async { onToken(token) }
            }
          }
        }
      } catch {
        return
      }
    }
  }

  @available(iOS 17.2, *)
  func waitForPushToStartToken(result: @escaping FlutterResult) {
    Task {
      let token = await Self.firstToken(
        from: Activity<BoardingActivityAttributes>.pushToStartTokenUpdates,
        timeoutSeconds: 2
      )
      DispatchQueue.main.async { result(token) }
    }
  }

  /// Resolves on the first token or when [timeoutSeconds] elapses.
  ///
  /// A task group cannot be used here. It waits until every child finishes,
  /// and ActivityKit's token stream does not finish or honor cancellation when
  /// no token is coming, so the group would never return.
  private static func firstToken<S: AsyncSequence>(
    from updates: S,
    timeoutSeconds: Double
  ) async -> String? where S.Element == Data {
    let once = TokenOnce()
    return await withCheckedContinuation { continuation in
      let reader = Task {
        var token: String?
        do {
          for try await data in updates {
            token = hex(data)
            break
          }
        } catch {
          token = nil
        }
        if once.claim() {
          continuation.resume(returning: token)
        }
      }
      Task {
        try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
        if once.claim() {
          continuation.resume(returning: nil)
        }
        reader.cancel()
      }
    }
  }
}

private final class TokenOnce {
  private let lock = NSLock()
  private var fired = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if fired { return false }
    fired = true
    return true
  }
}

private func hex(_ data: Data) -> String {
  data.map { String(format: "%02x", $0) }.joined()
}
