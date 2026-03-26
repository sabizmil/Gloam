# BUG-012: DM sender avatar shows wrong profile photo until scroll triggers re-render

- **Reported**: 2026-03-26
- **Status**: Open
- **Priority**: P2 (visual / polish)
- **Related**: BUG-008 (archived — partial fix)

## Description

Follow-up to BUG-008. In DM conversations, the current user's messages initially display the DM partner's (Phoenix's) avatar instead of the correct sender avatar. The issue self-corrects after scrolling up and back down, which forces a timeline rebuild. The BUG-008 fix addressed the avatar contamination from `senderFromMemoryOrFallback` but left a race condition on initial render.

## Steps to Reproduce

1. Launch Gloam and log in
2. Open a DM conversation with another user (e.g., Phoenix)
3. Observe: your own messages display Phoenix's avatar
4. Scroll up past the viewport, then scroll back down
5. Observe: avatars now display correctly (initials or your own avatar)

## Expected Behavior

Messages should display the correct sender avatar immediately on initial load, without requiring a scroll round-trip.

## Actual Behavior

On initial render, the current user's messages show the DM partner's avatar. Scrolling triggers a re-render that corrects the display.

## Root Cause Analysis

Two distinct issues combine to cause this bug:

### Issue 1: BUG-008 equality check fails on initial load (race condition)

**File**: `lib/features/chat/presentation/providers/timeline_provider.dart` (line 194-198, prior to this fix)

The BUG-008 fix compares `senderAvatarUrl == _room!.avatar` to detect when the fallback User has inherited the room's DM avatar. However, `Room.avatar` for a DM calls `unsafeGetUserFromMemoryOrFallback(directChatMatrixID)` (Matrix SDK `room.dart` line 320), which may not be resolved yet on initial load if the DM partner's member event hasn't been loaded into the room state cache. When `_room!.avatar` returns `null` but `senderAvatarUrl` is non-null (Phoenix's avatar from a partially-loaded state), the equality check fails and the contaminated avatar leaks through.

### Issue 2: Timeline not rebuilt when member state arrives asynchronously

**File**: `lib/features/chat/presentation/providers/timeline_provider.dart` (lines 88-93)

`TimelineNotifier._init()` sets up Timeline callbacks for `onChange`, `onInsert`, and `onRemove`. These fire for timeline events (messages) but **not** for room state changes (member events). When `unsafeGetUserFromMemoryOrFallback` doesn't find a member in cache, it fires `requestUser()` asynchronously (Matrix SDK `room.dart` line 1743), which fetches the member event via a direct API call and stores it in room state. However, nothing triggers `_rebuild()` when that request completes — the `TimelineMessage` objects mapped during the initial `_rebuild()` persist with stale avatar data until a timeline event (e.g. scrolling to load history) causes a re-map.

The Timeline class (`matrix-0.40.2/lib/src/timeline.dart` lines 329-345) subscribes only to:
- `onTimelineEvent` — new messages
- `onHistoryEvent` — history pagination
- `onSync` limited timeline — full timeline resets
- `onSessionKeyReceived` — decryption key arrival

Room state changes (member events) are not covered by any of these.

### Why scrolling fixes it

Scrolling up past `maxScrollExtent - 200` triggers `loadMore()` (chat_screen.dart line 58-62) which calls `requestHistory()`, fetching historical events and triggering `onInsert`/`onChange` callbacks, which call `_rebuild()`. By this time, `requestUser()` has resolved and the member state is correctly populated, so the re-mapped `TimelineMessage` objects get the correct avatar.

## Implementation Plan

### Fix 1: Broaden the avatar contamination guard

Replace the fragile `senderAvatarUrl == _room!.avatar` equality check with a direct comparison against the DM partner's avatar. This catches contamination even when `_room!.avatar` hasn't resolved yet, because it compares directly against `unsafeGetUserFromMemoryOrFallback(directChatMatrixID).avatarUrl`.

```dart
if (event.senderId == _room!.client.userID &&
    _room!.isDirectChat &&
    senderAvatarUrl != null) {
  final dmPartnerId = _room!.directChatMatrixID;
  if (dmPartnerId != null) {
    final dmPartner =
        _room!.unsafeGetUserFromMemoryOrFallback(dmPartnerId);
    if (senderAvatarUrl == dmPartner.avatarUrl ||
        senderAvatarUrl == _room!.avatar) {
      senderAvatarUrl = null;
    }
  }
}
```

### Fix 2: Subscribe to sync for member state changes

Add an `onSync` stream listener in `_init()` that detects when member state events arrive for this room (either in `state` or `timeline.events`) and triggers `_rebuild()`.

### Fix 3: Deferred rebuild for requestUser() resolution

`requestUser()` resolves via direct API calls (not sync), so the sync listener won't catch those. Schedule a deferred `_rebuild()` 500ms after initial load to pick up member data that resolves shortly after the initial render.

### Effort Estimate

30 minutes, already implemented alongside this bug report.

## Affected Files

- `lib/features/chat/presentation/providers/timeline_provider.dart` — avatar guard broadened, sync listener added, deferred rebuild added
