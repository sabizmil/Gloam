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
      case "fireNativeNotification":
        // Debug path — fires a UNUserNotificationCenter notification directly,
        // bypassing flutter_local_notifications. Used to isolate whether a
        // failure is in the plugin or in our iOS configuration.
        let args = call.arguments as? [String: Any?]
        let title = (args?["title"] as? String) ?? "Gloam native"
        let body = (args?["body"] as? String) ?? "Native test"
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if #available(iOS 15.0, *) {
          content.interruptionLevel = .active
        }
        let request = UNNotificationRequest(
          identifier: "gloam.native.test.\(Int(Date().timeIntervalSince1970))",
          content: content,
          trigger: nil  // immediate
        )
        UNUserNotificationCenter.current().add(request) { error in
          DispatchQueue.main.async {
            if let e = error {
              result(FlutterError(code: "native_notif_error", message: e.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        }
      case "notificationAuthStatus":
        // Returns raw UNAuthorizationStatus so we can tell "not determined"
        // apart from "denied" and "authorized".
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          DispatchQueue.main.async {
            let statusString: String
            switch settings.authorizationStatus {
            case .notDetermined: statusString = "notDetermined"
            case .denied:        statusString = "denied"
            case .authorized:    statusString = "authorized"
            case .provisional:   statusString = "provisional"
            case .ephemeral:     statusString = "ephemeral"
            @unknown default:    statusString = "unknown"
            }
            result([
              "authorizationStatus": statusString,
              "alertSetting":        settings.alertSetting == .enabled,
              "badgeSetting":        settings.badgeSetting == .enabled,
              "soundSetting":        settings.soundSetting == .enabled,
              "lockScreenSetting":   settings.lockScreenSetting == .enabled,
              "notificationCenterSetting": settings.notificationCenterSetting == .enabled,
            ])
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Register as UNUserNotificationCenter delegate so notifications appear
    // in the foreground too. The flutter_local_notifications plugin normally
    // owns this, but setting it here as a safety net ensures willPresent is
    // handled even if the plugin's delegate hook fails on iOS 26+.
    UNUserNotificationCenter.current().delegate = self
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show banner + badge + sound + add to notification list when in foreground.
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }
}
