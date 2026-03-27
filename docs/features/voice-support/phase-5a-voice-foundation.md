# Phase 5A: Voice Abstraction Layer + MatrixRTC Foundation

**Weeks 1–3 | Milestone: Join a voice channel on a Matrix server and hear other participants talk**

*Last updated: 2026-03-26*

---

## Objectives

1. Define the protocol-agnostic voice abstraction layer (interfaces, entities, capabilities) so all future voice UI is built against stable contracts — never against LiveKit or matrix SDK types directly.
2. Implement the MatrixRTC signaling layer on top of the Dart `matrix` SDK, handling `m.rtc.member` state events, SFU discovery, and LiveKit JWT acquisition.
3. Integrate the LiveKit Flutter SDK for media transport — connect to a LiveKit SFU, publish/subscribe to audio tracks, and receive real-time audio level data.
4. Build a shared `AudioDeviceService` for input/output device enumeration, selection, and volume control that is protocol-independent.
5. Create the global `VoiceService` Riverpod provider that manages connection state, current channel, participants, and local media — the single source of truth for all voice UI.
6. Handle platform permissions (camera, microphone) with graceful degradation.

## Success Criteria

- [ ] `VoiceProtocolAdapter`, `VoiceChannel`, `VoiceParticipant`, `VoicePermissions`, `VoiceCapabilities` interfaces defined and importable
- [ ] `MatrixRTCAdapter` connects to a Matrix homeserver's LiveKit SFU via `.well-known` discovery
- [ ] Sending `m.rtc.member` state event into a room signals participation to other clients
- [ ] Receiving other users' `m.rtc.member` events produces a `Stream<List<VoiceParticipant>>`
- [ ] Audio from the local microphone reaches the LiveKit SFU and is received by other participants
- [ ] Remote participants' audio plays through the local speaker
- [ ] `AudioDeviceService` enumerates input and output devices on macOS and iOS
- [ ] Mute/unmute toggles the local audio track (other participants stop hearing you)
- [ ] Deafen toggles reception of all remote audio tracks
- [ ] `VoiceService` exposes connection state as a Riverpod provider watchable from any widget
- [ ] Automatic reconnection on brief network interruptions (LiveKit handles this natively)
- [ ] Graceful error when homeserver lacks `.well-known` `rtc_foci` configuration
- [ ] Microphone permission requested with rationale on first voice channel join
- [ ] Unit tests for `MatrixRTCSignaling` (event parsing, membership tracking)

---

## Task Breakdown

### Task 1: Domain Layer — Voice Abstraction Interfaces

**3 days | Complexity: Medium**

Define all abstract interfaces and entity classes that the UI and state management will depend on. These are pure Dart — no Flutter, no SDK imports, no platform dependencies.

#### 1.1 `lib/features/calls/domain/voice_protocol_adapter.dart`

The top-level adapter interface. Every protocol (MatrixRTC, Mumble, Jitsi) implements this.

```dart
abstract class VoiceProtocolAdapter {
  String get protocolId;
  String get protocolName;
  VoiceCapabilities get capabilities;

  Stream<VoiceConnectionState> get connectionState;
  Future<void> connect(VoiceServerConfig config);
  Future<void> disconnect();

  VoiceChannelManager get channels;
  Stream<List<VoiceParticipant>> get participants;
  VoiceLocalMedia get localMedia;
  Stream<VoicePermissions> get permissions;

  Future<void> sendTextMessage(String text);
  Stream<VoiceTextMessage> get textMessages;

  Future<void> dispose();
}

abstract class VoiceChannelManager {
  Stream<List<VoiceChannel>> get channels;
  Stream<VoiceChannel?> get currentChannel;
  Future<void> joinChannel(String channelId);
  Future<void> leaveChannel();
  bool isVoiceChannel(String roomId);
}

abstract class VoiceLocalMedia {
  Stream<bool> get isMuted;
  Stream<bool> get isDeafened;
  Stream<bool> get hasVideo;
  Stream<bool> get isScreenSharing;
  Stream<double> get localAudioLevel;

  Future<void> setMuted(bool muted);
  Future<void> setDeafened(bool deafened);
  Future<void> setVideo(bool enabled);
  Future<void> setScreenShare(bool enabled);
  Future<void> setUserVolume(String participantId, double volume);
  Future<void> setInputDevice(String deviceId);
  Future<void> setOutputDevice(String deviceId);
}
```

#### 1.2 `lib/features/calls/domain/voice_channel.dart`

```dart
@freezed
class VoiceChannel with _$VoiceChannel {
  const factory VoiceChannel({
    required String id,
    required String name,
    String? description,
    String? parentId,
    @Default([]) List<String> childIds,
    int? maxParticipants,
    @Default(0) int currentParticipantCount,
    @Default(false) bool isTemporary,
    @Default(VoiceChannelType.voice) VoiceChannelType type,
    @Default({}) Map<String, dynamic> protocolMetadata,
  }) = _VoiceChannel;
}

enum VoiceChannelType { voice, stage, categorySpacer }
```

#### 1.3 `lib/features/calls/domain/voice_participant.dart`

```dart
@freezed
class VoiceParticipant with _$VoiceParticipant {
  const factory VoiceParticipant({
    required String id,
    required String displayName,
    Uri? avatarUrl,
    @Default(false) bool isSelf,
    @Default(false) bool isMuted,
    @Default(false) bool isDeafened,
    @Default(false) bool isServerMuted,
    @Default(false) bool isServerDeafened,
    @Default(false) bool isSpeaking,
    @Default(0.0) double audioLevel,
    @Default(false) bool hasVideo,
    @Default(false) bool isScreenSharing,
    @Default(VoiceConnectionQuality.good) VoiceConnectionQuality connectionQuality,
    @Default({}) Map<String, dynamic> protocolMetadata,
  }) = _VoiceParticipant;
}

enum VoiceConnectionQuality { good, fair, poor, unknown }
```

#### 1.4 Remaining domain files

- `voice_permissions.dart` — `VoicePermissions` freezed class with bool capability flags
- `voice_capabilities.dart` — `VoiceCapabilities` class with feature support flags
- `voice_server_config.dart` — Sealed class with `MatrixVoiceServerConfig` subtype
- `voice_connection_state.dart` — Enum: `disconnected`, `connecting`, `connected`, `reconnecting`, `error`

**Output:** All domain types defined with freezed code generation. No implementation logic — just contracts.

---

### Task 2: MatrixRTC Signaling Layer

**5 days | Complexity: High**

This is the hardest piece. The Dart `matrix` SDK (v0.40.2) does not have built-in MatrixRTC support. We must implement signaling on top of the raw event APIs, following Element X's event schemas.

#### 2.1 `lib/features/calls/data/matrix_rtc_signaling.dart`

Handles sending and receiving MatrixRTC state events.

**Key responsibilities:**
- Send `m.rtc.member` (or `org.matrix.msc3401.call.member`) state events when joining/leaving
- Listen for other users' membership events via room state sync
- Parse membership event content: `slot_id`, `member.id`, `member.claimed_device_id`, `rtc_transports`
- Track active participants by maintaining a map of user_id -> membership event
- Handle stale memberships (events from crashed clients that didn't clean up)
- Send delayed leave events (MSC4140) if homeserver supports it

**Event schema (following Element X):**

```dart
/// State event sent when joining a voice channel
/// type: "org.matrix.msc3401.call.member"
/// state_key: user_id
Map<String, dynamic> buildMembershipEvent({
  required String callId,
  required String deviceId,
  required String userId,
  required String livekitServiceUrl,
}) => {
  'memberships': [{
    'call_id': callId,
    'scope': 'm.room',
    'application': 'm.call',
    'device_id': deviceId,
    'expires': 3600000, // 1 hour in ms
    'foci_active': [{
      'type': 'livekit',
      'livekit_service_url': livekitServiceUrl,
    }],
    'membershipID': _generateMembershipId(),
  }],
};
```

**State tracking:**

```dart
class MatrixRTCSignaling {
  final Client _client;
  final Room _room;

  /// Active participants derived from room state events
  final _participants = BehaviorSubject<List<CallMembership>>.seeded([]);
  Stream<List<CallMembership>> get participants => _participants.stream;

  /// Start listening to room state for membership events
  void startListening() {
    // Subscribe to room.onUpdate for state event changes
    // Filter for org.matrix.msc3401.call.member events
    // Parse and update _participants
  }

  /// Join: send our membership event
  Future<void> join({required String callId, required String livekitServiceUrl}) async {
    await _room.client.setRoomStateWithKey(
      _room.id,
      'org.matrix.msc3401.call.member',
      _client.userID!,
      buildMembershipEvent(...),
    );
  }

  /// Leave: clear our membership event
  Future<void> leave() async {
    await _room.client.setRoomStateWithKey(
      _room.id,
      'org.matrix.msc3401.call.member',
      _client.userID!,
      {'memberships': []},
    );
  }
}
```

**Key decisions:**
- Use `org.matrix.msc3401.call.member` event type (the unstable prefix Element X uses in production)
- State key is the user's Matrix ID
- Membership expiry handled client-side (refresh before expiry) and server-side (MSC4140 delayed events when available)

#### 2.2 `lib/features/calls/data/sfu_discovery_service.dart`

Discovers the LiveKit SFU endpoint and obtains a JWT for connection.

**Flow:**
1. Fetch homeserver's `.well-known/matrix/client`
2. Extract `org.matrix.msc4143.rtc_foci[0].livekit_service_url`
3. Request an OpenID token from the homeserver (`client.requestOpenIdToken()`)
4. POST the OpenID token to the `livekit_service_url`
5. Receive back a LiveKit JWT and SFU WebSocket URL

```dart
class SfuDiscoveryService {
  final Client _client;
  final Dio _dio;

  Future<SfuCredentials> discover(String homeserverUrl) async {
    // 1. Fetch .well-known
    final wellKnown = await _dio.get('$homeserverUrl/.well-known/matrix/client');
    final foci = wellKnown.data['org.matrix.msc4143.rtc_foci'];
    if (foci == null || foci.isEmpty) {
      throw VoiceConfigError('Homeserver does not support MatrixRTC voice. '
        'Missing org.matrix.msc4143.rtc_foci in .well-known');
    }
    final livekitServiceUrl = foci[0]['livekit_service_url'];

    // 2. Get OpenID token
    final openIdToken = await _client.requestOpenIdToken(_client.userID!);

    // 3. Exchange for LiveKit JWT
    final jwtResponse = await _dio.post(livekitServiceUrl, data: {
      'openid_token': openIdToken.toJson(),
      'room_id': roomId,
      'device_id': _client.deviceID,
    });

    return SfuCredentials(
      jwt: jwtResponse.data['jwt'],
      sfuUrl: jwtResponse.data['url'],
    );
  }
}
```

**Error handling:**
- Missing `.well-known` config: show user-facing error "Voice channels require server configuration"
- JWT exchange failure: retry once, then show error
- Cache SFU URL (it won't change per homeserver)

---

### Task 3: LiveKit Media Integration

**4 days | Complexity: Medium**

Wrap the `livekit_client` SDK to manage the media connection, audio tracks, and participant state.

#### 3.1 `lib/features/calls/data/livekit_media_manager.dart`

```dart
class LivekitMediaManager {
  Room? _room;
  LocalParticipant? _localParticipant;

  final _participants = BehaviorSubject<List<VoiceParticipant>>.seeded([]);
  Stream<List<VoiceParticipant>> get participants => _participants.stream;

  /// Connect to LiveKit SFU with JWT
  Future<void> connect(SfuCredentials credentials) async {
    _room = Room();

    // Configure audio defaults
    _room!.roomOptions = RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      defaultAudioPublishOptions: AudioPublishOptions(
        audioBitrate: AudioPreset.musicStereo.maxBitrate,
        dtx: true, // Discontinuous transmission for silence
      ),
    );

    await _room!.connect(credentials.sfuUrl, credentials.jwt);
    _localParticipant = _room!.localParticipant;

    // Publish local audio track
    await _localParticipant!.setMicrophoneEnabled(true);

    // Listen for participant changes
    _room!.addListener(_onRoomEvent);
    _updateParticipants();
  }

  /// Map LiveKit participants to VoiceParticipant entities
  void _updateParticipants() {
    final all = <VoiceParticipant>[];

    // Local participant
    if (_localParticipant != null) {
      all.add(_mapLocalParticipant(_localParticipant!));
    }

    // Remote participants
    for (final remote in _room!.remoteParticipants.values) {
      all.add(_mapRemoteParticipant(remote));
    }

    _participants.add(all);
  }

  VoiceParticipant _mapRemoteParticipant(RemoteParticipant p) {
    return VoiceParticipant(
      id: p.identity,
      displayName: p.name.isNotEmpty ? p.name : p.identity,
      isSelf: false,
      isMuted: !p.isMicrophoneEnabled(),
      isSpeaking: p.isSpeaking,
      audioLevel: p.audioLevel,
      hasVideo: p.isCameraEnabled(),
      isScreenSharing: p.isScreenShareEnabled(),
      connectionQuality: _mapQuality(p.connectionQuality),
    );
  }

  /// Mute/unmute local mic
  Future<void> setMuted(bool muted) async {
    await _localParticipant?.setMicrophoneEnabled(!muted);
    _updateParticipants();
  }

  /// Deafen: mute all remote audio tracks locally
  Future<void> setDeafened(bool deafened) async {
    for (final remote in _room!.remoteParticipants.values) {
      for (final pub in remote.audioTrackPublications) {
        if (deafened) {
          pub.track?.disable();
        } else {
          pub.track?.enable();
        }
      }
    }
  }

  /// Per-user volume (adjust track gain)
  Future<void> setUserVolume(String participantId, double volume) async {
    final remote = _room!.remoteParticipants[participantId];
    if (remote == null) return;
    for (final pub in remote.audioTrackPublications) {
      // LiveKit allows setting subscriber volume
      // volume: 0.0 to 2.0 (1.0 = normal)
    }
  }

  Future<void> disconnect() async {
    await _room?.disconnect();
    _room?.removeListener(_onRoomEvent);
    _room = null;
  }
}
```

**LiveKit event handling:**
- `ParticipantConnected` / `ParticipantDisconnected` — update participant list
- `TrackSubscribed` / `TrackUnsubscribed` — audio/video track availability
- `ActiveSpeakersChanged` — speaking state updates
- `ConnectionQualityChanged` — quality indicator per participant
- `Reconnecting` / `Reconnected` — automatic reconnection flow

---

### Task 4: MatrixRTC Adapter (Glue Layer)

**3 days | Complexity: Medium**

Combines Tasks 2 and 3 into a concrete `VoiceProtocolAdapter` implementation.

#### 4.1 `lib/features/calls/data/adapters/matrix_rtc_adapter.dart`

```dart
class MatrixRTCAdapter implements VoiceProtocolAdapter {
  final Client _client;
  final SfuDiscoveryService _sfuDiscovery;
  late final MatrixRTCSignaling _signaling;
  late final LivekitMediaManager _media;

  @override
  String get protocolId => 'matrixrtc';

  @override
  String get protocolName => 'Matrix';

  @override
  VoiceCapabilities get capabilities => VoiceCapabilities(
    supportsVideo: true,
    supportsScreenShare: true,
    supportsPersistentChannels: true,
    supportsRinging: true,
    supportsChannelHierarchy: false,    // Matrix rooms are flat
    supportsChannelLinks: false,
    supportsTemporaryChannels: false,
    supportsPositionalAudio: false,
    supportsPerUserVolume: true,
    supportsPushToTalk: true,
    supportsServerMute: true,
    supportsServerDeafen: true,
    supportsMoveUsers: false,
    supportsKick: true,
    supportsBan: true,
    supportsEncryption: true,
    supportsFederation: true,
    supportsTextInVoice: true,
    maxParticipants: 500,
  );

  @override
  Future<void> connect(VoiceServerConfig config) async {
    // SFU discovery + LiveKit connection handled per-channel in joinChannel
  }

  @override
  VoiceChannelManager get channels => _MatrixChannelManager(_client);

  @override
  Stream<List<VoiceParticipant>> get participants =>
    _media.participants.map((lkParticipants) {
      // Merge LiveKit participant data with Matrix user info (avatars, display names)
      return lkParticipants.map((p) => _enrichWithMatrixProfile(p)).toList();
    });

  // ... remaining adapter methods bridging signaling + media
}
```

**The key insight:** MatrixRTC has two parallel data flows that must be merged:
1. **Signaling** (Matrix events) — who is "in the call" according to room state
2. **Media** (LiveKit) — who is actually connected to the SFU with audio

These can diverge (e.g., a crashed client has a stale membership event but no LiveKit session). The adapter merges both views into a single participant list, preferring the LiveKit view for audio state and the Matrix view for identity.

---

### Task 5: Audio Device Service

**2 days | Complexity: Low**

Protocol-independent audio device management. Wraps `flutter_webrtc` device APIs.

#### 5.1 `lib/services/audio_device_service.dart`

```dart
@riverpod
class AudioDeviceService extends _$AudioDeviceService {
  @override
  AudioDeviceState build() => AudioDeviceState.initial();

  Future<List<MediaDevice>> getInputDevices() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    return devices.where((d) => d.kind == 'audioinput').toList();
  }

  Future<List<MediaDevice>> getOutputDevices() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    return devices.where((d) => d.kind == 'audiooutput').toList();
  }

  Future<void> setInputDevice(String deviceId) async {
    // Store preference, apply to active media tracks
    state = state.copyWith(selectedInputId: deviceId);
  }

  Future<void> setOutputDevice(String deviceId) async {
    state = state.copyWith(selectedOutputId: deviceId);
  }

  Future<void> setInputVolume(double volume) async {
    state = state.copyWith(inputVolume: volume.clamp(0.0, 1.0));
  }

  Future<void> setOutputVolume(double volume) async {
    state = state.copyWith(outputVolume: volume.clamp(0.0, 1.0));
  }
}

@freezed
class AudioDeviceState with _$AudioDeviceState {
  const factory AudioDeviceState({
    String? selectedInputId,
    String? selectedOutputId,
    @Default(0.8) double inputVolume,
    @Default(0.9) double outputVolume,
    @Default(true) bool echoCancellation,
    @Default(true) bool noiseSuppression,
    @Default(true) bool autoGainControl,
  }) = _AudioDeviceState;

  factory AudioDeviceState.initial() => const AudioDeviceState();
}
```

**Persistence:** Save selected devices and volume settings to `SharedPreferences` so they persist across sessions.

---

### Task 6: Global Voice Service (Riverpod Provider)

**3 days | Complexity: Medium**

The single source of truth for voice state across the entire app. Every voice-related widget watches this provider.

#### 6.1 `lib/services/voice_service.dart`

```dart
@Riverpod(keepAlive: true)
class VoiceService extends _$VoiceService {
  VoiceProtocolAdapter? _adapter;
  StreamSubscription? _connectionSub;
  StreamSubscription? _participantSub;

  @override
  VoiceState build() => const VoiceState.disconnected();

  /// Join a voice channel
  Future<void> joinChannel({
    required VoiceProtocolAdapter adapter,
    required String channelId,
  }) async {
    // If already connected to a different channel, disconnect first
    if (_adapter != null) {
      await _adapter!.disconnect();
    }

    _adapter = adapter;
    state = VoiceState.connecting(channelId: channelId);

    try {
      await adapter.channels.joinChannel(channelId);

      _connectionSub = adapter.connectionState.listen((connState) {
        // Update state based on connection changes
      });

      _participantSub = adapter.participants.listen((participants) {
        state = state.maybeMap(
          connected: (s) => s.copyWith(participants: participants),
          orElse: () => state,
        );
      });

      // Get channel info
      final channel = await adapter.channels.currentChannel.first;
      state = VoiceState.connected(
        channelId: channelId,
        channelName: channel?.name ?? '',
        protocolName: adapter.protocolName,
        participants: [],
        connectedAt: DateTime.now(),
      );
    } catch (e) {
      state = VoiceState.error(message: e.toString());
    }
  }

  /// Disconnect from current channel
  Future<void> disconnect() async {
    await _connectionSub?.cancel();
    await _participantSub?.cancel();
    await _adapter?.channels.leaveChannel();
    await _adapter?.disconnect();
    _adapter = null;
    state = const VoiceState.disconnected();
  }

  // Convenience accessors for UI
  bool get isConnected => state is VoiceStateConnected;
  VoiceProtocolAdapter? get adapter => _adapter;
  VoiceLocalMedia? get localMedia => _adapter?.localMedia;
}

@freezed
class VoiceState with _$VoiceState {
  const factory VoiceState.disconnected() = VoiceStateDisconnected;
  const factory VoiceState.connecting({required String channelId}) = VoiceStateConnecting;
  const factory VoiceState.connected({
    required String channelId,
    required String channelName,
    required String protocolName,
    required List<VoiceParticipant> participants,
    required DateTime connectedAt,
  }) = VoiceStateConnected;
  const factory VoiceState.reconnecting({required String channelId}) = VoiceStateReconnecting;
  const factory VoiceState.error({required String message}) = VoiceStateError;
}
```

**Critical pattern:** `keepAlive: true` ensures this provider survives navigation. The voice connection must persist when the user navigates away from the voice channel screen — this is the foundation for the persistent voice bar.

---

### Task 7: Platform Permissions

**1 day | Complexity: Low**

#### 7.1 Permission requests

```dart
Future<bool> requestMicrophonePermission() async {
  final status = await Permission.microphone.request();
  if (status.isPermanentlyDenied) {
    // Show dialog directing user to system settings
    openAppSettings();
    return false;
  }
  return status.isGranted;
}
```

#### 7.2 Platform configuration

**iOS** (`Info.plist`):
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Gloam needs microphone access for voice channels and calls</string>
<key>NSCameraUsageDescription</key>
<string>Gloam needs camera access for video calls</string>
```

**macOS** (`DebugProfile.entitlements` + `Release.entitlements`):
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
```

**Android** (`AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

---

## Dependencies & Blockers

| Dependency | Required By | Status | Risk |
|-----------|------------|--------|------|
| LiveKit SFU + lk-jwt-service deployed | Task 3 | Must be set up for testing | Medium — document self-hosting requirements |
| Homeserver `.well-known` with `rtc_foci` | Task 2 | Must be configured | Low — well-documented |
| `livekit_client` Flutter SDK | Task 3 | Stable, published on pub.dev | Low |
| `flutter_webrtc` | Task 3, 5 | Stable on mobile, maturing on desktop | Medium — test macOS early |
| Homeserver MSC4140 (delayed events) | Task 2 | Optional — improves reliability | Low — graceful fallback |
| `org.matrix.msc3401.call.member` schema stability | Task 2 | Used in production by Element X | Low — follow their schema |

## Key Technical Decisions

| Decision | Options | Recommendation | Rationale |
|----------|---------|---------------|-----------|
| Event type prefix | `m.call.member` (spec) vs `org.matrix.msc3401.call.member` (unstable) | **Unstable prefix** | Element X uses the unstable prefix in production. When the MSC merges, add support for both. |
| Participant identity | LiveKit identity = Matrix user ID vs custom mapping | **Matrix user ID as LiveKit identity** | Simplest. The JWT service maps Matrix identity to LiveKit automatically. |
| Audio codec config | Default Opus vs custom bitrate | **Default Opus with DTX enabled** | DTX (discontinuous transmission) reduces idle bandwidth. Default Opus quality is good. |
| Adapter instantiation | Singleton vs per-channel | **Singleton per protocol, joins/leaves channels** | Matches MatrixRTC model where one client session manages multiple room calls. |

## What "Done" Looks Like

1. Open Gloam on two devices, both signed into the same Matrix homeserver
2. On device A, navigate to a room tagged as a voice channel
3. Call `voiceService.joinChannel(adapter: matrixAdapter, channelId: roomId)`
4. Device A's microphone audio is captured and sent to the LiveKit SFU
5. On device B, join the same room's voice channel
6. Device B hears device A's audio; device A hears device B's audio
7. Device A mutes — device B stops hearing device A
8. Device A disconnects — device B sees the participant list shrink
9. Kill device A without disconnecting — the stale membership event is detected and cleaned up after expiry

No UI yet — this phase is infrastructure. The voice channel screen and persistent bar come in Phase 5B.

---

## Change History

- 2026-03-26: Initial implementation plan created
