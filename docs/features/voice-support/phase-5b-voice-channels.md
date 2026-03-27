# Phase 5B: Voice Channels + Persistent Bar

**Weeks 4–6 | Milestone: Full Discord-like voice channel UX — ambient join/leave, speaking indicators, persistent bar across all navigation**

*Last updated: 2026-03-26*

---

## Objectives

1. Integrate voice channels into the room list sidebar with speaker icons, participant avatars, and speaking indicators — visually distinct from text channels.
2. Build the voice channel view with a participant grid showing real-time audio levels, mute/deafen states, and user avatars.
3. Ship the persistent voice bar — visible on every screen while connected, with mute/deafen/disconnect controls and tap-to-navigate-back.
4. Implement text-in-voice: the room's existing message timeline shown alongside the participant grid.
5. Wire up join/leave/switch flows: single-click join, confirmation when switching channels, instant disconnect.
6. Add voice channel creation and configuration (capacity limits, room tagging).

## Success Criteria

- [ ] Voice channels appear in the room list sidebar with `volume-2` icon instead of `#`
- [ ] Connected participants shown as avatar row beneath voice channel name (max 5 + "+N")
- [ ] Speaking participant's avatar has animated green ring in sidebar
- [ ] Clicking a voice channel immediately connects (no lobby, no ringing)
- [ ] Clicking a different voice channel shows "Switch to X?" confirmation
- [ ] Voice channel view shows participant grid: avatars with names, speaking rings, mute/deafen icons
- [ ] Text-in-voice panel shows room timeline below participant grid with message composer
- [ ] Persistent voice bar visible on room list, chat views, settings — all routes
- [ ] Voice bar shows: channel name, space name, timer, quality dot, mute/deafen/disconnect buttons
- [ ] Tapping voice bar channel name navigates to the voice channel view
- [ ] Disconnect button immediately leaves (no confirmation)
- [ ] Connection timer counts up from join time
- [ ] Connection quality indicator (green/yellow/red) from LiveKit stats
- [ ] Navigate away from voice channel → bar persists, audio continues
- [ ] Voice channel creation via "Create Voice Channel" in space settings
- [ ] `im.gloam.voice_channel` room tag applied to voice channels
- [ ] Empty voice channels still visible in sidebar (with no participant row)
- [ ] Works on macOS and iOS

---

## Task Breakdown

### Task 1: Voice Channel Room List Integration

**4 days | Complexity: Medium**

Modify the existing room list to recognize voice channels and render them differently.

#### 1.1 Voice channel detection

In `lib/features/calls/data/adapters/matrix_rtc_adapter.dart`, the `VoiceChannelManager` implementation:

```dart
class _MatrixChannelManager implements VoiceChannelManager {
  final Client _client;

  @override
  bool isVoiceChannel(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null) return false;

    // Check room create event for voice channel type
    final createEvent = room.getState(EventTypes.RoomCreate);
    final roomType = createEvent?.content['type'];
    if (roomType == 'im.gloam.voice_channel') return true;

    // Also check room tags as fallback
    return room.tags.containsKey('im.gloam.voice_channel');
  }

  @override
  Stream<List<VoiceChannel>> get channels {
    // Filter all rooms in current space that are voice channels
    // Map to VoiceChannel entities with participant counts from m.rtc.member events
  }
}
```

#### 1.2 Room list modification

In `lib/features/rooms/presentation/providers/room_list_provider.dart`, add voice channel awareness:

```dart
// New model to distinguish voice channels in the room list
@freezed
class RoomListSection with _$RoomListSection {
  const factory RoomListSection.dms({required List<RoomListItem> items}) = _DmSection;
  const factory RoomListSection.channels({required List<RoomListItem> items}) = _ChannelSection;
  const factory RoomListSection.voiceChannels({required List<VoiceChannelListItem> items}) = _VoiceChannelSection;
}

@freezed
class VoiceChannelListItem with _$VoiceChannelListItem {
  const factory VoiceChannelListItem({
    required String roomId,
    required String name,
    required List<VoiceParticipant> connectedParticipants,
    required bool isCurrentlyConnected,
  }) = _VoiceChannelListItem;
}
```

#### 1.3 Voice channel sidebar widget

New widget: `lib/features/calls/presentation/widgets/voice_channel_sidebar.dart`

Renders a voice channel entry in the sidebar with:
- Speaker icon (`volume-2`) instead of `#`
- Channel name (accent color when connected, secondary when not)
- Participant avatar row when people are connected (max 5 mini avatars + "+N")
- Green ring on speaking participant's avatar
- Mute icon overlay on muted participants

The participant data comes from `VoiceService` for the currently connected channel, and from `MatrixRTCSignaling` (reading `m.rtc.member` state events) for other voice channels the user isn't in.

#### 1.4 Voice channel sorting

Voice channels appear in the room list under a `// voice channels` section label, after text channels. Within the section, channels with active participants sort first.

---

### Task 2: Voice Channel View

**4 days | Complexity: Medium**

The main content area when viewing a voice channel — participant grid + text-in-voice.

#### 2.1 Participant grid — `lib/features/calls/presentation/widgets/participant_grid.dart`

```dart
class ParticipantGrid extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceState = ref.watch(voiceServiceProvider);
    final participants = voiceState.maybeMap(
      connected: (s) => s.participants,
      orElse: () => <VoiceParticipant>[],
    );

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: participants.map((p) => ParticipantTile(participant: p)).toList(),
    );
  }
}
```

#### 2.2 Participant tile — `lib/features/calls/presentation/widgets/participant_tile.dart`

Each tile shows:
- Avatar (large, centered) with animated green border when `isSpeaking`
- Display name below
- Status indicator: "speaking" in accent, mic-off icon + "muted" in tertiary, headphone icon + "deafened" in warning
- Server mute indicator (red, distinct)
- Video feed replaces avatar when `hasVideo` (Phase 5D)

**Speaking animation:**
```dart
// Animate border opacity/thickness based on audioLevel
AnimatedContainer(
  duration: const Duration(milliseconds: 150),
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    border: Border.all(
      color: participant.isSpeaking
        ? GloamColors.accent.withOpacity(participant.audioLevel.clamp(0.3, 1.0))
        : Colors.transparent,
      width: participant.isSpeaking ? 3.0 : 0.0,
    ),
  ),
  child: avatar,
)
```

#### 2.3 Voice channel screen — `lib/features/calls/presentation/screens/voice_channel_screen.dart`

Layout (desktop):
```
Column(
  children: [
    VoiceChannelHeader(channelName, participantCount, settingsButton),
    Expanded(
      child: Center(child: ParticipantGrid()),
    ),
    TextInVoicePanel(roomId),  // collapsible
  ],
)
```

#### 2.4 Text-in-voice panel

Reuses the existing `Timeline` and `MessageComposer` widgets from `lib/features/chat/`. No new message code needed — just embed the existing chat widgets in a constrained-height panel below the participant grid.

```dart
class TextInVoicePanel extends ConsumerWidget {
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: GloamColors.bgSurface,
        border: Border(top: BorderSide(color: GloamColors.border)),
      ),
      child: Column(
        children: [
          _TextInVoiceHeader(),
          Expanded(child: Timeline(roomId: roomId, compact: true)),
          MessageComposer(roomId: roomId, compact: true),
        ],
      ),
    );
  }
}
```

---

### Task 3: Persistent Voice Bar

**5 days | Complexity: High**

The most architecturally important widget. Must be visible on **every route** while connected to voice.

#### 3.1 Implementation strategy

The voice bar cannot live inside any specific route's widget tree — it must be above the router. Add it to `lib/features/rooms/presentation/screens/home_screen.dart` (the root shell) as an overlay that appears when `voiceService.isConnected`.

```dart
// In home_screen.dart (the root scaffold)
class HomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceState = ref.watch(voiceServiceProvider);
    final isConnected = voiceState is VoiceStateConnected;

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: _existingLayout()),
          if (isConnected)
            PersistentVoiceBar(state: voiceState as VoiceStateConnected),
        ],
      ),
    );
  }
}
```

On mobile, the voice bar sits above the bottom tab bar. On desktop, it spans the full width at the bottom of the chat area (to the right of the sidebar).

#### 3.2 Persistent voice bar widget — `lib/features/calls/presentation/widgets/persistent_voice_bar.dart`

```dart
class PersistentVoiceBar extends ConsumerWidget {
  final VoiceStateConnected state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceService = ref.read(voiceServiceProvider.notifier);
    final localMedia = voiceService.localMedia;
    final elapsed = DateTime.now().difference(state.connectedAt);

    return Container(
      height: 52,
      color: GloamColors.bgElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Left: channel info (tappable — navigates to voice channel)
          GestureDetector(
            onTap: () => context.go('/voice/${state.channelId}'),
            child: Row(children: [
              Icon(LucideIcons.volume2, color: GloamColors.accent, size: 18),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${state.channelName} · ${state.protocolName}', ...),
                Text(_participantNames(state.participants), ...),
              ]),
            ]),
          ),

          const Spacer(),

          // Center: timer + quality
          Text(_formatDuration(elapsed), ...),
          const SizedBox(width: 8),
          _ConnectionDot(quality: _overallQuality(state.participants)),

          const Spacer(),

          // Right: controls
          _BarButton(icon: LucideIcons.mic, onTap: () => localMedia?.setMuted(true)),
          _BarButton(icon: LucideIcons.headphones, onTap: () => localMedia?.setDeafened(true)),
          _BarButton(
            icon: LucideIcons.phoneOff,
            color: GloamColors.danger,
            onTap: () => voiceService.disconnect(),
          ),
        ],
      ),
    );
  }
}
```

#### 3.3 Timer

Use a `Timer.periodic` or `Stream.periodic` to update the elapsed time display every second. Start the timer when `VoiceState.connected` is entered, cancel when disconnected.

#### 3.4 Mobile voice bar

On mobile, the bar is slightly taller (64px) with larger touch targets. It appears between the content and the bottom tab bar. Swipe up on it to expand into a mini control panel with additional options (camera, screen share).

---

### Task 4: Join / Leave / Switch Flows

**2 days | Complexity: Low**

#### 4.1 Join flow

1. User taps voice channel in sidebar
2. If not connected to any voice: immediately join (no dialog)
3. Request mic permission if not yet granted
4. `voiceService.joinChannel(adapter, channelId)` — starts connecting
5. Voice bar appears, voice channel view opens
6. Mic defaults to unmuted (configurable in settings)

#### 4.2 Switch flow

1. User taps a different voice channel while already connected
2. Show bottom sheet: "Switch to [channel]? You'll leave [current channel]."
3. "Switch" button: disconnect from current, join new
4. "Cancel" button: dismiss

#### 4.3 Leave flow

1. User taps disconnect button in voice bar
2. Immediately disconnect — no confirmation
3. Voice bar disappears
4. If viewing the voice channel screen, navigate back to previous route

---

### Task 5: Voice Channel Creation

**2 days | Complexity: Low**

#### 5.1 Create voice channel flow

In space settings or via a "+" button in the voice channels section:

1. Dialog: channel name, optional description, optional capacity limit
2. Create a Matrix room with `im.gloam.voice_channel` type:
   ```dart
   await client.createRoom(
     name: channelName,
     topic: description,
     creationContent: {'type': 'im.gloam.voice_channel'},
     roomVersion: '11',
     visibility: Visibility.private,
     preset: CreateRoomPreset.privateChat,
     initialState: [
       // Add to parent space
       StateEvent(
         type: 'm.space.child',
         stateKey: newRoomId,
         content: {'via': [client.homeserver!.host]},
       ),
     ],
   );
   ```
3. Room appears in the voice channels section of the sidebar

#### 5.2 Channel settings

- Capacity limit: stored as a custom state event `im.gloam.voice_config` with `max_participants`
- Bitrate: stored in same event, applied as LiveKit room config

---

### Task 6: Router Integration

**1 day | Complexity: Low**

Add a route for the voice channel view in `lib/app/router.dart`:

```dart
GoRoute(
  path: '/voice/:roomId',
  builder: (context, state) => VoiceChannelScreen(
    roomId: state.pathParameters['roomId']!,
  ),
),
```

The voice channel screen is a full-page route on mobile, and replaces the chat area on desktop (same position as the regular chat view).

---

## Dependencies & Blockers

| Dependency | Required By | Status | Risk |
|-----------|------------|--------|------|
| Phase 5A complete (all infrastructure) | All tasks | Must complete first | — |
| Existing room list widget (`room_list_tile.dart`) | Task 1 | Exists, needs modification | Low |
| Existing timeline + composer widgets | Task 2.4 | Exists, reuse directly | Low |
| GoRouter (`router.dart`) | Task 6 | Exists, add one route | Low |
| Home screen scaffold (`home_screen.dart`) | Task 3 | Exists, add voice bar | Low |

## Key Technical Decisions

| Decision | Options | Recommendation | Rationale |
|----------|---------|---------------|-----------|
| Voice bar placement | Above tab bar vs below content | **Bottom of content, above tab bar (mobile) / spanning chat area (desktop)** | Matches Discord's pattern. Must not cover chat content. |
| Voice channel detection for channels user isn't in | Poll `m.rtc.member` events vs subscribe to room state | **Subscribe to room state on visible channels** | Room state sync provides `m.rtc.member` events for all rooms in the space. Parse those for participant counts without joining the voice session. |
| Text-in-voice | New chat component vs reuse existing | **Reuse existing `Timeline` + `MessageComposer`** with `compact: true` flag | Avoids duplicating the entire chat infrastructure. The voice channel's room already has a timeline. |

## What "Done" Looks Like

1. Open Gloam, navigate to a space with voice channels
2. Voice channels appear in the sidebar with speaker icons
3. "lounge" has 3 people connected — their mini-avatars show beneath the channel name
4. Click "lounge" — immediately connected, participant grid shows 3 tiles with one speaking (green ring animating)
5. Text chat area below shows the room's messages; type a message, it appears
6. Navigate to `#design` text channel — voice bar appears at the bottom: "lounge · matrix.org | 0:05:23 | 🟢 | 🎤 🎧 📞"
7. Voice continues playing through speakers while reading text chat
8. Tap the voice bar's channel name — navigates back to lounge voice view
9. Tap disconnect — bar disappears, audio stops, removed from participant list
10. Other clients see you leave in real-time

---

## Change History

- 2026-03-26: Initial implementation plan created
