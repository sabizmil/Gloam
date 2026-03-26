# BUG-014: macOS Notifications Silently Fail

*Investigated: 2026-03-26*

## Summary

macOS local notifications fire without error but never appear. The `sendTestNotification()` method returns `true` (success), yet no banner/alert is displayed.

## Investigation Findings

### 1. The Delegate Override Problem (ROOT CAUSE)

The `AppDelegate.swift` currently does this:

```swift
override func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self  // <-- PROBLEM
    super.applicationDidFinishLaunching(notification)
}
```

Meanwhile, the plugin's own `register` method (in `FlutterLocalNotificationsPlugin.swift` line 102-113) already sets the delegate to its own instance:

```swift
public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(...)
    let instance = FlutterLocalNotificationsPlugin.init(fromChannel: channel)
    if #available(macOS 10.14, *) {
        let center = UNUserNotificationCenter.current()
        center.delegate = instance  // Plugin sets ITSELF as delegate
    }
    registrar.addMethodCallDelegate(instance, channel: channel)
}
```

**The execution order is:**
1. `AppDelegate.applicationDidFinishLaunching` runs, sets `delegate = self` (the AppDelegate)
2. `super.applicationDidFinishLaunching` triggers plugin registration
3. `RegisterGeneratedPlugins` is called (via `MainFlutterWindow.awakeFromNib`)
4. `FlutterLocalNotificationsPlugin.register` runs, sets `delegate = instance` (the plugin)

Wait -- actually `MainFlutterWindow.awakeFromNib()` calls `RegisterGeneratedPlugins`, which happens during window NIB loading, which may run BEFORE `applicationDidFinishLaunching`. The exact order depends on the macOS app lifecycle.

**But the real problem is even more fundamental:** `UNUserNotificationCenter` has a **single delegate** property. Only ONE object can be the delegate. The plugin's `register` method sets the delegate to its plugin instance. Our `AppDelegate` sets the delegate to `self`. Whichever runs last wins, and the other loses its delegate callbacks.

- If `AppDelegate` wins: `delegate = self` (the AppDelegate). The AppDelegate is a `FlutterAppDelegate` which does NOT implement `userNotificationCenter(_:willPresent:withCompletionHandler:)`. Therefore, foreground notifications are suppressed (macOS default behavior).
- If the plugin wins: `delegate = instance`. The plugin correctly implements `willPresent` with banner/alert/sound options. Notifications work.

**What's actually happening:** The `MainFlutterWindow.awakeFromNib()` registers plugins during NIB loading. Then `applicationDidFinishLaunching` fires and our code **overwrites** the plugin's delegate with `self`. Since `FlutterAppDelegate` does not conform to `UNUserNotificationCenterDelegate` with a `willPresent` implementation, macOS silently drops foreground notifications.

The official example macOS AppDelegate for flutter_local_notifications does NOT set the delegate at all -- it's a plain default:
```swift
class AppDelegate: FlutterAppDelegate {
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
```

### 2. The sendTestNotification() Creates a Separate Plugin Instance

`sendTestNotification()` creates a brand-new `FlutterLocalNotificationsPlugin` instance via `FlutterLocalNotificationsPlugin()`. This new instance:
- Calls `initialize` which registers itself but does NOT re-set the `UNUserNotificationCenter.delegate` (only the static `register` method does that)
- Calls `show` which adds a `UNNotificationRequest` to the notification center
- The notification center dispatches the notification, but calls `willPresent` on whatever object is currently the delegate
- If the delegate is the AppDelegate (which doesn't implement `willPresent`), the notification is silently swallowed

### 3. No Permission Issues Found

- The `DarwinInitializationSettings()` defaults request alert/badge/sound permissions on init (all true by default)
- The `requestPermissions` call in `initialize()` explicitly asks for alert/badge/sound
- The macOS deployment target is 10.15, which is >= the plugin's minimum of 10.14
- Entitlements are standard (sandbox enabled, network client enabled)
- No special entitlements are needed for `UNUserNotificationCenter` local notifications in a sandboxed app

### 4. No Entitlement Issues

The `com.apple.security.app-sandbox` is `true` in both Debug and Release entitlements. Local notifications work fine under sandbox -- only push notifications (remote) require a push notification entitlement. Local notifications via `UNUserNotificationCenter` just need user permission, which the plugin requests.

### 5. Podfile Deployment Target

Podfile sets `platform :osx, '10.15'`, plugin requires `10.14`. No conflict.

## Root Cause

**The `AppDelegate.swift` line `UNUserNotificationCenter.current().delegate = self` overwrites the plugin's delegate assignment, breaking the plugin's ability to present foreground notifications.**

This is the opposite of what was intended. The comment says "Required for flutter_local_notifications to present notifications" but it actually breaks them. The iOS setup guide says to add this line, but on macOS the plugin handles it internally in its `register` method.

## Fix

### Primary Fix: Remove the delegate override from AppDelegate

Remove the entire `applicationDidFinishLaunching` override. The plugin sets up its own delegate during registration.

**AppDelegate.swift should become:**

```swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
```

That's it. The `import UserNotifications` line and the `applicationDidFinishLaunching` override should both be removed.

### Secondary Fix: Fix the sendTestNotification() isolated instance problem

The `sendTestNotification()` static method creates a throwaway `FlutterLocalNotificationsPlugin`. While the `show` call will work if the main plugin instance is correctly set as delegate, there's a subtle issue: this throwaway instance calls `initialize`, which sets `UserDefaults` presentation options. If the main instance hasn't initialized yet, this is fine. If it has, the throwaway's defaults may not include the same configuration.

More importantly, the throwaway instance doesn't call `requestPermissions`. If this is the first time running the app, the user may not have granted permission yet.

**Recommendation:** Make `sendTestNotification()` use the same singleton plugin instance, or at minimum add a `requestPermissions` call.

### Implementation Plan

1. **Edit `macos/Runner/AppDelegate.swift`**: Remove the `applicationDidFinishLaunching` override and the `import UserNotifications`
2. **Clean build**: `pkill gloam; scripts/build_macos.sh` (per MEMORY.md build workflow)
3. **Test**: Open app, go to Settings > Notifications > Send Test Notification
4. **Verify**: Notification banner should appear in top-right corner of screen
5. **Check System Preferences**: If still not working, verify System Settings > Notifications > gloam is set to allow notifications (Banners or Alerts)

### Verification Checklist

- [ ] Test notification appears when clicking "Send Test Notification" in settings
- [ ] Notifications appear when a message arrives in a non-active room
- [ ] Notifications appear when the app is in the foreground but a different room is selected
- [ ] Notifications do NOT appear for the currently active room
- [ ] Notification sound plays
- [ ] macOS Notification Center shows notification history

## Related Files

- `/Users/sabizmil/Developer/matrix-chat/macos/Runner/AppDelegate.swift`
- `/Users/sabizmil/Developer/matrix-chat/lib/services/notification_service.dart`
- `/Users/sabizmil/Developer/matrix-chat/macos/Runner/DebugProfile.entitlements`
- `/Users/sabizmil/Developer/matrix-chat/macos/Runner/Release.entitlements`
- `~/.pub-cache/hosted/pub.dev/flutter_local_notifications-18.0.1/macos/Classes/FlutterLocalNotificationsPlugin.swift` (plugin source, read-only)
