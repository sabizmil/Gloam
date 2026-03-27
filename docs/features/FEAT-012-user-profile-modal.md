# FEAT-012: User Profile Modal

**Requested:** 2026-03-27
**Status:** Proposed
**Priority:** Medium
**Effort:** Small-Medium (2-3 days)

---

## Description

Clicking a user's avatar or name anywhere in Gloam (message timeline, member list, room info panel, voice channel participants) opens a centered overlay modal showing their profile. From there you can initiate a DM, start a call, see their role/power level, homeserver, online status, and mutual rooms.

This is a foundational social interaction pattern — it's how you discover and connect with people in every modern chat app (Discord, Slack, Cinny).

## User Story

As a Gloam user, I want to click on someone's avatar and see their profile with a "Message" button, so I can learn about them and start a conversation without leaving my current view.

---

## Design

**Variation C: Overlay Modal** (selected from Pencil prototypes)

- Centered 500px card over dimmed backdrop
- Gradient banner (derived from user's avatar color)
- Large avatar (88px) overlapping the banner edge, with online status dot
- Display name (large) + full Matrix ID (mono, tertiary)
- Action buttons: Message (accent), Call (surface), More (surface with ellipsis)
- Two-column detail grid: server, role/power level, online status
- Mutual rooms as clickable chips
- Close button on the banner corner
- Click outside to dismiss

---

## Where the Modal is Triggered

| Location | Trigger | What's available |
|----------|---------|-----------------|
| Message timeline (avatar) | Click avatar | senderId, senderName, senderAvatarUrl, roomId |
| Message timeline (name) | Click name | Same as avatar |
| Room info panel (member list) | Click member row | userId, displayName, avatarUrl, powerLevel |
| Voice channel participant tile | Click tile | userId, displayName, avatarUrl |
| Room list (DM avatar) | Click avatar | userId from directChatMatrixID |

All triggers need the same data: `userId` and `roomId` (for power level context). The modal fetches the rest from the SDK.

---

## Data Sources

| Field | Source |
|-------|--------|
| Display name | `room.unsafeGetUserFromMemoryOrFallback(userId).calcDisplayname()` or `client.getProfileFromUserId(userId)` |
| Avatar URL | `user.avatarUrl` (MXC URI) |
| Matrix ID | The `userId` string itself (`@phoenix:nerdforge.xyz`) |
| Homeserver | Extract from userId: `userId.split(':').last` |
| Power level | `room.getPowerLevelByUserId(userId)` |
| Role label | Derive from power level: 100 = Admin, 50 = Moderator, 0 = Member |
| Online/presence | `client.presences[userId]?.presence` (if available — presence is often disabled on homeservers) |
| Mutual rooms | `client.rooms.where((r) => r.getParticipants().any((m) => m.id == userId))` |
| Existing DM | `client.getDirectChatFromUserId(userId)` |

## Implementation Plan

### Task 1: User Profile Modal Widget

**New file:** `lib/features/profile/presentation/user_profile_modal.dart`

The modal widget and the `showUserProfile()` function that opens it:

```dart
Future<void> showUserProfile(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  String? roomId,  // for power level context
}) async {
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => UserProfileModal(userId: userId, roomId: roomId),
  );
}
```

Modal contents:
- Gradient banner (color seeded from userId hash, matching avatar color palette)
- Avatar (GloamAvatar, 88px, circular, overlapping banner)
- Online status dot (from presence if available, otherwise hidden)
- Name + Matrix ID
- Action row: Message, Call, More (ellipsis → context menu with Copy ID, Block, Ignore)
- Details grid: server, role, power level, presence
- Mutual rooms: chips that navigate to the room on tap
- Close button + click-outside-to-dismiss (handled by showDialog's barrier)

### Task 2: Profile Data Provider

**New file:** `lib/features/profile/providers/user_profile_provider.dart`

A FutureProvider that fetches all profile data for a given userId:

```dart
@riverpod
Future<UserProfileData> userProfile(
  UserProfileRef ref,
  String userId,
  String? roomId,
) async {
  final client = ref.read(matrixServiceProvider).client!;

  // Get profile from server (or memory)
  final profile = await client.getProfileFromUserId(userId);

  // Get power level from room context
  int? powerLevel;
  String? roleLabel;
  if (roomId != null) {
    final room = client.getRoomById(roomId);
    if (room != null) {
      powerLevel = room.getPowerLevelByUserId(userId);
      roleLabel = switch (powerLevel) {
        100 => 'Admin',
        >= 50 => 'Moderator',
        _ => 'Member',
      };
    }
  }

  // Find mutual rooms
  final mutualRooms = client.rooms
      .where((r) => r.membership == Membership.join)
      .where((r) {
        final members = r.getParticipants();
        return members.any((m) => m.id == userId);
      })
      .map((r) => MutualRoom(id: r.id, name: r.getLocalizedDisplayname()))
      .toList();

  // Check for existing DM
  final existingDmId = client.getDirectChatFromUserId(userId);

  // Presence (may not be available)
  final presence = client.presences[userId]?.currentlyActive == true
      ? 'online'
      : null;

  return UserProfileData(
    userId: userId,
    displayName: profile.displayName ?? userId.split(':').first.substring(1),
    avatarUrl: profile.avatarUrl,
    homeserver: userId.split(':').last,
    powerLevel: powerLevel,
    roleLabel: roleLabel,
    presence: presence,
    mutualRooms: mutualRooms,
    existingDmId: existingDmId,
  );
}
```

### Task 3: Message Action (Start/Open DM)

When the user clicks "Message":

```dart
void _onMessage(BuildContext context, WidgetRef ref, UserProfileData profile) async {
  // If DM already exists, navigate to it
  if (profile.existingDmId != null) {
    ref.read(selectedRoomProvider.notifier).state = profile.existingDmId;
    Navigator.of(context).pop(); // close modal
    return;
  }

  // Create a new DM room
  final client = ref.read(matrixServiceProvider).client!;
  final roomId = await client.startDirectChat(profile.userId);
  ref.read(selectedRoomProvider.notifier).state = roomId;
  Navigator.of(context).pop();
}
```

### Task 4: Wire Trigger Points

**Message bubble avatar/name click:**

File: `lib/features/chat/presentation/widgets/message_bubble.dart`

Wrap the avatar and sender name in a GestureDetector:

```dart
GestureDetector(
  onTap: () => showUserProfile(context, ref,
    userId: message.senderId, roomId: roomId),
  child: GloamAvatar(displayName: message.senderName, ...),
)
```

Same for the sender name text.

**Room info panel member list:**

File: `lib/app/shell/room_info_panel.dart`

Each member row becomes tappable:

```dart
GestureDetector(
  onTap: () => showUserProfile(context, ref,
    userId: member.userId, roomId: roomId),
  child: _MemberRow(member: member),
)
```

**Voice participant tile:**

File: `lib/features/calls/presentation/widgets/participant_tile.dart`

Tap (not long-press) opens profile:

```dart
GestureDetector(
  onTap: () => showUserProfile(context, ref,
    userId: participant.id),
  // existing onSecondaryTapDown/onLongPressStart for context menu
  child: Container(...)
)
```

### Task 5: Call Action

The Call button in the profile modal starts a voice call to the DM:

```dart
void _onCall(BuildContext context, WidgetRef ref, UserProfileData profile) async {
  // Ensure DM exists
  final client = ref.read(matrixServiceProvider).client!;
  final roomId = profile.existingDmId ??
      await client.startDirectChat(profile.userId);

  ref.read(callServiceProvider.notifier).startCall(
    roomId: roomId,
    isVideo: false,
  );
  Navigator.of(context).pop();
}
```

### Task 6: More Menu

The ellipsis button shows a popup menu:

- **Copy Matrix ID** — copies `@phoenix:nerdforge.xyz` to clipboard
- **View in room info** — opens the room info panel focused on this user
- **Ignore user** (future) — `client.ignoreUser(userId)`

---

## File Layout

```
lib/features/profile/
├── presentation/
│   └── user_profile_modal.dart    # Modal widget + showUserProfile()
└── providers/
    └── user_profile_provider.dart # Data fetching + UserProfileData model
```

## Files to Modify

| File | Change |
|------|--------|
| `lib/features/chat/presentation/widgets/message_bubble.dart` | Wrap avatar + name in GestureDetector → showUserProfile |
| `lib/app/shell/room_info_panel.dart` | Make member rows tappable → showUserProfile |
| `lib/features/calls/presentation/widgets/participant_tile.dart` | Tap → showUserProfile (keep long-press for context menu) |

## Dependencies

No new packages. Uses existing:
- `client.getProfileFromUserId()` — fetch profile from server
- `client.getDirectChatFromUserId()` — find existing DM
- `client.startDirectChat()` — create new DM
- `room.getPowerLevelByUserId()` — get power level
- `client.presences` — presence data (if server supports it)

## Success Criteria

- [ ] Clicking any avatar in the message timeline opens the profile modal
- [ ] Clicking a sender name opens the same modal
- [ ] Modal shows: avatar, name, Matrix ID, homeserver, role, power level
- [ ] Online status dot shown when presence data is available
- [ ] "Message" button opens existing DM or creates a new one
- [ ] "Call" button starts a voice call to the user's DM
- [ ] Mutual rooms listed as clickable chips (navigate on tap)
- [ ] "More" menu with Copy Matrix ID
- [ ] Clicking a member in the room info panel opens the modal
- [ ] Clicking a voice participant tile opens the modal
- [ ] Click outside modal or X button dismisses it
- [ ] Modal loads instantly for users with cached profiles, shows spinner for server fetch

---

## Change History

- 2026-03-27: Initial plan. Design Variation C (overlay modal) selected from 3 prototypes.
