import CoreLocation
import Flutter
import UIKit

/// Asks iOS for Always location. Geolocator only requests While Using when
/// NSLocationWhenInUseUsageDescription is present, so the alighting reminder
/// uses this channel instead.
final class AlightingLocationBridge: NSObject, CLLocationManagerDelegate {
  static let shared = AlightingLocationBridge()
  private let manager = CLLocationManager()
  private var pending: FlutterResult?
  private var waiting = false
  private var resigned = false
  private var baseline: CLAuthorizationStatus = .notDetermined

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "mbka/alighting_location", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "authorizationStatus":
        result(Self.name(for: Self.shared.manager.authorizationStatus))
      case "requestAlways":
        Self.shared.requestAlways(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func requestAlways(result: @escaping FlutterResult) {
    let status = manager.authorizationStatus
    if status == .authorizedAlways || status == .denied || status == .restricted {
      result(Self.name(for: status))
      return
    }
    pending = result
    waiting = true
    resigned = false
    baseline = status
    manager.delegate = self
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    manager.requestAlwaysAuthorization()
    // If iOS will not present the prompt, the app never resigns active.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self, self.waiting, !self.resigned else { return }
      self.finish(self.manager.authorizationStatus)
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard waiting else { return }
    let status = manager.authorizationStatus
    if status != baseline {
      finish(status)
    }
  }

  @objc private func didResignActive() {
    resigned = true
  }

  @objc private func didBecomeActive() {
    guard waiting, resigned else { return }
    finish(manager.authorizationStatus)
  }

  private func finish(_ status: CLAuthorizationStatus) {
    guard waiting else { return }
    waiting = false
    NotificationCenter.default.removeObserver(self)
    let callback = pending
    pending = nil
    callback?(Self.name(for: status))
  }

  private static func name(for status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways:
      return "always"
    case .authorizedWhenInUse:
      return "whenInUse"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "denied"
    }
  }
}
