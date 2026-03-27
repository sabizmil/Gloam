# Phase 5D: Video, Screen Share + Polish

**Weeks 10–12 | Milestone: Video calls, screen sharing, voice settings panel, per-user volume, and production-ready reliability**

*Last updated: 2026-03-26*

---

## Objectives

1. Add video track support to voice channels and DM calls — camera toggle, gallery grid layout, active speaker spotlight.
2. Implement screen sharing on desktop (window/screen picker) and mobile (ReplayKit / MediaProjection).
3. Build the voice settings screen: input/output device selection, volume sliders, input mode (Voice Activity / Push-to-Talk), voice processing toggles.
4. Implement per-user volume control via context menu on participants.
5. Add Push-to-Talk mode with configurable keybind and release delay.
6. Ship connection diagnostics panel (ping, packet loss, codec info).
7. Voice moderation: server mute/deafen, disconnect member, voice-specific power levels.
8. Platform testing and hardening across macOS, iOS, and Android.

## Success Criteria

- [ ] Toggle camera in voice channel → video feed appears in participant tile, avatar replaced by live video
- [ ] Gallery grid adapts to participant count: 1×2, 2×2, 2×3, 3×3
- [ ] Active speaker spotlight: when enabled, speaker gets large view, others shrink to strip
- [ ] Screen share (desktop): window/screen picker dialog, shared content fills main area
- [ ] Screen share (mobile): system permission prompt, broadcast starts
- [ ] "You are sharing your screen" banner with stop button
- [ ] Receiving screen share: auto-layout switch, participants move to sidebar strip
- [ ] Voice settings: input device dropdown, volume slider (0–100%), mic test
- [ ] Voice settings: output device dropdown, volume slider
- [ ] Voice settings: Voice Activity (with sensitivity slider) and Push-to-Talk radio buttons
- [ ] Voice settings: echo cancellation, noise reduction, auto gain control, noise suppression toggles
- [ ] Push-to-Talk: hold key to transmit, configurable keybind, release delay slider
- [ ] Right-click participant → per-user volume slider (0–200%)
- [ ] Right-click participant → "Mute for me" (local-only mute)
- [ ] Connection quality click → diagnostics: ping, packet loss, codec, server region
- [ ] Moderator can server-mute a participant (they cannot unmute themselves)
- [ ] Moderator can disconnect a participant from the voice channel
- [ ] Voice channel capacity limits enforced (show "Channel full" error)
- [ ] All features work on macOS, iOS; Android at functional parity

---

## Task Breakdown

### Task 1: Video Track Management

**4 days | Complexity: Medium**

#### 1.1 Camera enable/disable

Extend `VoiceLocalMedia` and `LivekitMediaManager`:

```dart
Future<void> setVideo(bool enabled) async {
  if (enabled) {
    await _localParticipant?.setCameraEnabled(true);
  } else {
    await _localParticipant?.setCameraEnabled(false);
  }
  _updateParticipants();
}

/// Switch between front and back camera (mobile)
Future<void> flipCamera() async {
  final track = _localParticipant?.videoTrackPublications.firstOrNull?.track;
  if (track is LocalVideoTrack) {
    await track.switchCamera();
  }
}
```

#### 1.2 Video rendering in participant tiles

When `participant.hasVideo` is true, replace the avatar with a `VideoTrackRenderer`:

```dart
// In participant_tile.dart
Widget _buildVisual(VoiceParticipant participant) {
  if (participant.hasVideo && participant.videoTrack != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: VideoTrackRenderer(
        participant.videoTrack!,
        fit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }
  return _buildAvatar(participant);
}
```

The `videoTrack` needs to be passed through the participant model. Add an optional `dynamic videoTrack` field to `VoiceParticipant.protocolMetadata` or create a `VoiceParticipantWithMedia` wrapper that the UI layer consumes.

#### 1.3 Gallery grid layout

Dynamic grid sizing based on participant count:

| Participants | Grid | Tile Size (desktop, 1096px content width) |
|-------------|------|------------------------------------------|
| 1 | 1×1 | 548×400 (centered) |
| 2 | 1×2 | 440×400 |
| 3–4 | 2×2 | 440×300 |
| 5–6 | 2×3 | 290×300 |
| 7–9 | 3×3 | 290×200 |
| 10+ | 3×3 + scroll | 290×200 (paginated) |

```dart
int _getCrossAxisCount(int participantCount) {
  if (participantCount <= 1) return 1;
  if (participantCount <= 4) return 2;
  return 3;
}
```

#### 1.4 Active speaker spotlight

When enabled (toggle in voice channel header):
- Speaker gets 70% of the area (large view)
- Other participants in a horizontal strip below (small tiles)
- Speaker switches based on LiveKit's `activeSpeakers` with 1.5-second debounce

```dart
// Debounce rapid speaker switching
Timer? _speakerDebounce;
String? _spotlightedUserId;

void _onActiveSpeakerChanged(List<Participant> speakers) {
  if (speakers.isEmpty) return;
  final newSpeaker = speakers.first.identity;
  if (newSpeaker == _spotlightedUserId) return;

  _speakerDebounce?.cancel();
  _speakerDebounce = Timer(const Duration(milliseconds: 1500), () {
    _spotlightedUserId = newSpeaker;
    _updateLayout();
  });
}
```

---

### Task 2: Screen Sharing

**4 days | Complexity: High**

#### 2.1 Desktop screen sharing

LiveKit + flutter_webrtc handle screen capture:

```dart
Future<void> startScreenShare() async {
  // Show system picker (window or screen selection)
  final source = await _localParticipant?.setScreenShareEnabled(true,
    captureScreenAudio: true, // Share system audio where supported
  );
  _updateParticipants();
}

Future<void> stopScreenShare() async {
  await _localParticipant?.setScreenShareEnabled(false);
  _updateParticipants();
}
```

**"Sharing your screen" banner:**
```dart
if (voiceState.participants.any((p) => p.isSelf && p.isScreenSharing))
  Container(
    color: GloamColors.accentDim,
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(children: [
      Icon(LucideIcons.monitor, color: GloamColors.accent, size: 16),
      SizedBox(width: 8),
      Text('You are sharing your screen', style: ...),
      Spacer(),
      TextButton(onPressed: stopScreenShare, child: Text('Stop')),
    ]),
  ),
```

#### 2.2 Mobile screen sharing

- **iOS**: Uses ReplayKit broadcast extension. Requires a separate broadcast upload extension target in the iOS project.
- **Android**: Uses MediaProjection API. System permission dialog appears.

Both are handled by LiveKit's `setScreenShareEnabled()` — the Flutter SDK triggers the appropriate platform mechanism.

#### 2.3 Receiving screen shares

When another participant starts screen sharing, the voice channel view layout switches:
- Screen share content takes the main area (full width)
- Participants move to a vertical strip on the right (80px wide, avatars stacked)

```dart
Widget _buildLayout(List<VoiceParticipant> participants) {
  final screenSharer = participants.firstWhereOrNull((p) => p.isScreenSharing && !p.isSelf);

  if (screenSharer != null) {
    return Row(children: [
      Expanded(child: _ScreenShareView(participant: screenSharer)),
      _ParticipantStrip(participants: participants, width: 80),
    ]);
  }

  return _buildGrid(participants);
}
```

---

### Task 3: Voice Settings Screen

**3 days | Complexity: Low**

#### 3.1 Route

Add to `router.dart`:
```dart
GoRoute(
  path: '/settings/voice',
  builder: (context, state) => const VoiceSettingsScreen(),
),
```

Also accessible from the main settings panel (add a "Voice & Audio" row in settings).

#### 3.2 Voice settings screen — `lib/features/calls/presentation/screens/voice_settings_screen.dart`

Sections (matching the design in `gloam.pen`):

**Input section:**
- Device dropdown (populated from `AudioDeviceService.getInputDevices()`)
- Volume slider (0–100%)
- "Test Microphone" button (record 3 seconds, play back)

**Output section:**
- Device dropdown
- Volume slider

**Input mode:**
- Voice Activity (radio, selected by default) with sensitivity slider
- Push to Talk (radio) with keybind recorder and release delay slider

**Voice processing:**
- Echo Cancellation toggle (default: on)
- Noise Reduction toggle (default: on)
- Auto Gain Control toggle (default: on)
- Noise Suppression (AI) toggle (default: off — more CPU intensive)

All settings persisted via `SharedPreferences` and applied to `AudioDeviceService` state.

#### 3.3 Mic test

```dart
Future<void> testMicrophone() async {
  // 1. Capture 3 seconds of audio from the selected input device
  // 2. Show a recording indicator with countdown
  // 3. Play back the recorded audio through the selected output device
  // Uses flutter_webrtc's getUserMedia + audio element playback
}
```

---

### Task 4: Per-User Volume + Context Menu

**2 days | Complexity: Low**

#### 4.1 Participant context menu

Right-click (desktop) or long-press (mobile) on a participant tile:

```dart
showMenu(
  context: context,
  items: [
    // Volume slider
    _VolumeMenuItem(
      currentVolume: _getUserVolume(participant.id),
      onChanged: (vol) => voiceService.adapter?.localMedia.setUserVolume(participant.id, vol),
    ),
    PopupMenuItem(child: Text('Mute for me'), onTap: () => _muteLocally(participant.id)),
    if (permissions.canMuteOthers) ...[
      PopupMenuDivider(),
      PopupMenuItem(child: Text('Server Mute'), onTap: () => _serverMute(participant.id)),
      PopupMenuItem(child: Text('Disconnect'), onTap: () => _disconnect(participant.id)),
    ],
  ],
);
```

#### 4.2 Volume slider

Range: 0% to 200% (0.0 to 2.0). Default: 100% (1.0).

Implementation: `LivekitMediaManager.setUserVolume()` adjusts the audio track gain for that specific remote participant. This is a local-only operation — other participants are unaffected.

---

### Task 5: Push-to-Talk

**2 days | Complexity: Medium**

#### 5.1 Implementation

```dart
class PushToTalkManager {
  final VoiceLocalMedia _localMedia;
  bool _isHolding = false;
  Timer? _releaseTimer;
  Duration releaseDelay = const Duration(milliseconds: 200);

  /// Call when PTT key is pressed
  void onKeyDown() {
    _releaseTimer?.cancel();
    if (!_isHolding) {
      _isHolding = true;
      _localMedia.setMuted(false);
    }
  }

  /// Call when PTT key is released
  void onKeyUp() {
    _releaseTimer = Timer(releaseDelay, () {
      _isHolding = false;
      _localMedia.setMuted(true);
    });
  }
}
```

#### 5.2 Keybind registration

Desktop: Use `RawKeyboardListener` or `HardwareKeyboard` to detect global key events.

Note: True global hotkeys (outside the app window) require platform-specific plugins and are deferred. In-app PTT works in Phase 5D; global hotkeys are a future enhancement.

#### 5.3 PTT indicator

When PTT is active and key is held, show a "Transmitting" indicator in the voice bar:
```
🔊 lounge · matrix.org     ● TRANSMITTING     🎤 🎧 📞
```

---

### Task 6: Connection Diagnostics

**1 day | Complexity: Low**

#### 6.1 Diagnostics panel

Click the connection quality dot in the voice bar or call screen to open a diagnostics overlay:

```dart
class ConnectionDiagnostics extends StatelessWidget {
  // Data sourced from LiveKit Room.engine.connectionStats
  // and LiveKit's RemoteParticipant stats

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GloamColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GloamColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('// connection', style: sectionLabelStyle),
        _Row('Server', sfuUrl),
        _Row('Ping', '${pingMs}ms'),
        _Row('Packet Loss', '${packetLoss}%'),
        _Row('Codec', 'Opus'),
        _Row('Bitrate', '${bitrate}kbps'),
        SizedBox(height: 12),
        Text('// participants', style: sectionLabelStyle),
        for (final p in participants)
          _Row(p.displayName, _qualityLabel(p.connectionQuality)),
      ]),
    );
  }
}
```

---

### Task 7: Voice Moderation

**3 days | Complexity: Medium**

#### 7.1 Server mute

Moderators with sufficient power level can mute another participant. Implemented as a custom state event:

```dart
Future<void> serverMute(String roomId, String userId) async {
  await _client.setRoomStateWithKey(
    roomId,
    'im.gloam.voice.moderation',
    userId,
    {'muted': true, 'deafened': false},
  );
}
```

Participants listen for this event and enforce it:
- If `im.gloam.voice.moderation` for your user ID has `muted: true`, your mic is force-muted
- The UI shows a red mic icon and disables the unmute button
- Only a moderator can clear the moderation event

#### 7.2 Disconnect member

Moderators can remove another user from the voice channel by clearing their `m.rtc.member` event:

```dart
Future<void> disconnectMember(String roomId, String userId) async {
  await _client.setRoomStateWithKey(
    roomId,
    'org.matrix.msc3401.call.member',
    userId,
    {'memberships': []},
  );
}
```

The target client sees their membership cleared and disconnects from LiveKit.

#### 7.3 Voice-specific power levels

Define custom power levels for voice actions:
- `im.gloam.voice.speak` — minimum power to transmit audio (default: 0)
- `im.gloam.voice.video` — minimum power to use camera/screen share (default: 0)
- `im.gloam.voice.moderate` — minimum power to server-mute/disconnect others (default: 50)

These are stored in the room's `m.room.power_levels` event under a custom namespace.

#### 7.4 Capacity enforcement

When a user tries to join a voice channel that's at capacity:

```dart
Future<void> joinChannel(String channelId) async {
  final config = _getVoiceConfig(channelId);
  if (config.maxParticipants != null) {
    final currentCount = _getActiveParticipantCount(channelId);
    if (currentCount >= config.maxParticipants!) {
      throw VoiceChannelFullException(channelId, config.maxParticipants!);
    }
  }
  // Proceed with join...
}
```

The UI shows a toast/snackbar: "Channel full (5/5)".

---

### Task 8: Platform Testing + Hardening

**3 days | Complexity: Medium**

#### 8.1 Test matrix

| Feature | macOS | iOS | Android |
|---------|-------|-----|---------|
| Voice channels (join/leave/talk) | Primary | Primary | Secondary |
| Persistent voice bar | Primary | Primary | Secondary |
| DM calls (ring/answer) | Primary | Primary | Secondary |
| Video in voice channels | Primary | Primary | Secondary |
| Screen sharing (send) | Primary | N/A (deferred) | N/A (deferred) |
| Screen sharing (receive) | Primary | Primary | Secondary |
| CallKit incoming call | N/A | Primary | Secondary |
| PiP | N/A | Primary | Secondary |
| Audio device switching | Primary | Primary | Secondary |
| Bluetooth audio routing | N/A | Primary | Secondary |

#### 8.2 Known platform risks

- **macOS + flutter_webrtc**: Screen capture works on macOS but requires screen recording permission in System Preferences. Detect and guide user.
- **iOS background audio**: Requires `UIBackgroundModes: voip` and correct `AVAudioSession` configuration. Test thoroughly with app backgrounded.
- **Android 14+**: Requires `FOREGROUND_SERVICE_PHONE_CALL` permission type for call foreground services.
- **Audio routing changes**: Bluetooth connect/disconnect, headphone plug/unplug — test that audio route switches cleanly without drops.

#### 8.3 Reliability testing

- Network interruption: disconnect WiFi for 5 seconds, verify auto-reconnect
- App background/foreground cycle during voice channel
- Memory pressure: monitor memory usage during 30-minute voice session
- Battery impact: measure battery drain during idle voice channel (target: minimal with Opus DTX)

---

## Dependencies & Blockers

| Dependency | Required By | Status | Risk |
|-----------|------------|--------|------|
| Phase 5A + 5B + 5C complete | All tasks | Must complete first | — |
| iOS ReplayKit broadcast extension | Task 2.2 | New Xcode target needed | Medium |
| Screen recording permission (macOS) | Task 2.1 | System Preferences entry | Low |
| `FOREGROUND_SERVICE_PHONE_CALL` (Android 14+) | Task 7 | Manifest change | Low |

## What "Done" Looks Like

1. In a voice channel with 4 people: toggle camera → your tile shows live video, others see it
2. Screen share your VS Code window → it fills the main area, participants move to a sidebar strip, "Sharing your screen" banner with Stop button appears
3. Open Voice & Audio settings → select a different microphone, test it, hear playback
4. Switch to Push-to-Talk mode → hold key to talk, release to mute, release delay prevents clipping
5. Right-click a loud participant → adjust their volume to 60%, they're quieter for you only
6. Click the connection quality dot → see 12ms ping, 0.1% packet loss, Opus codec
7. As a moderator, right-click a disruptive user → Server Mute → they see red mic icon, can't unmute
8. Try to join a full channel → "Channel full (5/5)" toast appears
9. Run a 30-minute voice session with 5 participants → no audio drops, memory stable, battery acceptable

---

## Phase 5 Complete — What Ships

After all four sub-phases, Gloam has:

- **Discord-caliber voice channels**: ambient join/leave, participant grid with speaking indicators, persistent bar, text-in-voice
- **Full DM calls**: ring-to-answer with CallKit/Android integration, voice + video, PiP
- **Screen sharing**: desktop window/screen sharing with participant strip layout
- **Voice settings**: device management, input modes, processing toggles
- **Moderation**: server mute, disconnect, capacity limits, voice-specific permissions
- **Multi-protocol ready**: all UI built against abstract interfaces; Mumble adapter can plug in without touching any UI code

No other Matrix client ships this feature set.

---

## Change History

- 2026-03-26: Initial implementation plan created
