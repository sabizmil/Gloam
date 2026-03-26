# BUG-013: Unread badge does not clear when opening a room

- **Reported**: 2026-03-26
- **Status**: Open
- **Priority**: P1 (broken feature)
- **Effort**: M

## Description

When the user receives new messages, the sidebar correctly shows an unread badge with the message count. However, opening the chat and viewing the new messages does not clear the badge. The user expects that having messages visible in the viewport satisfies the read condition and should dismiss the unread indicator.

## Steps to Reproduce

1. Have another user send one or more messages to a room
2. Observe the unread badge appears on that room in the sidebar
3. Click the room to open it
4. Observe: the unread badge remains visible even though the messages are in view

## Expected Behavior

Opening a room and having the new messages visible in the viewport should send a read receipt for the latest event, causing the server to reset `notificationCount` to 0, which clears the badge in the sidebar.

## Actual Behavior

The badge persists after opening the room. It may eventually clear on a subsequent sync cycle or not at all, depending on the timing of the `markAsRead` call relative to timeline initialization.

## Root Cause Analysis

There are three compounding issues:

### 1. Race condition: `markAsRead` fires before the timeline has loaded

**File**: `lib/features/chat/presentation/screens/chat_screen.dart`, lines 39-41

```dart
Future.microtask(() {
  ref.read(timelineProvider(widget.roomId).notifier).markAsRead();
});
```

This runs in `initState` via `Future.microtask`, which executes before the next frame. However, `TimelineNotifier._init()` is async — it awaits `room.getTimeline()` before populating `_timeline`. By the time `markAsRead` runs, `_timeline` is almost certainly still `null`, causing the method to bail out at the guard clause:

**File**: `lib/features/chat/presentation/providers/timeline_provider.dart`, lines 420-428

```dart
Future<void> markAsRead() async {
  final room = _room;
  if (room == null || _timeline == null) return;  // <-- exits here
  if (_timeline!.events.isEmpty) return;
  await room.setReadMarker(
    _timeline!.events.first.eventId,
    mRead: _timeline!.events.first.eventId,
  );
}
```

The `_timeline == null` guard causes `markAsRead` to silently no-op. No read receipt is ever sent.

### 2. No `markAsRead` call when new messages arrive

Even if the initial `markAsRead` succeeded, there is no mechanism to call it again when new messages are inserted into the timeline while the chat screen is already open. The `TimelineNotifier` has `onChange`/`onInsert` callbacks (line 90-91) that only trigger `_rebuild()` — they never send a read receipt. So messages arriving while the room is in view still accumulate an unread count.

### 3. Room list relies on server-side `notificationCount`

**File**: `lib/features/rooms/presentation/providers/room_list_provider.dart`, line 82

```dart
unreadCount: room.notificationCount,
```

This value is controlled by the homeserver. The server only resets it when it receives an `m.read` receipt (or `m.fully_read` marker) for the latest event. Since the read receipt is never sent (issue 1) or not sent for new messages (issue 2), `notificationCount` stays elevated.

## Implementation Plan

### Fix 1: Defer `markAsRead` until the timeline is actually loaded

Instead of calling `markAsRead` in `initState` (where the timeline hasn't loaded yet), listen for the first non-empty state emission from the timeline provider and call `markAsRead` then.

**File**: `lib/features/chat/presentation/screens/chat_screen.dart`

- Remove the `Future.microtask` call in `initState`
- Add a `ref.listen` on the timeline provider that calls `markAsRead` when messages first appear and whenever new messages are inserted (i.e., the list length increases)

```dart
@override
void initState() {
  super.initState();
  _scrollController.addListener(_onScroll);
}

// In build() or didChangeDependencies():
ref.listen<List<TimelineMessage>>(
  timelineProvider(widget.roomId),
  (previous, next) {
    if (next.isNotEmpty) {
      ref.read(timelineProvider(widget.roomId).notifier).markAsRead();
    }
  },
);
```

### Fix 2: Ensure `markAsRead` is called when new messages arrive while the chat is open

The `ref.listen` approach above handles this automatically — any time the timeline state changes and has messages, a read receipt is sent for the latest event. To avoid excessive network calls, add a debounce or check that the latest event ID has actually changed since the last receipt.

**File**: `lib/features/chat/presentation/providers/timeline_provider.dart`

- Track the last event ID that was marked as read to avoid redundant receipt calls:

```dart
String? _lastReadEventId;

Future<void> markAsRead() async {
  final room = _room;
  if (room == null || _timeline == null) return;
  if (_timeline!.events.isEmpty) return;
  final latestEventId = _timeline!.events.first.eventId;
  if (latestEventId == _lastReadEventId) return;  // already sent
  _lastReadEventId = latestEventId;
  await room.setReadMarker(latestEventId, mRead: latestEventId);
}
```

### Fix 3 (optional): Optimistic local badge clear

For immediate visual feedback, the room list provider could optimistically set the unread count to 0 for the currently selected room, rather than waiting for the server sync round-trip.

**File**: `lib/features/rooms/presentation/providers/room_list_provider.dart`

- Check the `selectedRoomProvider` and force `unreadCount: 0` for the active room in `_buildRoomList`.

## Affected Files

- `lib/features/chat/presentation/screens/chat_screen.dart` — move `markAsRead` from `initState` to a `ref.listen` callback
- `lib/features/chat/presentation/providers/timeline_provider.dart` — add dedup guard (`_lastReadEventId`), ensure `markAsRead` is robust
- `lib/features/rooms/presentation/providers/room_list_provider.dart` — (optional) optimistic badge clear for active room
