import Flutter
import Foundation
import Intents
import UIKit
import UserNotifications

/// Puts the MBKa artwork on boarding banners and in Notification Center.
///
/// A `UNNotificationAttachment` is only a thumbnail, and 1.0.54 named it
/// `mbka_app_icon` with no file extension, so iOS stored a typeless file and
/// showed a generic icon. The leading picture is the sender image from
/// `INSendMessageIntent`, built from `MBKaNotificationIcon.png` in the app
/// bundle. The same request stays a plugin notification (`payload` /
/// `presentBanner`) so a foreground banner still plays the default sound.
enum BoardingNotificationIcon {
  static let channelName = "mbka/boarding_notification"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "schedule":
        let args = call.arguments as? [String: Any] ?? [:]
        schedule(args: args, result: result)
      case "cancel":
        let args = call.arguments as? [String: Any] ?? [:]
        let ids = args["ids"] as? [Int] ?? []
        let names = ids.map { String($0) }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: names)
        center.removeDeliveredNotifications(withIdentifiers: names)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func schedule(args: [String: Any], result: @escaping FlutterResult) {
    guard let id = args["id"] as? Int,
          let title = args["title"] as? String,
          let body = args["body"] as? String else {
      result(FlutterError(code: "bad_args", message: "boarding notification needs id, title, body", details: nil))
      return
    }
    let atMillis = args["atMillis"] as? Int
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    // Keys the flutter_local_notifications foreground delegate looks for.
    content.userInfo = [
      "NotificationId": id,
      "presentAlert": true,
      "presentSound": true,
      "presentBadge": false,
      "presentBanner": true,
      "presentList": true,
      "payload": "boarding",
    ]
    if let iconURL = Bundle.main.url(forResource: "MBKaNotificationIcon", withExtension: "png"),
       let attachment = try? UNNotificationAttachment(
         identifier: "mbka_app_icon.png",
         url: iconURL,
         options: nil
       ) {
      content.attachments = [attachment]
    }

    let delivered = contentWithAppIcon(content, title: title, body: body)
    let trigger = triggerFor(atMillis: atMillis)
    let request = UNNotificationRequest(
      identifier: String(id),
      content: delivered,
      trigger: trigger
    )
    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "schedule", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    }
  }

  /// Leading icon slot. Falls back to the original content, which still has
  /// the PNG attachment, when the system will not accept the intent.
  private static func contentWithAppIcon(
    _ content: UNMutableNotificationContent,
    title: String,
    body: String
  ) -> UNNotificationContent {
    guard let image = UIImage(named: "MBKaNotificationIcon") ?? iconFromBundle(),
          let data = image.pngData() else {
      return content
    }
    let avatar = INImage(imageData: data)
    let sender = INPerson(
      personHandle: INPersonHandle(value: "mbka", type: .unknown),
      nameComponents: nil,
      displayName: title,
      image: avatar,
      contactIdentifier: nil,
      customIdentifier: "mbka",
      isMe: false,
      suggestionType: .none
    )
    let intent = INSendMessageIntent(
      recipients: nil,
      outgoingMessageType: .outgoingMessageText,
      content: body,
      speakableGroupName: nil,
      conversationIdentifier: "mbka-boarding",
      serviceName: nil,
      sender: sender,
      attachments: nil
    )
    intent.setImage(avatar, forParameterNamed: \.sender)
    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming
    interaction.donate(completion: nil)
    guard let updated = try? content.updating(from: intent),
          let mutable = updated.mutableCopy() as? UNMutableNotificationContent else {
      return content
    }
    if mutable.title.isEmpty { mutable.title = title }
    if mutable.body.isEmpty { mutable.body = body }
    mutable.sound = .default
    mutable.userInfo = content.userInfo
    if mutable.attachments.isEmpty {
      mutable.attachments = content.attachments
    }
    return mutable
  }

  private static func iconFromBundle() -> UIImage? {
    guard let url = Bundle.main.url(forResource: "MBKaNotificationIcon", withExtension: "png") else {
      return nil
    }
    return UIImage(contentsOfFile: url.path)
  }

  private static func triggerFor(atMillis: Int?) -> UNNotificationTrigger? {
    guard let atMillis = atMillis else { return nil }
    let at = Date(timeIntervalSince1970: Double(atMillis) / 1000.0)
    let interval = at.timeIntervalSinceNow
    if interval < 1 {
      return nil
    }
    return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
  }
}
