# BUG-008: Wrong avatar shown for own messages and self-DM room

- **Reported**: 2026-03-26
- **Updated**: 2026-03-26
- **Status**: Open
- **Priority**: P1 (broken feature)

## Description

Avatar resolution is broken in two places:

1. **Self-DM room list**: When the user creates a DM with themselves, the room list sidebar shows another user's avatar ("Phoenix") and no room title.
2. **Chat timeline**: In a normal DM with Phoenix, the user's own messages ("sabizmil") display Phoenix's avatar instead of the user's own "S" initial avatar. This happens because `senderFromMemoryOrFallback` returns a fallback User whose avatar inherits from the room's DM avatar (which is Phoenix's).

## Steps to Reproduce

### Self-DM (room list)
1. Start Gloam and log in
2. Create a new direct message with yourself (your own Matrix ID)
3. Look at the room list sidebar under "Direct Messages"
4. Observe: the self-DM shows another user's profile picture (Phoenix) and has no display name

### Chat timeline (normal DM)
1. Open a DM with another user (e.g., Phoenix)
2. Send a message
3. Observe: your own messages display Phoenix's avatar instead of your own

## Expected Behavior

- The self-DM should display the current user's own display name and avatar
- In the chat timeline, each message should display the actual sender's avatar, not the room/DM target avatar
- Normal DMs with other people should continue showing the other person's name and avatar in the room list

## Actual Behavior

- The self-DM shows no title (empty string) and "Phoenix"'s avatar
- In the chat timeline, the user's own messages show Phoenix's fire-bird avatar instead of the "S" initial

## Root Cause Analysis

The issue originates in the Matrix SDK's `Room` class and how Gloam consumes its output without handling the self-DM edge case.

### Display Name (empty title)

**File**: Matrix SDK `room.dart` (line 246-297 in `matrix-0.40.2`)

`Room.getLocalizedDisplayname()` builds the display name from "heroes" (other room members). At line 262-265, it filters out the current user:

```dart
final result = heroes
    .where((hero) => hero.isNotEmpty && hero != client.userID)
    .map(...)
    .join(', ');
```

In a self-DM, `directChatMatrixID == client.userID`, so the only hero is the current user. After filtering, `result` is an empty string — hence no title.

**File**: `/Users/sabizmil/Developer/matrix-chat/lib/features/rooms/presentation/providers/room_list_provider.dart` (line 62)

```dart
displayName: room.getLocalizedDisplayname(),
```

This passes the empty string straight through to the UI with no self-DM handling.

### Avatar (wrong user)

**File**: Matrix SDK `room.dart` (line 309-324)

`Room.avatar` for direct chats falls back to `unsafeGetUserFromMemoryOrFallback(directChatMatrixID).avatarUrl`. For a self-DM, `directChatMatrixID == client.userID`, so this should return the user's own avatar. However, `unsafeGetUserFromMemoryOrFallback` may return stale or incorrect member data if the user's own membership event hasn't been fully loaded. The "Phoenix" avatar appearing suggests the SDK returned cached member data from a different context, or `directChatMatrixID` resolved unexpectedly.

Regardless of the SDK-level cause, Gloam's room list provider at line 63 (`avatarUrl: room.avatar`) does not handle self-DMs explicitly, so any SDK quirk propagates directly to the UI.

**File**: `/Users/sabizmil/Developer/matrix-chat/lib/features/rooms/presentation/providers/room_list_provider.dart` (line 63)

```dart
avatarUrl: room.avatar,
```

### Timeline avatar (wrong sender avatar)

**File**: `/Users/sabizmil/Developer/matrix-chat/lib/features/chat/presentation/providers/timeline_provider.dart` (line 191)

```dart
senderAvatarUrl: event.senderFromMemoryOrFallback.avatarUrl,
```

`event.senderFromMemoryOrFallback` returns a `User` from the room's member cache. When the user's own membership event hasn't been fully loaded into the room cache, it creates a fallback `User` object. In a DM room, this fallback can inherit the room's avatar (which is Phoenix's avatar for a DM with Phoenix). The result: sabizmil's messages display Phoenix's avatar.

### Summary

Two separate code paths are affected:
1. `room_list_provider.dart` `_buildRoomList()` — no self-DM handling for room display name/avatar
2. `timeline_provider.dart` `_mapEvent()` — `senderFromMemoryOrFallback` returns unreliable avatar for the current user in DMs

## Implementation Plan

### Fix 1: Self-DM room list (room_list_provider.dart)

Detect self-DMs in `_buildRoomList()` where `room.directChatMatrixID == client.userID` and override both the display name and avatar URL to use the current user's profile.

In the `_buildRoomList` function (around lines 60-63):

```dart
final isSelfDM = room.isDirectChat &&
    room.directChatMatrixID == client.userID;

String displayName;
Uri? avatarUrl;

if (isSelfDM) {
  final ownProfile = client.ownProfile;
  displayName = ownProfile.displayName ?? client.userID?.localpart ?? 'Me';
  avatarUrl = ownProfile.avatarUrl ?? room.avatar;
} else {
  displayName = room.getLocalizedDisplayname();
  avatarUrl = room.avatar;
}
```

### Fix 2: Timeline sender avatar (timeline_provider.dart)

In `_mapEvent()` at line 191, use `room.unsafeGetUserFromMemoryOrFallback(event.senderId)` but cross-check: if the sender is the current user and the returned avatarUrl matches the room's DM avatar, discard it and use the client's own profile avatar instead:

```dart
final sender = event.senderFromMemoryOrFallback;
Uri? senderAvatarUrl = sender.avatarUrl;

// Guard against DM rooms where the fallback user inherits the room avatar
if (event.senderId == _room.client.userID &&
    _room.isDirectChat &&
    senderAvatarUrl == _room.avatar) {
  senderAvatarUrl = _room.client.ownProfile.avatarUrl;
}
```

This preserves the existing fast path for all other messages while fixing the current-user-in-DM edge case.

### Effort Estimate

30 minutes, including testing both fixes.

## Affected Files

- `lib/features/rooms/presentation/providers/room_list_provider.dart` — self-DM detection in `_buildRoomList()`
- `lib/features/chat/presentation/providers/timeline_provider.dart` — sender avatar guard in `_mapEvent()`
