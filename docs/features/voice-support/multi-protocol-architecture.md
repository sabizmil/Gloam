# Multi-Protocol Voice Architecture — Forward-Looking Design

*Created: 2026-03-26*

This document ensures the voice support described in the [PRD](PRD.md) is built with a protocol-agnostic abstraction layer, so future integrations (Mumble, Jitsi, potentially TeamSpeak) can plug in without rewriting the voice UI or state management.

### Companion Documents

- [PRD](PRD.md) — Feature specification and phased plan (MatrixRTC first)
- [Element Call / MatrixRTC Research](element-call-research.md) — Primary protocol deep dive
- [Mumble, TeamSpeak & Multi-Protocol Research](mumble-teamspeak-research.md) — Secondary protocol research

---

## The Problem

The PRD currently specs voice support as a MatrixRTC + LiveKit implementation. That's correct for v1. But if `VoiceService`, the UI, and the persistent voice bar are all wired directly to MatrixRTC event types and LiveKit APIs, adding Mumble later means:

- Forking the entire voice UI to handle a different participant model
- Duplicating the persistent voice bar logic for each protocol
- Rewriting permission checks everywhere
- Managing two completely separate voice state machines

We need to build once and swap the backend.

---

## Design Principle: Split at the Right Seam

The voice system has a natural split point:

```
┌─────────────────────────────────────────────────┐
│                 PROTOCOL-AGNOSTIC                │
│                                                  │
│  Voice UI (channel view, participant grid, bar)  │
│  VoiceService (global state, Riverpod provider)  │
│  Audio device management                         │
│  Permission normalization                        │
│  Voice settings (input mode, processing)         │
│  Call UI (ring, answer, active call screens)     │
│  Notification handling                           │
└─────────────────────┬───────────────────────────┘
                      │
              VoiceProtocolAdapter
                      │
      ┌───────────────┼───────────────┐
      │               │               │
┌─────┴─────┐  ┌──────┴──────┐  ┌────┴────┐
│ MatrixRTC  │  │   Mumble    │  │  Jitsi  │
│  Adapter   │  │   Adapter   │  │ Adapter │
│            │  │             │  │         │
│ livekit_   │  │  dumble +   │  │ jitsi_  │
│ client +   │  │  opus_dart  │  │ meet_   │
│ matrix SDK │  │             │  │ sdk     │
└────────────┘  └─────────────┘  └─────────┘
```

Everything above the line is shared. Everything below is swappable.

---

## The Abstraction Layer

### Core Interfaces

These are the Dart abstract classes that all protocol adapters must implement. The UI and `VoiceService` only talk to these — never to LiveKit, dumble, or any protocol SDK directly.

#### VoiceProtocolAdapter

The top-level entry point. One instance per active connection.

```dart
abstract class VoiceProtocolAdapter {
  /// Unique identifier for this protocol type
  String get protocolId; // "matrixrtc", "mumble", "jitsi"

  /// Human-readable name
  String get protocolName; // "Matrix", "Mumble", "Jitsi"

  /// What this protocol supports (used by UI to show/hide features)
  VoiceCapabilities get capabilities;

  /// Connection lifecycle
  Future<void> connect(VoiceServerConfig config);
  Future<void> disconnect();
  Stream<VoiceConnectionState> get connectionState;

  /// Channel/room management
  VoiceChannelManager get channels;

  /// Participants in the current channel
  Stream<List<VoiceParticipant>> get participants;

  /// Local audio/video control
  VoiceLocalMedia get localMedia;

  /// Permissions for the current user in the current channel
  Stream<VoicePermissions> get permissions;

  /// Text chat (if supported by protocol)
  Future<void> sendTextMessage(String text);
  Stream<VoiceTextMessage> get textMessages;

  /// Dispose all resources
  Future<void> dispose();
}
```

#### VoiceCapabilities

Protocols differ in what they support. The UI checks these flags to show/hide features rather than checking which protocol is active.

```dart
class VoiceCapabilities {
  /// Core
  final bool supportsVideo;
  final bool supportsScreenShare;
  final bool supportsPersistentChannels; // always-on voice rooms
  final bool supportsRinging;            // DM-style ring-to-call

  /// Channel model
  final bool supportsChannelHierarchy;   // Mumble/TS tree structure
  final bool supportsChannelLinks;       // Mumble-specific
  final bool supportsTemporaryChannels;

  /// Audio
  final bool supportsPositionalAudio;    // Mumble/TS
  final bool supportsPerUserVolume;
  final bool supportsPushToTalk;

  /// Moderation
  final bool supportsServerMute;
  final bool supportsServerDeafen;
  final bool supportsMoveUsers;
  final bool supportsKick;
  final bool supportsBan;

  /// Other
  final bool supportsEncryption;
  final bool supportsFederation;         // Matrix only
  final bool supportsTextInVoice;
  final int maxParticipants;             // 0 = unlimited
}
```

#### VoiceChannel

A normalized channel model that works for flat (Matrix/Jitsi) and hierarchical (Mumble/TS) structures.

```dart
class VoiceChannel {
  final String id;
  final String name;
  final String? description;
  final String? parentId;           // null = top-level
  final List<String> childIds;      // empty for leaf channels
  final int? maxParticipants;       // null = unlimited
  final int currentParticipantCount;
  final bool isTemporary;
  final bool isLinked;              // Mumble channel linking
  final VoiceChannelType type;      // voice, stage, category_spacer
  final Map<String, dynamic> protocolMetadata; // protocol-specific extras
}
```

#### VoiceParticipant

Unified participant model across all protocols.

```dart
class VoiceParticipant {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final bool isSelf;

  // Audio state
  final bool isMuted;
  final bool isDeafened;
  final bool isServerMuted;
  final bool isServerDeafened;
  final bool isSpeaking;
  final double audioLevel;          // 0.0 - 1.0, for speaking ring animation

  // Video state (if protocol supports it)
  final bool hasVideo;
  final bool isScreenSharing;

  // Connection
  final VoiceConnectionQuality connectionQuality; // good, fair, poor

  // Protocol-specific
  final Map<String, dynamic> protocolMetadata;
}
```

#### VoicePermissions

Normalized to a flat capability set. Hides ACLs, power levels, numeric powers.

```dart
class VoicePermissions {
  final bool canSpeak;
  final bool canVideo;
  final bool canScreenShare;
  final bool canMuteOthers;
  final bool canDeafenOthers;
  final bool canMoveOthers;
  final bool canKick;
  final bool canBan;
  final bool canCreateChannels;
  final bool canModifyChannel;
  final bool canDisconnectOthers;
}
```

---

## How the PRD Maps to This Architecture

### What Stays Protocol-Agnostic (shared UI + state)

| PRD Feature | Abstraction Used |
|------------|-----------------|
| Voice channel appearance in sidebar | `VoiceChannel` + `participants` stream |
| Participant grid (avatars, speaking rings, mute icons) | `List<VoiceParticipant>` stream |
| Persistent voice bar | `VoiceConnectionState` + `VoiceChannel` + `participants` |
| Mute/deafen/disconnect controls | `VoiceLocalMedia.setMuted()` / `setDeafened()` / `adapter.disconnect()` |
| Per-user volume | `VoiceLocalMedia.setUserVolume(userId, level)` |
| Voice settings (device selection, processing) | `VoiceLocalMedia` (devices, volume, input mode) |
| Connection quality indicator | `VoiceConnectionState.quality` |
| Text-in-voice | `sendTextMessage()` / `textMessages` stream |
| Permission-gated UI (show/hide moderation actions) | `VoicePermissions` stream |

### What Is Protocol-Specific (inside adapters)

| PRD Feature | Why It's Protocol-Specific |
|------------|--------------------------|
| MatrixRTC signaling (`m.rtc.member` events) | Matrix-only event system |
| LiveKit SFU connection + JWT auth | MatrixRTC's SFU choice |
| MSC4075 call notifications (ringing) | Matrix-only notification mechanism |
| CallKit / Android ConnectionService triggers | Triggered by adapter, but ring UI is shared |
| Voice channel room identification (`im.gloam.voice_channel`) | Matrix room metadata |
| E2EE key distribution | Protocol-specific encryption model |
| Mumble certificate auth | Mumble-specific |
| Mumble channel tree + ACLs | Mumble protocol |
| Mumble positional audio | Mumble-specific capability |

### What Needs Careful Design (shared but protocol-aware)

| Feature | Risk if Not Abstracted | Recommendation |
|---------|----------------------|----------------|
| **DM calls vs voice channels** | The PRD defines these as separate flows. Mumble has no concept of "DM calls" — it only has channels. | Define `CallMode` enum: `ambient` (voice channel, no ring) and `ringing` (DM call, ring-to-answer). The adapter reports which modes it supports via `VoiceCapabilities`. UI switches behavior based on mode, not protocol. |
| **Channel creation** | Matrix creates rooms; Mumble sends `ChannelState` to server. | `VoiceChannelManager.createChannel()` returns a `Future<VoiceChannel>` — implementation differs per adapter but the interface is the same. |
| **Server discovery / connection** | Matrix uses homeserver + `.well-known`; Mumble uses direct address + cert. | The "Add Voice Server" UI is protocol-specific (a form that asks for the right credentials). But the saved server list and connection management are shared. Define `VoiceServerConfig` as a sealed class with protocol-specific subtypes. |
| **Screen sharing** | MatrixRTC routes through LiveKit; Mumble doesn't support screen share at all. | Gate on `capabilities.supportsScreenShare`. The screen share button simply doesn't appear for Mumble. |
| **Video** | Same pattern — Mumble is audio-only. | Gate on `capabilities.supportsVideo`. Participant tiles show avatar-only for audio-only protocols. |

---

## Concrete Changes to the PRD

These are specific things to build differently in Phase 1 to avoid rework later.

### 1. VoiceService Must Not Import LiveKit or matrix SDK

The global `VoiceService` Riverpod provider (the one that owns connection state, current channel, participants, and mute/deafen state) should depend only on `VoiceProtocolAdapter` — never on `livekit_client` or `matrix` SDK directly.

```dart
// GOOD: Protocol-agnostic
@riverpod
class VoiceService extends _$VoiceService {
  late VoiceProtocolAdapter _adapter;

  void connectToChannel(VoiceProtocolAdapter adapter, String channelId) { ... }
  void disconnect() => _adapter.disconnect();
  void toggleMute() => _adapter.localMedia.setMuted(!_adapter.localMedia.isMuted);
}

// BAD: Protocol-coupled
@riverpod
class VoiceService extends _$VoiceService {
  late Room _livekitRoom;             // direct LiveKit dependency
  late MatrixRTCService _matrixRTC;   // direct Matrix dependency
}
```

### 2. Voice Channel Detection Must Be Pluggable

The PRD proposes `im.gloam.voice_channel` as a room tag to identify voice channels in Matrix. This is correct for Matrix. But the room list needs a protocol-agnostic way to ask "is this a voice channel?"

```dart
// In the room list provider, don't check for Matrix-specific tags.
// Instead, ask the adapter:
bool isVoiceChannel(String roomId) {
  return voiceService.adapter?.channels.isVoiceChannel(roomId) ?? false;
}
```

For MatrixRTC, `isVoiceChannel` checks the room's `im.gloam.voice_channel` tag. For Mumble, every channel is implicitly a voice channel (Mumble is voice-first).

### 3. Participant State Must Flow Through a Single Stream

The participant grid, sidebar participant avatars, and persistent voice bar all consume the same `Stream<List<VoiceParticipant>>`. Do not have the UI subscribe to LiveKit's `Room.participants` directly — always go through the adapter's normalized stream.

### 4. Audio Device Management Should Be Shared

Input/output device enumeration, volume control, noise suppression, echo cancellation — these are not protocol-specific. They operate on the local audio pipeline regardless of where audio is being sent. Extract these into a shared `AudioDeviceService` that all adapters use rather than each adapter reimplementing device management.

```
AudioDeviceService (shared)
├── enumerateInputDevices()
├── enumerateOutputDevices()
├── setInputDevice(deviceId)
├── setOutputDevice(deviceId)
├── setInputVolume(double)
├── setOutputVolume(double)
├── enableNoiseSuppression(bool)
├── enableEchoCancellation(bool)
└── enableAutoGainControl(bool)
```

LiveKit, dumble, and Jitsi all receive the processed audio track from this shared service.

### 5. The Persistent Voice Bar Is Protocol-Agnostic by Default

The voice bar only needs:
- Channel name (from `VoiceChannel.name`)
- Server/space name (from `VoiceServerConfig.displayName`)
- Participant names (from `List<VoiceParticipant>`)
- Connection duration (tracked by `VoiceService`, not the adapter)
- Connection quality (from `VoiceConnectionState.quality`)
- Mute/deafen state (from `VoiceLocalMedia`)

None of these are protocol-specific. The bar works for Matrix, Mumble, or anything else without changes.

### 6. Saved Servers List

Users will eventually have multiple voice connections across protocols:
- Their Matrix homeserver (with MatrixRTC voice channels)
- A Mumble server for their gaming guild
- A Jitsi instance for work meetings

The "saved servers" model:

```dart
sealed class VoiceServerConfig {
  final String id;
  final String displayName;
  final String protocolId;
}

class MatrixVoiceServerConfig extends VoiceServerConfig {
  final String homeserverUrl;
  // No additional config needed — uses existing Matrix session
}

class MumbleServerConfig extends VoiceServerConfig {
  final String host;
  final int port;
  final String? username;
  final String? password;
  final Uint8List? certificate;   // X.509 client cert
  final List<String> accessTokens;
}

class JitsiServerConfig extends VoiceServerConfig {
  final String serverUrl;
}
```

This should live in settings/storage from day one, even if v1 only has one entry (the Matrix homeserver).

---

## What to Build Now (Phase 1) vs Later

### Phase 1 (MatrixRTC — build now)

- Define `VoiceProtocolAdapter` and all abstract interfaces
- Implement `MatrixRTCAdapter` as the first (and only) concrete adapter
- Build `VoiceService` against the abstract interface
- Build all voice UI against `VoiceParticipant`, `VoiceChannel`, `VoicePermissions`
- Build `AudioDeviceService` as a shared, protocol-independent module
- Store voice server configs using the sealed class model (even with only Matrix)

### Phase 2 (Mumble — build when ready)

- Implement `MumbleAdapter` using `dumble` + `opus_dart`
- Add Mumble server configuration UI (host, port, certificate management)
- Handle channel hierarchy rendering (tree view in sidebar — the flat list used for Matrix channels gets a tree option)
- Test: joining a Mumble server should show channels in the sidebar, participants in the grid, and the voice bar at the bottom — all using the same UI components

### Phase 3 (Jitsi — easy add)

- Implement `JitsiAdapter` wrapping `jitsi_meet_flutter_sdk`
- This adapter has limited capabilities: no persistent channels, no hierarchy, no moderation
- UI gracefully degrades: no voice channel sidebar items, just "Join Meeting" actions

---

## Risks This Architecture Mitigates

| Risk | Without Abstraction | With Abstraction |
|------|-------------------|-----------------|
| Adding Mumble requires rewriting voice UI | Yes — UI is wired to LiveKit types | No — UI consumes `VoiceParticipant` regardless of source |
| Mumble's channel tree doesn't fit Matrix's flat model | Requires separate UI codepath | `VoiceChannel.parentId` + `childIds` support both; UI renders tree or flat based on data |
| Different auth models cause credential management chaos | Protocol-specific credential handling scattered across the app | `VoiceServerConfig` sealed class with protocol subtypes; single "Servers" settings page |
| Per-user volume breaks for Mumble | Implementation coupled to LiveKit track gain API | `VoiceLocalMedia.setUserVolume(userId, level)` abstracted; adapter implements via LiveKit gain or Mumble volume adjustment |
| Testing voice UI is hard | Must have LiveKit running | Can create a `MockAdapter` that emits fake participants — UI tests work without any server |

---

## What This Architecture Does NOT Cover

- **Simultaneous multi-protocol connections**: v1 supports one active voice connection at a time. A user is either in a Matrix voice channel OR a Mumble channel, not both. Multi-connection is a future extension.
- **Cross-protocol bridging**: Bridging audio between a Matrix channel and a Mumble channel is a server-side concern (bot/bridge), not a client architecture concern.
- **Protocol-specific UI**: Some features (Mumble certificate management, Mumble channel linking, Mumble positional audio configuration) will need protocol-specific settings screens. These live under a "Server Settings" area gated on `protocolId`, not in the shared voice UI.

---

## Summary

Build the MatrixRTC implementation as the first `VoiceProtocolAdapter`. Wire all UI and state management to the abstract interfaces. When Mumble time comes, implement `MumbleAdapter`, plug it in, and the voice channel view, participant grid, persistent bar, and voice settings all work without modification.

The cost of this abstraction in Phase 1 is small — a few extra interfaces and one level of indirection. The cost of NOT doing it is rewriting the voice UI for every new protocol.

---

## Change History

- 2026-03-26: Initial architecture document. Defines protocol-agnostic voice abstraction layer, maps PRD features to shared vs protocol-specific, identifies 6 concrete changes to Phase 1 implementation.
