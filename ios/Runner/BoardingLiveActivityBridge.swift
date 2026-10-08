import ActivityKit
import Flutter
import Foundation

/// Live Activity for the boarding reminder.
///
/// Content state is predicted minutes and a localized sentence. It does not
/// carry a stop count. The widget UI lives in ios/BoardingLiveActivity and is
/// not an Xcode target yet, so the Dynamic Island will not render until that
/// extension is added and the App ID has the Live Activities capability.
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
      BoardingActivityTokenStore.shared.waitForActivityToken(activity: activity, result: result)
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

  func waitForActivityToken(activity: Activity<BoardingActivityAttributes>, result: @escaping FlutterResult) {
    Task {
      let token = await Self.firstToken(from: activity.pushTokenUpdates, timeoutSeconds: 3)
      DispatchQueue.main.async { result(token) }
    }
  }

  func observeNewActivities(onToken: @escaping (String) -> Void) {
    observeTask?.cancel()
    observeTask = Task {
      for await activity in Activity<BoardingActivityAttributes>.activityUpdates {
        Task {
          if let token = await Self.firstToken(from: activity.pushTokenUpdates, timeoutSeconds: 8) {
            DispatchQueue.main.async { onToken(token) }
          }
        }
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

  private static func firstToken<S: AsyncSequence>(
    from updates: S,
    timeoutSeconds: Double
  ) async -> String? where S.Element == Data {
    await withTaskGroup(of: String?.self) { group in
      group.addTask {
        for await data in updates {
          return hex(data)
        }
        return nil
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }
}

private func hex(_ data: Data) -> String {
  data.map { String(format: "%02x", $0) }.joined()
}
