# BUG-014: macOS notifications silently fail — test button shows success but no notification appears

- **Reported**: 2026-03-26
- **Status**: Open
- **Priority**: P1 (broken feature)

## Description

Push notifications do not work on macOS. The "send test notification" button in Settings shows a green checkmark (indicating `sendTestNotification()` returned `true`) but no macOS notification banner, alert, or Notification Center entry ever appears. The user has confirmed that notification permissions are enabled in System Settings (Allow Notifications = on, all delivery methods checked, Alert Style = Temporary, Sound = on).

This is distinct from the archived BUG-006 which addressed an earlier notification issue. The underlying native setup was never completed.

## Steps to Reproduce

1. Launch Gloam on macOS
2. Open Settings > Notifications
3. Tap "Send test notification"
4. Observe: button shows spinner, then green checkmark (success)
5. Observe: no macOS notification appears — not in banners, not in Notification Center

Also reproducible via real messages:
1. Open a second Matrix client and send a message to a room Gloam is joined to
2. Ensure Gloam is not focused on that room (or is backgrounded)
3. Observe: no notification appears

## Expected Behavior

A macOS notification banner should appear with title "Gloam" and body "Notifications are working." (for the test case), or the sender/message content (for real messages).

## Actual Behavior

`plugin.show()` completes without throwing an exception, `sendTestNotification()` returns `true`, the UI shows a success checkmark, but macOS silently discards the notification. No banner, no sound, no Notification Center entry.

## Root Cause Analysis

There are two issues, one critical and one minor.

### Issue 1 (Critical): Missing `UNUserNotificationCenter` delegate in AppDelegate.swift

**File**: `macos/Runner/AppDelegate.swift` (lines 1-13)

The `flutter_local_notifications` plugin on macOS requires the native `AppDelegate` to configure itself as the `UNUserNotificationCenter` delegate. Without this, macOS has no delegate to handle the notification presentation callback (`userNotificationCenter(_:willPresent:withCompletionHandler:)`), so the system silently drops all local notifications.

The current AppDelegate:

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

It is missing:
1. `import UserNotifications` — needed for `UNUserNotificationCenter` API
2. Setting `UNUserNotificationCenter.current().delegate = self` in `applicationDidFinishLaunching(_:)` — this is the critical line that tells macOS to route notification presentation through the FlutterAppDelegate (which implements `UNUserNotificationCenterDelegate` via the plugin)

This is a well-documented requirement in the `flutter_local_notifications` package README under "macOS setup". `FlutterAppDelegate` already conforms to `UNUserNotificationCenterDelegate` (the plugin extends it), but macOS won't call any delegate methods unless `delegate` is explicitly assigned. Without the delegate assignment, `plugin.show()` succeeds at the plugin layer (no error thrown) but the OS-level notification is never presented.

### Issue 2 (Minor): `sendTestNotification()` creates a throwaway plugin instance

**File**: `lib/services/notification_service.dart` (lines 74-106)

The static `sendTestNotification()` method creates a brand-new `FlutterLocalNotificationsPlugin()` instance (line 79), initializes it (line 87), and calls `show()` (line 88). This works at the Dart level, but:

- It does **not** call `requestPermissions()` on the new instance (unlike `initialize()` on lines 29-34 of the instance method)
- The `catch (_)` on line 103 swallows all exceptions indiscriminately, masking any errors that might help diagnose failures
- The method returns `true` as long as no exception is thrown, which gives false confidence that notifications are working

This is secondary to Issue 1 — even the instance-level `_showNotification()` method (which uses the properly initialized `_plugin`) would fail without the native delegate setup. But the test method's architecture makes the problem harder to diagnose.

### Why the user sees a green checkmark

`sendTestNotification()` returns `true` on line 101 because the Dart-level `plugin.show()` call completes without throwing. The failure is entirely on the native side — macOS accepts the notification request but has no delegate to handle presentation, so it silently drops it. The `catch (_)` block is never reached.

## Implementation Plan

### Fix 1 (Critical): Configure UNUserNotificationCenter delegate in AppDelegate.swift

Update `macos/Runner/AppDelegate.swift` to:

```swift
import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
```

This is the standard setup documented by `flutter_local_notifications` for macOS. The `FlutterAppDelegate` superclass already conforms to `UNUserNotificationCenterDelegate`, so no additional protocol conformance is needed — just the delegate assignment.

### Fix 2 (Minor): Improve `sendTestNotification()` reliability

Refactor `sendTestNotification()` to reuse the singleton plugin instance (or at minimum call `requestPermissions()` on the new instance) and replace the blanket `catch (_)` with proper error logging so failures are diagnosable.

### Effort Estimate

Fix 1: 5 minutes (single file, 3 lines changed). Fix 2: 15 minutes.

## Affected Files

- `macos/Runner/AppDelegate.swift` — add `import UserNotifications`, override `applicationDidFinishLaunching` to set `UNUserNotificationCenter.current().delegate = self`
- `lib/services/notification_service.dart` — (optional) refactor `sendTestNotification()` to request permissions and improve error handling
