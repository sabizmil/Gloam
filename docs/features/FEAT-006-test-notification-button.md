# FEAT-006: Test Notification Button in Settings

- **Requested**: 2026-03-26
- **Status**: Proposed
- **Priority**: P2

## Description

The Notifications section in the Settings panel is currently an empty placeholder (`_PlaceholderSection('notifications')`) that displays "// notifications -- coming soon". The user wants a "Test notification" button added so they can verify notifications are working correctly on their system. This is especially useful since [BUG-006](../bugs/archive/BUG-006-macos-notifications-not-showing.md) (macOS notifications not showing) was recently fixed -- users need a way to confirm the fix is working without waiting for a real incoming message.

## User Story

As a Gloam user, I want to send myself a test notification from Settings so that I can verify my system is correctly configured to receive notifications without needing someone else to message me.

---

## Implementation Approaches

### Approach 1: Standalone Test via FlutterLocalNotificationsPlugin Directly

**Summary:** Create a new `NotificationSection` widget that instantiates its own `FlutterLocalNotificationsPlugin` and fires a test notification directly, bypassing `NotificationService` entirely.

**Technical approach:** The section widget creates a local `FlutterLocalNotificationsPlugin` instance, calls `show()` with hardcoded test content. No changes to `NotificationService`.

**Pros:**
- Zero coupling to existing notification infrastructure
- Simplest possible implementation -- one new file, one line change in `settings_modal.dart`
- Cannot break existing notification flow

**Cons:**
- Duplicates plugin initialization logic (DarwinNotificationDetails flags, etc.)
- Does not actually validate that the *real* `NotificationService` pipeline works
- If `NotificationService` configuration diverges from the test, the test becomes misleading

**Effort:** Small (1-2 hours)

**Dependencies:** None -- `flutter_local_notifications` is already in pubspec.

---

### Approach 2: Add a Public `sendTestNotification()` Method to NotificationService

**Summary:** Expose a `sendTestNotification()` method on the existing `NotificationService` class, then make the service accessible from Settings via a Riverpod provider.

**Technical approach:** Add a public method to `NotificationService` that calls the existing private `_showNotification()` pipeline (or directly calls `_plugin.show()`) with test content. Promote `NotificationService` to a Riverpod provider so the settings section can access it. The new `NotificationSection` widget reads the provider and wires the button.

**Pros:**
- Tests the *actual* notification path (same plugin instance, same config, same permission state)
- Validates the real pipeline end-to-end
- Sets up provider infrastructure needed for future notification settings (per-room controls, DND, etc.)

**Cons:**
- Requires refactoring `NotificationService` lifecycle from local state in `_AuthenticatedHomeState` to a Riverpod provider
- More moving parts for a single button
- Provider lifecycle management needs care (service must be initialized before test fires)

**Effort:** Medium (3-4 hours)

**Dependencies:** Refactor of `NotificationService` instantiation in `home_screen.dart`.

---

### Approach 3: Static Helper Method on NotificationService

**Summary:** Add a static `sendTestNotification()` method to `NotificationService` that creates a temporary plugin instance, fires one notification, and disposes.

**Technical approach:** The static method encapsulates all the setup: create plugin, initialize with correct platform settings, request permissions if needed, fire notification, return success/failure. The settings section calls it directly -- no provider needed.

**Pros:**
- No refactoring of existing service lifecycle
- Self-contained -- settings section just calls `NotificationService.sendTestNotification()`
- Returns a result that can drive UI feedback (success/failure)
- Reuses the same notification detail configuration as the real service

**Cons:**
- Uses a separate plugin instance, so it's not a perfect end-to-end test of the running service
- Static methods are harder to mock in tests
- Still some duplication of initialization logic (though contained in one class)

**Effort:** Small-Medium (2-3 hours)

**Dependencies:** None.

---

### Approach 4: Event-Based Test via Matrix Client Loopback

**Summary:** Send a real Matrix message to yourself (a notice or a special event type) that triggers the actual notification pipeline.

**Technical approach:** Create a "test" room or use a self-DM, send a message event, let the existing `NotificationService._checkForNotifications()` pick it up and display it. The settings button triggers the send.

**Pros:**
- True end-to-end test: Matrix sync -> notification service -> OS notification
- Validates the entire pipeline including sync, event filtering, and display

**Cons:**
- Requires network connectivity
- Creates real events in the user's account (noise)
- Complex failure modes (sync delay, room creation, event filtering)
- The notification service suppresses notifications for the active room, so the UX would be confusing
- Way over-engineered for a test button

**Effort:** Large (6-8 hours)

**Dependencies:** Network connectivity, Matrix homeserver availability.

---

### Approach 5: Notification Section with Test Button + Permission Status Display

**Summary:** Build a full notification section that shows the current permission status, a test button, and placeholder rows for future settings (DND, per-room controls). The test button uses the static helper approach internally.

**Technical approach:** Combine Approach 3 (static test method) with a richer UI that also checks and displays the current notification permission state. Shows "Notifications: Allowed" / "Notifications: Denied" with a link to system settings. The test button is contextually disabled if permissions are denied.

**Pros:**
- Most useful to the user -- answers "are notifications working?" *and* "are they even allowed?"
- Sets up the section structure for future notification settings
- Permission check on macOS via `FlutterLocalNotificationsPlugin` is straightforward
- Feels like a real settings section, not just a single button

**Cons:**
- More UI work than a simple button
- Permission checking APIs differ across platforms (may need platform-specific code)
- Risk of scope creep into building notification preferences prematurely

**Effort:** Medium (4-5 hours)

**Dependencies:** Platform-specific permission checking (partially available via `flutter_local_notifications`).

---

## Recommendation

**Approach 3: Static Helper Method on NotificationService** is the best fit.

**Rationale:**
- The user explicitly asked for a test button, not a full notification settings panel. Approach 3 delivers exactly that with minimal surface area.
- It avoids the premature refactoring of Approach 2 (promoting `NotificationService` to a provider). That refactor *should* happen eventually when per-room notification controls are built, but forcing it now for a single button adds unnecessary risk.
- Unlike Approach 1, it keeps notification configuration centralized in `NotificationService`, so the test uses the same `DarwinNotificationDetails` flags and platform logic as real notifications. If the config changes, the test stays in sync.
- Approach 4 is over-engineered. Approach 5 is nice but risks scope creep -- it can be evolved into that later when the full notification settings are built.
- The static method can return a bool/error to drive simple UI feedback (a brief "Sent!" confirmation or error state on the button).
- Cross-platform: the static method inherits the same platform guards (`Platform.isMacOS`, `Platform.isLinux`, `Platform.isWindows`) as the real service.

---

## Implementation Plan

### Step 1: Add static test method to NotificationService

**File:** `lib/services/notification_service.dart`

Add a public static method:

```dart
/// Fire a single test notification to verify system configuration.
/// Returns true if the notification was sent without error.
static Future<bool> sendTestNotification() async {
  if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) {
    return false;
  }

  try {
    final plugin = FlutterLocalNotificationsPlugin();
    const initMacOS = DarwinInitializationSettings();
    const initLinux = LinuxInitializationSettings(defaultActionName: 'Open');
    const initSettings = InitializationSettings(
      macOS: initMacOS,
      linux: initLinux,
    );
    await plugin.initialize(initSettings);

    await plugin.show(
      0, // fixed ID for test notifications
      'Gloam',
      'Notifications are working.',
      const NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
        linux: LinuxNotificationDetails(),
      ),
    );
    return true;
  } catch (_) {
    return false;
  }
}
```

### Step 2: Create NotificationSection widget

**File (new):** `lib/features/settings/presentation/sections/notification_section.dart`

A `StatefulWidget` with:
- Section header "// test" using `SettingsSectionHeader`
- A `SettingsTile` with icon `Icons.notifications_active_outlined`, label "send test notification", and an `onTap` that calls `NotificationService.sendTestNotification()`
- Brief visual feedback after tapping: swap the trailing widget to a checkmark icon for ~2 seconds on success, or show a red X on failure
- A descriptive subtitle row explaining what this does ("Fires a local notification to verify your system is configured correctly")
- Platform guard: on mobile (iOS/Android), show a note that desktop notifications only -- or hide the button entirely

**Design system alignment:**
- Uses `SettingsTile` and `SettingsSectionHeader` (existing widgets)
- Monospace `// test` section header pattern
- Button feedback uses `accent` for success, `danger` for failure
- Follows the `ListView` + padding pattern from other sections (e.g., `AccountSection`)
- Typography: Inter for labels, JetBrains Mono for section headers and status values

### Step 3: Wire into settings_modal.dart

**File:** `lib/features/settings/presentation/settings_modal.dart`

- Import the new `NotificationSection`
- Replace the `_PlaceholderSection('notifications')` case with `const NotificationSection()`

### Step 4: Verify and test

- pkill the running app, rebuild via `build_macos.sh`, relaunch
- Navigate to Settings > Notifications
- Tap "send test notification"
- Confirm macOS notification appears with title "Gloam" and body "Notifications are working."

### Files to Modify

| File | Change |
|------|--------|
| `lib/services/notification_service.dart` | Add `static sendTestNotification()` method |
| `lib/features/settings/presentation/sections/notification_section.dart` | **New file** -- `NotificationSection` widget |
| `lib/features/settings/presentation/settings_modal.dart` | Replace placeholder with `NotificationSection` |

### New Dependencies

None.

### State Management

Minimal local state only (`StatefulWidget`):
- `_isSending` bool to disable the button while the notification is in flight
- `_lastResult` enum (`none`, `success`, `failure`) to drive the trailing icon feedback
- `Timer` to reset the result state after 2 seconds

No Riverpod state needed for this feature.

### Edge Cases

- **Permissions denied:** `sendTestNotification()` will succeed at the plugin level but the OS may suppress the banner. The method returns `true` (no error thrown), but the user sees nothing. A future iteration (Approach 5) can add permission status checking.
- **Mobile platforms:** The method returns `false` on iOS/Android since local desktop notifications are not supported there. The section should handle this gracefully (either hide the button or show a disabled state with explanation).
- **Rapid tapping:** The `_isSending` guard prevents multiple simultaneous test notifications.
- **App not focused:** Test notification should appear regardless of app focus state (it bypasses the active-room suppression in the real service).

---

## Acceptance Criteria

- [ ] Notifications section in Settings shows a "send test notification" tile instead of the placeholder
- [ ] Tapping the tile fires a local OS notification with title "Gloam" and body "Notifications are working."
- [ ] The tile shows brief visual feedback (checkmark) after successful send
- [ ] The tile is disabled while a notification send is in flight (prevents double-tap)
- [ ] The notification appears on macOS with banner, alert, and sound
- [ ] The notification appears on Linux
- [ ] On unsupported platforms (iOS/Android), the button is gracefully hidden or shows an explanation
- [ ] No new dependencies added
- [ ] Follows Gloam design system (SettingsTile, section headers, correct typography and colors)

---

## Related

- [BUG-006: macOS notifications not showing](../bugs/archive/BUG-006-macos-notifications-not-showing.md) -- the fix that motivates this feature; users need a way to verify it works
- [COMPETITIVE_ANALYSIS.md](../../COMPETITIVE_ANALYSIS.md) -- notification reliability listed as gap #8 in the UX gaps ranking
- [09-design-system.md](../plan/09-design-system.md) -- settings panel layout spec, button variants, section header pattern
- `lib/services/notification_service.dart` -- existing notification infrastructure
- `lib/features/settings/presentation/settings_modal.dart` -- settings panel routing
