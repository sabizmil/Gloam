# BUG-006: macOS notifications not showing for new messages

- **Reported**: 2026-03-26
- **Status**: Open
- **Priority**: P1 (broken feature)

## Description

Push notifications are not appearing on macOS when new messages arrive, even though notification permissions are allowed in System Settings.

## Steps to Reproduce

1. Open Gloam on macOS
2. Be in any room (or have the app open/backgrounded)
3. Receive a new message in a different room
4. Observe: no notification banner, sound, or alert appears

## Expected Behavior

A macOS notification banner should appear showing the sender name and message body for new messages in rooms that are not currently focused.

## Actual Behavior

No notification appears at all, despite the system notification permission being granted.

## Root Cause Analysis

Two issues in `lib/services/notification_service.dart`:

### 1. Missing `presentAlert` / `presentSound` / `presentBanner` in notification details (line 81)

```dart
macOS: DarwinNotificationDetails(),
```

`DarwinNotificationDetails()` with no arguments defaults `presentAlert`, `presentSound`, `presentBanner`, and `presentList` all to `false`. This tells macOS **not** to present the notification visually — so even when permission is granted, the OS silently discards the banner.

### 2. No explicit `requestPermissions()` call on macOS plugin (line 18-28)

On macOS, unlike iOS, the `DarwinInitializationSettings` permission request flags during `initialize()` are not sufficient. The macOS plugin requires an explicit call to:

```dart
_plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
    ?.requestPermissions(alert: true, badge: true, sound: true);
```

Without this, the app may never trigger the system permission prompt, meaning even if the user goes to System Settings and toggles it on manually, the app's notification categories may not be registered.

## Implementation Plan

### Fix 1: Add presentation flags to `DarwinNotificationDetails`

**File**: `lib/services/notification_service.dart` — `_showNotification()` method (line 81)

Change:
```dart
macOS: DarwinNotificationDetails(),
```
To:
```dart
macOS: DarwinNotificationDetails(
  presentAlert: true,
  presentSound: true,
  presentBanner: true,
  presentList: true,
),
```

### Fix 2: Request permissions explicitly on macOS during initialization

**File**: `lib/services/notification_service.dart` — `initialize()` method (line 18)

After `_plugin.initialize(initSettings)`, add:

```dart
if (Platform.isMacOS) {
  await _plugin
      .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);
}
```

## Affected Files

- `lib/services/notification_service.dart`
