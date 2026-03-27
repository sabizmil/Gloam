# Phase 5C: DM Calls + Mobile Integration

**Weeks 7–9 | Milestone: Ring-to-answer voice and video calls from DMs, with native phone integration on iOS and Android**

*Last updated: 2026-03-26*

---

## Objectives

1. Implement ring-to-call for 1:1 DMs using MSC4075 call notifications — the recipient's device rings, they accept or decline.
2. Build outgoing call, incoming call, and active call screens for both voice-only and video modes.
3. Integrate iOS CallKit so incoming calls appear as native phone calls (lock screen, system call UI).
4. Integrate Android foreground service with full-screen notification for incoming calls.
5. Add call history as system messages in the DM timeline ("Voice call · 5:23", "Missed call").
6. Implement Picture-in-Picture (PiP) for active calls on mobile when navigating away.
7. Handle multi-device: all user's devices ring, answering one stops the others.

## Success Criteria

- [ ] Tap phone icon in DM header → outgoing call screen appears, recipient's device rings
- [ ] Incoming call: full-screen overlay on mobile, popup on desktop
- [ ] Accept call → audio flows bidirectionally within 3 seconds
- [ ] Decline call → caller sees "No Answer" after decline or 45-second timeout
- [ ] Active call screen: remote avatar/video, self-view PiP, mute/camera/speaker/end controls
- [ ] Toggle video during call: camera feed appears/disappears
- [ ] Navigate away from call screen → PiP window appears (mobile) or voice bar shows (desktop)
- [ ] Call end → system message in DM timeline: "Voice call · 5:23"
- [ ] Missed call → system message: "Missed voice call"
- [ ] iOS: incoming call appears via CallKit (lock screen, native UI)
- [ ] Android: high-priority notification with ringtone and accept/decline buttons
- [ ] Multi-device: ring all devices, answering on one stops ringing on others
- [ ] Group DM: start a call that rings all members, late join available
- [ ] Background audio: call continues when app is backgrounded

---

## Task Breakdown

### Task 1: Call Notification Signaling (MSC4075)

**3 days | Complexity: High**

Implement the call notification protocol for ringing behavior.

#### 1.1 Sending call notifications

When the user initiates a DM call:

```dart
class CallNotificationService {
  final Client _client;

  /// Ring a user for a 1:1 call
  Future<void> sendCallNotification({
    required String roomId,
    required String callId,
    required bool isVideo,
  }) async {
    // Send to-device message to the recipient
    // Event type: org.matrix.msc4075.call.notify (unstable prefix)
    final recipientId = _getOtherUserId(roomId);

    await _client.sendToDevice(
      'org.matrix.msc4075.call.notify',
      _client.generateUniqueTransactionId(),
      {
        recipientId: {
          '*': {  // All devices
            'call_id': callId,
            'room_id': roomId,
            'application': 'm.call',
            'call_type': isVideo ? 'm.video' : 'm.voice',
            'sender_display_name': _client.userDisplayName,
            'sender_avatar_url': _client.avatar?.toString(),
          },
        },
      },
    );
  }

  /// Decline a call (MSC4310)
  Future<void> sendDeclineNotification({
    required String roomId,
    required String callId,
    required String callerId,
  }) async {
    await _client.sendToDevice(
      'org.matrix.msc4310.call.decline',
      _client.generateUniqueTransactionId(),
      {
        callerId: {
          '*': {
            'call_id': callId,
            'room_id': roomId,
          },
        },
      },
    );
  }

  /// Listen for incoming call notifications
  Stream<IncomingCall> get incomingCalls {
    return _client.onToDeviceEvent
      .where((e) => e.type == 'org.matrix.msc4075.call.notify')
      .map((e) => IncomingCall.fromEvent(e));
  }
}
```

#### 1.2 `IncomingCall` model

```dart
@freezed
class IncomingCall with _$IncomingCall {
  const factory IncomingCall({
    required String callId,
    required String roomId,
    required String callerId,
    required String callerDisplayName,
    Uri? callerAvatarUrl,
    required bool isVideo,
    required DateTime receivedAt,
  }) = _IncomingCall;
}
```

#### 1.3 Call state machine

```dart
/// Managed by CallProvider (Riverpod)
enum CallPhase {
  idle,           // No active call
  ringingOutgoing, // We initiated, waiting for answer
  ringingIncoming, // Someone is calling us
  connecting,     // Call accepted, media connecting
  active,         // Media flowing
  ended,          // Call finished (will return to idle after posting system message)
}
```

---

### Task 2: Call Provider (Riverpod State)

**3 days | Complexity: Medium**

#### 2.1 `lib/features/calls/presentation/providers/call_provider.dart`

Manages the DM call lifecycle separately from voice channels. A DM call is a ringing interaction; a voice channel is an ambient join. Different state machines, same adapter underneath.

```dart
@Riverpod(keepAlive: true)
class CallService extends _$CallService {
  Timer? _ringTimeout;
  DateTime? _callStartTime;

  @override
  CallState build() => const CallState.idle();

  /// Start an outgoing call
  Future<void> startCall({
    required String roomId,
    required bool isVideo,
  }) async {
    final callId = _generateCallId();
    state = CallState.ringingOutgoing(
      callId: callId,
      roomId: roomId,
      isVideo: isVideo,
      callee: _getCalleeInfo(roomId),
    );

    // Send notification to recipient
    await ref.read(callNotificationServiceProvider).sendCallNotification(
      roomId: roomId,
      callId: callId,
      isVideo: isVideo,
    );

    // Start ring timeout (45 seconds)
    _ringTimeout = Timer(const Duration(seconds: 45), () {
      if (state is CallStateRingingOutgoing) {
        _endCall(reason: CallEndReason.noAnswer);
      }
    });

    // Join the MatrixRTC session (so media is ready when they answer)
    await ref.read(voiceServiceProvider.notifier).joinChannel(
      adapter: ref.read(matrixRTCAdapterProvider),
      channelId: roomId,
    );
  }

  /// Handle incoming call notification
  void onIncomingCall(IncomingCall call) {
    if (state is! CallStateIdle) return; // Already in a call

    state = CallState.ringingIncoming(
      callId: call.callId,
      roomId: call.roomId,
      isVideo: call.isVideo,
      caller: CallPeerInfo(
        userId: call.callerId,
        displayName: call.callerDisplayName,
        avatarUrl: call.callerAvatarUrl,
      ),
    );

    // Show incoming call UI (full-screen on mobile, popup on desktop)
    // Trigger CallKit on iOS, full-screen notification on Android
  }

  /// Accept an incoming call
  Future<void> acceptCall() async {
    final incoming = state as CallStateRingingIncoming;
    state = CallState.connecting(callId: incoming.callId, roomId: incoming.roomId);

    await ref.read(voiceServiceProvider.notifier).joinChannel(
      adapter: ref.read(matrixRTCAdapterProvider),
      channelId: incoming.roomId,
    );

    _callStartTime = DateTime.now();
    state = CallState.active(
      callId: incoming.callId,
      roomId: incoming.roomId,
      isVideo: incoming.isVideo,
      peer: incoming.caller,
      startedAt: _callStartTime!,
    );
  }

  /// Decline an incoming call
  Future<void> declineCall() async {
    final incoming = state as CallStateRingingIncoming;
    await ref.read(callNotificationServiceProvider).sendDeclineNotification(
      roomId: incoming.roomId,
      callId: incoming.callId,
      callerId: incoming.caller.userId,
    );
    state = const CallState.idle();
  }

  /// End the active call
  Future<void> endCall() async {
    _ringTimeout?.cancel();
    final activeState = state;

    await ref.read(voiceServiceProvider.notifier).disconnect();

    // Post system message to DM timeline
    if (activeState is CallStateActive) {
      final duration = DateTime.now().difference(activeState.startedAt);
      await _postCallSystemMessage(activeState.roomId, duration);
    } else if (activeState is CallStateRingingOutgoing) {
      await _postMissedCallMessage(activeState.roomId);
    }

    state = const CallState.idle();
  }

  Future<void> _postCallSystemMessage(String roomId, Duration duration) async {
    final room = ref.read(matrixServiceProvider).client.getRoomById(roomId);
    await room?.sendEvent({
      'msgtype': 'im.gloam.call.summary',
      'body': 'Voice call · ${_formatDuration(duration)}',
      'call_duration_ms': duration.inMilliseconds,
    });
  }

  Future<void> _postMissedCallMessage(String roomId) async {
    final room = ref.read(matrixServiceProvider).client.getRoomById(roomId);
    await room?.sendEvent({
      'msgtype': 'im.gloam.call.missed',
      'body': 'Missed voice call',
    });
  }
}
```

#### 2.2 `CallState` (freezed)

```dart
@freezed
class CallState with _$CallState {
  const factory CallState.idle() = CallStateIdle;
  const factory CallState.ringingOutgoing({
    required String callId,
    required String roomId,
    required bool isVideo,
    required CallPeerInfo callee,
  }) = CallStateRingingOutgoing;
  const factory CallState.ringingIncoming({
    required String callId,
    required String roomId,
    required bool isVideo,
    required CallPeerInfo caller,
  }) = CallStateRingingIncoming;
  const factory CallState.connecting({
    required String callId,
    required String roomId,
  }) = CallStateConnecting;
  const factory CallState.active({
    required String callId,
    required String roomId,
    required bool isVideo,
    required CallPeerInfo peer,
    required DateTime startedAt,
  }) = CallStateActive;
}

@freezed
class CallPeerInfo with _$CallPeerInfo {
  const factory CallPeerInfo({
    required String userId,
    required String displayName,
    Uri? avatarUrl,
  }) = _CallPeerInfo;
}
```

---

### Task 3: Call UI Screens

**4 days | Complexity: Medium**

#### 3.1 Outgoing call screen — `lib/features/calls/presentation/screens/outgoing_call_screen.dart`

- Centered card (desktop) or full-screen (mobile)
- Callee avatar (large), name, "calling..." status
- Animated pulse dots
- Controls: mute, video toggle, end call
- "voice call" label at bottom

Show as a modal route that overlays the current screen.

#### 3.2 Incoming call screen — `lib/features/calls/presentation/screens/incoming_call_screen.dart`

- Full-screen (mobile) or notification popup (desktop)
- Caller avatar, name, "incoming voice call..." status
- Accept (green phone) and Decline (red phone-off) buttons
- Gradient background with subtle animation
- Ringtone plays via `AudioPlayer` from assets

**Desktop popup** — a small floating window at top-right:
```dart
showDialog(
  context: context,
  barrierDismissible: false,
  builder: (_) => Align(
    alignment: Alignment.topRight,
    child: IncomingCallPopup(call: incomingCall),
  ),
);
```

#### 3.3 Active call screen — `lib/features/calls/presentation/screens/active_call_screen.dart`

Voice-only mode:
- Large avatar with speaking ring, name, quality indicator, timer
- Controls at bottom: mute, video toggle, speaker, end call

Video mode:
- Remote video fills screen (or avatar if their camera is off)
- Self-view: small draggable PiP overlay (bottom-right)
- Gradient fade at top with name + timer
- Floating control bar at bottom center

#### 3.4 DM header integration

Add a phone icon button to the DM chat header:

```dart
// In chat_screen.dart header actions
if (room.isDirectChat) ...[
  IconButton(
    icon: Icon(LucideIcons.phone, color: GloamColors.textSecondary, size: 20),
    onPressed: () => ref.read(callServiceProvider.notifier).startCall(
      roomId: room.id,
      isVideo: false,
    ),
  ),
  IconButton(
    icon: Icon(LucideIcons.video, color: GloamColors.textSecondary, size: 20),
    onPressed: () => ref.read(callServiceProvider.notifier).startCall(
      roomId: room.id,
      isVideo: true,
    ),
  ),
],
```

---

### Task 4: iOS CallKit Integration

**3 days | Complexity: High**

Use `flutter_callkit_incoming` package for cross-platform call notification handling.

#### 4.1 Incoming call via CallKit

When `CallNotificationService.incomingCalls` emits:

```dart
Future<void> _showNativeIncomingCall(IncomingCall call) async {
  final params = CallKitParams(
    id: call.callId,
    nameCaller: call.callerDisplayName,
    appName: 'Gloam',
    avatar: call.callerAvatarUrl?.toString(),
    type: call.isVideo ? 1 : 0, // 0 = audio, 1 = video
    duration: 45000, // Ring for 45 seconds
    android: AndroidParams(
      isCustomNotification: true,
      ringtonePath: 'assets/sounds/ringtone.mp3',
      backgroundColor: '#080f0a',
      actionColor: '#7db88a',
    ),
    ios: IOSParams(
      supportsVideo: true,
      audioSessionMode: 'voiceChat',
      ringtonePath: 'ringtone.caf',
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}
```

#### 4.2 CallKit event handling

```dart
FlutterCallkitIncoming.onEvent.listen((event) {
  switch (event.event) {
    case Event.actionCallAccept:
      ref.read(callServiceProvider.notifier).acceptCall();
      break;
    case Event.actionCallDecline:
      ref.read(callServiceProvider.notifier).declineCall();
      break;
    case Event.actionCallEnded:
      ref.read(callServiceProvider.notifier).endCall();
      break;
    case Event.actionCallTimeout:
      ref.read(callServiceProvider.notifier).endCall();
      break;
  }
});
```

#### 4.3 Background audio session (iOS)

Configure `AVAudioSession` for voice calls:
- Category: `.playAndRecord`
- Mode: `.voiceChat`
- Options: `.allowBluetooth`, `.defaultToSpeaker` (for speakerphone)
- Background mode: `voip` in `UIBackgroundModes`

---

### Task 5: Android Call Integration

**2 days | Complexity: Medium**

`flutter_callkit_incoming` handles both platforms. Android-specific config:

#### 5.1 Foreground service

- When a call is active, start a foreground service with a persistent notification
- Notification shows: caller name, duration, mute/end buttons
- Required for background audio on Android

#### 5.2 AndroidManifest additions

```xml
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_PHONE_CALL" />
<uses-permission android:name="android.permission.VIBRATE" />
```

---

### Task 6: Multi-Device Ring Handling

**2 days | Complexity: Medium**

#### 6.1 Ring all devices

The `org.matrix.msc4075.call.notify` to-device message targets `'*'` (all devices) for the recipient. All their active sessions receive it.

#### 6.2 Answer stops ringing

When a call is accepted on one device:
1. That device joins the MatrixRTC session (sends `m.rtc.member`)
2. Other devices see the `m.rtc.member` event and know the call was answered
3. Other devices dismiss the incoming call UI and cancel the ringtone

```dart
// On each device, watch for the call being answered elsewhere
_client.onSync.listen((_) {
  if (state is CallStateRingingIncoming) {
    final room = _client.getRoomById(state.roomId);
    final memberEvents = room?.getState('org.matrix.msc3401.call.member');
    // If someone else answered (membership event with matching call_id), dismiss ring
  }
});
```

---

### Task 7: PiP and Screen Wake Lock

**2 days | Complexity: Low**

#### 7.1 Screen wake lock

During active calls, prevent screen dimming:
```dart
// On call start
WakelockPlus.enable();
// On call end
WakelockPlus.disable();
```

#### 7.2 PiP on mobile

When the user navigates away from the active call screen, the call screen shrinks to a PiP window.

On iOS: Use the native `AVPictureInPictureController` via platform channel (for video calls).
On Android: Use `Activity.enterPictureInPictureMode()` via platform channel.

For voice-only calls, PiP is not needed — the persistent voice bar handles this.

#### 7.3 Desktop floating window

On macOS, when navigating away from a video call, show the persistent voice bar (same as voice channels). Full floating-window PiP is deferred to Phase 5D.

---

## Dependencies & Blockers

| Dependency | Required By | Status | Risk |
|-----------|------------|--------|------|
| Phase 5A + 5B complete | All tasks | Must complete first | — |
| `flutter_callkit_incoming` package | Task 4, 5 | Stable, supports iOS + Android | Low |
| `wakelock_plus` package | Task 7 | Stable | Low |
| MSC4075 (call notifications) | Task 1 | Used in production by Element X | Low |
| Ringtone audio assets | Task 3, 4 | Must create/license | Low |
| iOS VoIP background mode entitlement | Task 4 | Requires Apple Developer Account config | Low |

## Key Technical Decisions

| Decision | Options | Recommendation | Rationale |
|----------|---------|---------------|-----------|
| Call system messages | Custom event type vs `m.room.message` with custom `msgtype` | **`m.room.message` with `msgtype: im.gloam.call.summary`** | Renders as a regular message in other clients (fallback `body` field), but Gloam can render it with a phone icon. |
| Ring delivery | To-device (MSC4075) vs room event | **To-device** | Room events would notify everyone in the room; to-device targets only the intended recipient. |
| Call UI routing | Modal overlay vs push route | **Modal overlay** for incoming, **push route** for active call | Incoming must overlay any screen instantly. Active call is a proper screen to navigate to/from. |
| Multi-device conflict | Last-write-wins vs explicit signaling | **Membership event check** | When device B answers, its `m.rtc.member` event appears in room state. Other devices observe this and dismiss their ring UI. Simple and reliable. |

## What "Done" Looks Like

1. Open a DM with "alex chen"
2. Tap the phone icon — outgoing call screen appears, "calling..." with pulse animation
3. On Alex's phone (locked), a native CallKit screen appears: "Gloam — alex chen"
4. Alex slides to accept — audio connects, both hear each other
5. Call timer counts up. Connection quality shows green dot
6. Alex toggles video — their camera feed appears in the main area, your self-view appears as PiP
7. Navigate back to the DM chat — PiP window shows on mobile, voice bar shows on desktop
8. Tap end call — "Voice call · 3:12" system message appears in the DM
9. Later: Alex calls you while your phone is locked — CallKit shows "alex chen calling", accept/decline
10. Decline → "Missed voice call" message appears in the DM

---

## Change History

- 2026-03-26: Initial implementation plan created
