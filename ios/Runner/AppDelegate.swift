import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // `chat.gloam/platform` — icon badge from BadgeService.
    // focusWindow is a no-op on iOS: the OS handles bringing the app
    // forward on notification tap automatically.
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "chat.gloam.platform")!
    let channel = FlutterMethodChannel(
      name: "chat.gloam/platform",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setBadge":
        let args = call.arguments as? [String: Any?]
        let count = (args?["count"] as? Int) ?? 0
        DispatchQueue.main.async {
          if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
          } else {
            UIApplication.shared.applicationIconBadgeNumber = count
          }
        }
        result(nil)
      case "focusWindow":
        // iOS handles notification-tap routing natively.
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
