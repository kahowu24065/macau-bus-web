import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications presents scheduled boarding banners (sound, so
    // iOS vibrates) while the app is in the foreground. The plugin reads
    // presentBanner / presentSound off each request.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    if #available(iOS 17.0, *) {
      // The expanded-island button runs this intent in the app process.
      // Keep the type linked. It does not open the UI.
      _ = BoardingIslandStayIntent.openAppWhenRun
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    BoardingLiveActivityBridge.register(messenger: messenger)
    BoardingNotificationIcon.register(messenger: messenger)
    AlightingLocationBridge.register(messenger: messenger)
  }
}
