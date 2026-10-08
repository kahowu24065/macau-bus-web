import ActivityKit
import Flutter
import Foundation

/// Live Activity for the boarding reminder.
///
/// Content state is predicted minutes and a localized sentence. It does not
/// carry a stop count. The same activity is rendered by the BoardingLiveActivity
/// widget extension: Dynamic Island on phones that have one, and the Lock Screen
/// plus the notification list on phones that do not.
@available(iOS 16.1, *)
struct BoardingActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var minutes: Int
    var text: String
  }

  var route: String
  var stopName: String
}

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

  private static func startActivity(args: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result(nil)
      return
    }
    let route = args["route"] as? String ?? ""
    let stopName = args["stopName"] as? String ?? ""
    let minutes = args["minutes"] as? Int ?? 0
    let text = args["text"] as? String ?? ""
    let state = BoardingActivityAttributes.ContentState(minutes: minutes, text: text)
    let attributes = BoardingActivityAttributes(route: route, stopName: stopName)
    do {
      let activity: Activity<BoardingActivityAttributes>
      if #available(iOS 16.2, *) {
        let content = ActivityContent(state: state, staleDate: nil)
        activity = try Activity.request(attributes: attributes, content: content, pushType: .token)
      } else {
        activity = try Activity.request(attributes: attributes, contentState: state, pushType: .token)
      }
      BoardingActivityTokenStore.shared.activity = activity
      // The activity is already on screen. Do not wait for its push token;
      // that stream can stay silent, and the method call would never return.
      result(nil)
    } catch {
      result(nil)
    }
  }

  private static func updateActivity(args: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *),
          let activity = BoardingActivityTokenStore.shared.activity else {
      result(nil)
      return
    }
    let minutes = args["minutes"] as? Int ?? 0
    let text = args["text"] as? String ?? ""
    let state = BoardingActivityAttributes.ContentState(minutes: minutes, text: text)
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

  func observeNewActivities(onToken: @escaping (String) -> Void) {
    observeTask?.cancel()
    observeTask = Task {
      do {
        for try await activity in Activity<BoardingActivityAttributes>.activityUpdates {
          let updates = activity.pushTokenUpdates
          Task {
            do {
              for try await data in updates {
                let token = hex(data)
                DispatchQueue.main.async { onToken(token) }
                return
              }
            } catch {
              return
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
