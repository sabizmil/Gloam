# FEAT-009: Room Invite Flow

**Requested:** 2026-03-26
**Status:** Proposed
**Priority:** High
**Effort:** Small-Medium (2-3 days)

---

## Problem

Gloam currently filters the room list to `Membership.join` only (`room_list_provider.dart:35`). Rooms with `Membership.invite` are completely invisible. When another user or a bot invites you to a room, nothing happens in Gloam — no notification, no badge, no UI. You'd only see the invite if you opened another client like Cinny or Element.

This is a critical gap. Invites are how people get added to private rooms, how bridges send you status rooms (like the Libera.Chat IRC bridge), and how bots onboard users.

## User Story

As a Gloam user, when someone invites me to a room, I want to see the invite in my room list with the ability to accept or decline, so I don't miss invitations and can choose whether to join.

---

## UX Design

### Invite Banner in Room List

Invites appear at the **top** of the room list, above "direct messages", in a visually distinct section:

```
┌─────────────────────────────────────┐
│ // invites (2)                      │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ 📩 Libera.Chat IRC Bridge      │ │
│ │    @bridge:mailstation.de       │ │
│ │    [Accept]  [Decline]          │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ 📩 Project Planning             │ │
│ │    @alice:matrix.org invited you│ │
│ │    [Accept]  [Decline]          │ │
│ └─────────────────────────────────┘ │
│                                     │
│ // direct messages                  │
│ ...                                 │
```

### Invite Card

Each invite shows:
- Room name (or inviter's name for DM invites)
- Room avatar (or inviter's avatar)
- Who invited you: "@user:server invited you"
- Room topic (if available, truncated to 2 lines)
- Member count (if available from the invite state)
- **Accept** button (accent color) — joins the room
- **Decline** button (subtle/danger) — rejects the invite
- Accept shows a spinner while joining, then the room transitions to the regular room list
- Decline removes the card with a brief animation

### Invite Notification Badge

The space rail's DM icon (or a new dedicated badge) shows a count of pending invites so you notice them even when scrolled down in the room list.

### DM Invite vs Room Invite

- **DM invite** (room `isDirect`): Show the inviter's avatar and name prominently, like a friend request
- **Room invite**: Show the room name/avatar, with "invited by @user" as subtitle

---

## Implementation Plan

### Task 1: Extend RoomListItem to Support Invites

**File:** `lib/features/rooms/presentation/providers/room_list_provider.dart`

Add invites to the room list provider:

```dart
List<RoomListItem> _buildRoomList(Client client) {
  // Include both joined AND invited rooms
  final rooms = client.rooms
      .where((r) => r.membership == Membership.join || r.membership == Membership.invite)
      .toList();
  // ... existing sort and map logic
}
```

Add invite-related fields to `RoomListItem`:

```dart
class RoomListItem {
  // ... existing fields ...
  final bool isInvite;
  final String? inviterId;       // who sent the invite
  final String? inviterName;     // display name of inviter
}
```

Populate from the room's invite state:
```dart
// For invited rooms, the membership event content has the inviter
final isInvite = room.membership == Membership.invite;
String? inviterId;
String? inviterName;
if (isInvite) {
  // The invite event sender is the person who invited us
  final inviteEvent = room.getState(EventTypes.RoomMember, client.userID!);
  inviterId = inviteEvent?.senderId;
  if (inviterId != null) {
    final inviter = room.unsafeGetUserFromMemoryOrFallback(inviterId);
    inviterName = inviter.calcDisplayname();
  }
}
```

### Task 2: Invite Tile Widget

**New file:** `lib/features/rooms/presentation/widgets/invite_tile.dart`

A distinct card-style tile for invites with:
- Room avatar + name
- "invited by @user" subtitle
- Accept / Decline buttons
- Loading state on Accept (spinner)

```dart
class InviteTile extends ConsumerWidget {
  final RoomListItem invite;

  void _accept(WidgetRef ref) async {
    final client = ref.read(matrixServiceProvider).client;
    final room = client?.getRoomById(invite.roomId);
    await room?.join();
    // Room transitions from invite to join on next sync
  }

  void _decline(WidgetRef ref) async {
    final client = ref.read(matrixServiceProvider).client;
    final room = client?.getRoomById(invite.roomId);
    await room?.leave();
    // Room disappears on next sync
  }
}
```

### Task 3: Integrate Into Room List Panel

**File:** `lib/app/shell/room_list_panel.dart`

In the ListView builder, add an invites section at the top:

```dart
final invites = filtered.where((r) => r.isInvite).toList();
final dms = filtered.where((r) => r.isDirect && !r.isInvite).toList();
final channels = filtered.where((r) => !r.isDirect && !r.isInvite && !isVoiceChannel(r)).toList();

return ListView(
  children: [
    if (invites.isNotEmpty) ...[
      const SectionHeader('invites'),
      ...invites.map((r) => InviteTile(invite: r)),
    ],
    if (dms.isNotEmpty) ...[
      const SectionHeader('direct messages'),
      ...
    ],
    // ... rest unchanged
  ],
);
```

### Task 4: Invite Count Badge

**File:** `lib/app/shell/space_rail.dart`

Show an invite count badge on the DM icon in the space rail:

```dart
// In the DM icon widget
Stack(
  children: [
    _SpaceIcon(child: Icon(Icons.chat_bubble), ...),
    if (inviteCount > 0)
      Positioned(
        right: 0, top: 0,
        child: _BadgeDot(count: inviteCount),
      ),
  ],
)
```

The invite count comes from a simple provider:
```dart
final inviteCountProvider = Provider<int>((ref) {
  final client = ref.watch(matrixServiceProvider).client;
  if (client == null) return 0;
  return client.rooms.where((r) => r.membership == Membership.invite).length;
});
```

### Task 5: Mobile Invite UI

On mobile, invites appear the same way — at the top of the room list in the Chats tab. The invite tile has slightly larger touch targets for Accept/Decline.

---

## Dependencies

| Dependency | Status | Risk |
|-----------|--------|------|
| `room.join()` | Available in matrix SDK | Low |
| `room.leave()` | Available in matrix SDK | Low |
| Room invite state events | Available via `room.getState()` | Low |
| `client.rooms` includes invites | Yes — SDK returns all memberships | Low |

No new packages needed.

## Success Criteria

- [ ] Invites appear at the top of the room list under `// invites` section
- [ ] Each invite shows room name, inviter, and accept/decline buttons
- [ ] Accept joins the room — invite card transitions to regular room tile after sync
- [ ] Decline removes the invite — card disappears after sync
- [ ] Accept button shows spinner while joining
- [ ] DM invites show the inviter's avatar and name prominently
- [ ] Room invites show the room name/avatar with "invited by" subtitle
- [ ] Invite count badge visible on space rail DM icon
- [ ] Works on both desktop and mobile layouts
- [ ] Bridge bot invites (like Libera.Chat) are handled the same as human invites

## Design Note

Should be designed in Pencil before implementation — need an invite tile card that's visually distinct from regular room tiles (slightly elevated, accent border, prominent accept/decline buttons).

---

## Change History

- 2026-03-26: Initial feature request from discovering that IRC bridge invites were invisible in Gloam
