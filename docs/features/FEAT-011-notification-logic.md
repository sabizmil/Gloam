# FEAT-011: Notification Logic Overhaul

**Requested:** 2026-03-27
**Status:** Proposed
**Priority:** High
**Effort:** Medium (2-3 days)

---

## Current Behavior

The notification service (`lib/services/notification_service.dart`) fires on every sync when:
1. Room has `notificationCount > 0`
2. Room is NOT the `_activeRoomId` (the room the user clicked into)
3. Last event is < 10 seconds old

The room info panel (`lib/app/shell/room_info_panel.dart:131`) hardcodes "mentions only" — it doesn't read or set the actual push rule.

### Problems

| Problem | Impact |
|---------|--------|
| **No app focus detection** — Notifies even when Gloam is the frontmost app | Double-notifying (badge + system notification) |
| **Notifies for own messages** — Messages you sent from another device trigger notifications | Confusing |
| **No dedup tracking** — 10-second window heuristic causes duplicate notifications | Notification spam |
| **Ignores per-room push rules** — `room.pushRuleState` is never checked | Can't customize per room |
| **Room info panel is hardcoded** — Shows "mentions only" regardless of actual setting | Misleading, no way to change it |
| **No notification grouping** — Each message is a separate notification | 5 messages = 5 notifications |
| **Always sounds** — No distinction between regular messages and mentions | Too noisy for busy rooms |
| **Active room detection is fragile** — `setActiveRoom()` only called by timeline provider | Edge cases where suppression fails |

---

## Per-Room Notification Settings

### Matrix SDK Support

The SDK provides three push rule states per room:

| `PushRuleState` | Meaning | When to notify |
|-----------------|---------|----------------|
| `notify` | All messages | Every new message |
| `mentionsOnly` | Only @mentions and keywords | Only when `highlightCount > 0` |
| `dontNotify` | Muted | Never (except invites/calls) |

**Read:** `room.pushRuleState` — returns the current setting
**Write:** `room.setPushRuleState(PushRuleState.notify)` — changes the server-side push rule

These are stored in the user's `m.push_rules` account data on the server, so they sync across all clients.

### UX: Room Notification Selector

In the room info panel, replace the hardcoded "mentions only" with an interactive selector:

```
notifications
  ○ All messages          ← PushRuleState.notify
  ● Mentions only         ← PushRuleState.mentionsOnly (default)
  ○ Mute                  ← PushRuleState.dontNotify
```

Also accessible via right-click on a room in the room list → context menu → Notification settings.

### Visual Indicators

- **Muted rooms**: Show a muted bell icon (🔕) next to the room name in the room list. Unread badge should be dimmed or hidden for muted rooms.
- **All messages rooms**: Show unread badge normally.
- **Mentions only rooms**: Show unread badge only for mentions (highlight count), dim for regular unreads.

---

## Notification Decision Matrix

### Full Decision Tree

```
New sync arrives
  │
  For each room with notificationCount > 0:
  │
  ├─ Sender is me?  → SKIP (own messages from other devices)
  ├─ Already notified this event ID?  → SKIP (dedup)
  ├─ Room push rule == dontNotify?  → SKIP (muted)
  │
  ├─ App in FOREGROUND:
  │    ├─ This is the active room?  → SKIP (you're reading it)
  │    ├─ Room push rule == notify?
  │    │    ├─ DM?  → NOTIFY (DMs always break through in foreground)
  │    │    └─ Group room?  → SKIP (badge is visible, not urgent)
  │    ├─ Room push rule == mentionsOnly?
  │    │    ├─ highlightCount > 0?  → NOTIFY (you were mentioned)
  │    │    └─ No mention?  → SKIP
  │    └─ DM from someone not in any room with push rule?
  │         → NOTIFY (DMs default to notify)
  │
  └─ App in BACKGROUND:
       ├─ Room push rule == notify?  → NOTIFY
       ├─ Room push rule == mentionsOnly?
       │    ├─ highlightCount > 0?  → NOTIFY
       │    └─ No mention?  → SKIP
       └─ Default (no explicit rule)?  → NOTIFY (server default)

  For each room with membership == invite:
  └─ NOTIFY (always, regardless of focus)
```

### Simplified Summary Table

| Scenario | `notify` | `mentionsOnly` | `dontNotify` |
|----------|----------|----------------|--------------|
| Foreground, active room | No | No | No |
| Foreground, other DM | **Yes** | If mentioned | No |
| Foreground, other group room | No (badge visible) | If mentioned | No |
| Background, any room | **Yes** | If mentioned | No |
| Own message (any context) | No | No | No |
| Invite (any context) | **Yes** | **Yes** | **Yes** |

---

## Implementation Plan

### Task 1: App Focus Detection

**File:** `lib/services/notification_service.dart`

Use `WidgetsBindingObserver` to track foreground state:

```dart
class NotificationService with WidgetsBindingObserver {
  bool _appInForeground = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
  }

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _sub = client.onSync.stream.listen((_) => _checkForNotifications());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
  }
}
```

### Task 2: Core Notification Logic Rewrite

**File:** `lib/services/notification_service.dart`

Replace `_checkForNotifications()` with the full decision tree:

```dart
final _notifiedEventIds = <String>{};

void _checkForNotifications() {
  // Invites — always notify
  for (final room in client.rooms) {
    if (room.membership == Membership.invite) {
      _notifyInvite(room);
    }
  }

  // Messages
  for (final room in client.rooms) {
    if (room.membership != Membership.join) continue;
    if (room.notificationCount == 0 && room.highlightCount == 0) continue;

    final lastEvent = room.lastEvent;
    if (lastEvent == null) continue;

    // Own message — skip
    if (lastEvent.senderId == client.userID) continue;

    // Dedup
    if (_notifiedEventIds.contains(lastEvent.eventId)) continue;

    // Recency gate (only events from last 15 seconds)
    if (lastEvent.originServerTs
        .isBefore(DateTime.now().subtract(const Duration(seconds: 15)))) {
      continue;
    }

    // Per-room push rule
    final pushRule = room.pushRuleState;
    if (pushRule == PushRuleState.dontNotify) continue;

    // Determine if this message should notify
    bool shouldNotify = false;

    if (_appInForeground) {
      // Active room — never
      if (room.id == _activeRoomId) continue;

      if (pushRule == PushRuleState.notify) {
        // "All messages" mode: only DMs break through in foreground
        shouldNotify = room.isDirectChat;
      } else {
        // "Mentions only" mode: only if mentioned
        shouldNotify = room.highlightCount > 0;
      }
    } else {
      // Background
      if (pushRule == PushRuleState.notify) {
        shouldNotify = true;
      } else {
        shouldNotify = room.highlightCount > 0;
      }
    }

    if (shouldNotify) {
      _notifiedEventIds.add(lastEvent.eventId);
      _showNotification(
        room: room,
        sender: lastEvent.senderFromMemoryOrFallback.calcDisplayname(),
        body: lastEvent.body,
        isMention: room.highlightCount > 0,
      );

      // Cap dedup set
      if (_notifiedEventIds.length > 500) {
        final list = _notifiedEventIds.toList();
        _notifiedEventIds.clear();
        _notifiedEventIds.addAll(list.skip(list.length - 200));
      }
    }
  }
}
```

### Task 3: Notification Sound Differentiation

Mentions play the alert sound. Regular messages use a softer notification (or no sound on macOS):

```dart
Future<void> _showNotification({
  required Room room,
  required String sender,
  required String body,
  bool isMention = false,
}) async {
  final roomName = room.getLocalizedDisplayname();
  final title = room.isDirectChat ? sender : '$sender in $roomName';

  await _plugin.show(
    room.id.hashCode,
    title,
    body,
    NotificationDetails(
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: isMention, // Only sound for mentions
        presentBanner: true,
        presentList: true,
      ),
      linux: const LinuxNotificationDetails(),
    ),
  );
}
```

### Task 4: Room Info Panel — Live Push Rule Display

**File:** `lib/app/shell/room_info_panel.dart`

Replace the hardcoded "mentions only" with a live reader:

```dart
// Read the actual push rule state
final pushRule = room.pushRuleState;
final pushLabel = switch (pushRule) {
  PushRuleState.notify => 'all messages',
  PushRuleState.mentionsOnly => 'mentions only',
  PushRuleState.dontNotify => 'muted',
};

_DetailRow(
  label: 'notifications',
  value: pushLabel,
),
```

### Task 5: Room Notification Selector (Interactive)

**File:** `lib/app/shell/room_info_panel.dart`

Make the notification row tappable, opening an inline selector or bottom sheet:

```dart
GestureDetector(
  onTap: () => _showNotificationPicker(context, room),
  child: _DetailRow(
    label: 'notifications',
    value: pushLabel,
    trailing: Icon(Icons.chevron_right, size: 14, color: GloamColors.textTertiary),
  ),
)
```

The picker:

```dart
void _showNotificationPicker(BuildContext context, Room room) {
  showModalBottomSheet(
    context: context,
    backgroundColor: GloamColors.bgSurface,
    builder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PushRuleOption(
          label: 'All messages',
          subtitle: 'Notify for every new message',
          icon: Icons.notifications_active_outlined,
          isSelected: room.pushRuleState == PushRuleState.notify,
          onTap: () {
            room.setPushRuleState(PushRuleState.notify);
            Navigator.pop(context);
          },
        ),
        _PushRuleOption(
          label: 'Mentions only',
          subtitle: 'Only notify when you\'re @mentioned',
          icon: Icons.alternate_email,
          isSelected: room.pushRuleState == PushRuleState.mentionsOnly,
          onTap: () {
            room.setPushRuleState(PushRuleState.mentionsOnly);
            Navigator.pop(context);
          },
        ),
        _PushRuleOption(
          label: 'Mute',
          subtitle: 'No notifications from this room',
          icon: Icons.notifications_off_outlined,
          isSelected: room.pushRuleState == PushRuleState.dontNotify,
          onTap: () {
            room.setPushRuleState(PushRuleState.dontNotify);
            Navigator.pop(context);
          },
        ),
      ],
    ),
  );
}
```

### Task 6: Room List Visual Indicators

**File:** `lib/features/rooms/presentation/widgets/room_list_tile.dart`

Add muted indicator and adjust badge visibility:

```dart
// In RoomListItem, add:
final PushRuleState pushRuleState;

// In room_list_provider.dart, populate:
pushRuleState: room.pushRuleState,

// In room_list_tile.dart:
// Muted rooms: show 🔕 icon, dim the unread badge
if (room.pushRuleState == PushRuleState.dontNotify)
  Icon(Icons.notifications_off, size: 12, color: GloamColors.textTertiary),

// Mentions only: only show badge when highlightCount > 0
// Notify: show badge for any unreadCount > 0
```

### Task 7: Room List Context Menu

**File:** `lib/app/shell/room_list_panel.dart`

Add right-click / long-press context menu on room tiles:

```dart
GestureDetector(
  onSecondaryTapDown: (details) => _showRoomContextMenu(
    context, room, details.globalPosition,
  ),
  child: RoomListTile(room: room, ...),
)
```

Context menu options:
- Mark as read
- Notification settings → submenu (All / Mentions / Mute)
- Leave room

---

## Files Summary

| File | Change |
|------|--------|
| `lib/services/notification_service.dart` | Focus detection, dedup, own-message filter, push rule integration, sound differentiation |
| `lib/app/shell/room_info_panel.dart` | Live push rule display + interactive selector |
| `lib/features/rooms/presentation/providers/room_list_provider.dart` | Add `pushRuleState` to `RoomListItem` |
| `lib/features/rooms/presentation/widgets/room_list_tile.dart` | Muted indicator, conditional badge visibility |
| `lib/app/shell/room_list_panel.dart` | Room context menu with notification settings |

## Success Criteria

- [ ] No notification when actively reading the room (foreground + active)
- [ ] No notification for own messages from other devices
- [ ] No duplicate notifications for the same event
- [ ] Foreground, other room: DMs notify, group rooms don't (unless mention)
- [ ] Background: all non-muted rooms with unreads notify
- [ ] Muted rooms (`dontNotify`): never notify, badge dimmed
- [ ] Mentions-only rooms: only notify on highlight
- [ ] All-messages rooms: always notify in background, DMs notify in foreground
- [ ] Room info panel shows actual push rule, tappable to change
- [ ] Push rule changes sync to server (visible in other clients)
- [ ] Room list shows muted indicator (🔕) for muted rooms
- [ ] Invites always notify regardless of settings
- [ ] Mentions play alert sound, regular messages don't

---

## Change History

- 2026-03-27: Initial plan with core notification logic
- 2026-03-27: Added per-room notification settings (push rules), room info panel selector, room list visual indicators, context menu
