# Voice Support PRD — Gloam

**Feature ID:** FEAT-007
**Requested:** 2026-03-26
**Status:** Proposed
**Priority:** High
**Effort:** Large (8-12 weeks)

---

## Overview

Add Discord-caliber voice and calling support to Gloam, powered by MatrixRTC and LiveKit. This covers three distinct interaction models:

1. **Always-on voice channels** — ambient, drop-in/drop-out voice rooms within spaces (Discord's core innovation)
2. **DM calls** — ring-to-answer 1:1 and group calls from direct messages
3. **Room calls** — ad-hoc group calls within any text room

The goal is to match Discord's voice UX as closely as the Matrix protocol allows, while leveraging MatrixRTC for federation, E2EE, and interoperability with other Matrix clients.

### Companion Documents

- [Discord Voice Research](discord-voice-research.md) — competitive feature breakdown
- [Element Call / MatrixRTC Research](element-call-research.md) — technical foundation

---

## User Stories

**Voice Channels:**
- As a space member, I want to see which voice channels have people in them and join with a single click, so I can hang out without the friction of "calling" someone.
- As a space admin, I want to create voice channels with capacity limits and permissions, so I can organize my community's voice spaces.
- As a user in a voice channel, I want to navigate anywhere in the app while staying connected, with a persistent bar showing my voice state and controls.

**DM Calls:**
- As a user, I want to call someone from a DM and have their phone ring, so I can reach them for a real-time conversation.
- As a user receiving a call, I want to see an incoming call screen (or native phone notification on mobile) with accept/decline options.
- As a group DM participant, I want anyone in the group to be able to start a call that rings everyone, with the ability for others to join late.

**Room Calls:**
- As a room member, I want to start an ad-hoc voice/video call that others in the room can join, for spontaneous group conversations.

**Universal:**
- As a user on a call, I want mute, deafen, screen share, and camera controls that work reliably.
- As a user, I want to control my audio devices, noise suppression, and per-user volume.

---

## Discord-to-Gloam Feature Mapping

This table maps every Discord voice feature to what Gloam can achieve with MatrixRTC/LiveKit, with a feasibility assessment.

### Voice Channels

| Discord Feature | Gloam Equivalent | Feasibility | Phase |
|----------------|-----------------|-------------|-------|
| Always-on voice channels | Matrix rooms with `m.rtc.member` state events + Gloam room tag | Full | 1 |
| Join with single click (no ringing) | Join LiveKit session on click, send `m.rtc.member` event | Full | 1 |
| Users listed under channel in sidebar | Read `m.rtc.member` events, show participants under room | Full | 1 |
| Speaking indicator (green ring) | LiveKit audio level API -> green ring on avatar | Full | 1 |
| Mute/deafen icons on participants | Track local state + room state events for server mute | Full | 1 |
| Persistent voice connection bar | Flutter overlay widget, visible on all routes | Full | 1 |
| Navigate away while connected | Voice connection managed by a global provider, not tied to route | Full | 1 |
| Channel capacity limits | Custom room state event for max participants | Full | 2 |
| Stage channels (speaker/audience) | Custom power-level gating: deny "speak" to audience role | Partial | 3 |
| Voice channel status text | Custom room state event or room topic | Full | 2 |
| Text-in-voice | Room already has a timeline — just show it alongside voice UI | Full | 1 |
| Screen sharing | LiveKit screen capture APIs + `flutter_webrtc` | Full | 2 |
| Video in voice channels | LiveKit video tracks, grid layout | Full | 2 |
| Go Live / streaming | Equivalent to screen share with game context — screen share covers this | Partial | 2 |
| Embedded Activities | Out of scope (requires Activity SDK equivalent) | None | — |
| Soundboard | Send audio clips via LiveKit data channel or audio track injection | Partial | 3 |
| AFK timeout / auto-move | Client-side idle timer -> auto-leave | Full | 2 |
| Voice channel bitrate control | LiveKit per-room bitrate configuration | Full | 2 |
| Per-user volume | Adjust WebRTC audio track gain per remote participant | Full | 1 |

### DM Calls

| Discord Feature | Gloam Equivalent | Feasibility | Phase |
|----------------|-----------------|-------------|-------|
| 1:1 voice call with ringing | MSC4075 call notifications + MatrixRTC session | Full | 1 |
| 1:1 video call | Same as voice + enable video track | Full | 1 |
| Group DM calls (up to 10) | MatrixRTC session in DM room, ring all via MSC4075 | Full | 2 |
| Ring timeout (~60s) | Client-side timer on outgoing call | Full | 1 |
| Incoming call UI (overlay) | Full-screen overlay on mobile, popup on desktop | Full | 1 |
| CallKit (iOS native ring) | Platform channel to CXProvider | Full | 1 |
| Android call notification | Foreground service with call controls | Full | 1 |
| Multi-device ring (all devices, answer stops others) | MatrixRTC membership + to-device events | Full | 2 |
| Missed call indicator | System message in DM timeline | Full | 1 |
| Call duration system message | Post `m.room.message` with call summary on hangup | Full | 1 |
| Join late to ongoing group call | "Join Call" button in DM header when `m.rtc.member` events exist | Full | 2 |
| Decline notification (MSC4310) | Send decline to-device event | Full | 1 |

### Voice UX

| Discord Feature | Gloam Equivalent | Feasibility | Phase |
|----------------|-----------------|-------------|-------|
| Voice Activity Detection (default) | Monitor mic audio levels, auto-transmit above threshold | Full | 1 |
| Push-to-Talk | Hold-to-unmute with configurable keybind | Full | 2 |
| Push-to-Talk release delay | Configurable timer after key release | Full | 2 |
| Noise suppression (Krisp) | RNNoise or similar client-side ML model, or platform APIs | Partial | 2 |
| Input/output device selection | `flutter_webrtc` device enumeration | Full | 1 |
| Input/output volume sliders | Adjust track gain | Full | 1 |
| Mic test (record and playback) | Local audio capture -> playback | Full | 2 |
| Per-user volume (0-200%) | Per-track gain adjustment on remote audio | Full | 1 |
| Echo cancellation | WebRTC built-in AEC | Full | 1 |
| Automatic Gain Control | WebRTC built-in AGC | Full | 1 |
| Noise reduction | WebRTC built-in NS | Full | 1 |
| Global hotkeys (mute/deafen) | Platform-specific global keybind registration | Partial | 2 |
| Connection quality indicator | LiveKit connection stats: RTT, packet loss, jitter | Full | 1 |
| Automatic reconnection | LiveKit SDK handles reconnection natively | Full | 1 |

### Permissions & Moderation

| Discord Feature | Gloam Equivalent | Feasibility | Phase |
|----------------|-----------------|-------------|-------|
| Connect permission | Matrix room membership / invite-only | Full | 1 |
| Speak permission | Custom power level for voice transmission | Full | 2 |
| Video permission | Custom power level for video/screen share | Full | 2 |
| Force Push-to-Talk | Custom room setting, client-enforced | Full | 3 |
| Priority Speaker | Client-side audio attenuation when priority user speaks | Full | 3 |
| Server mute (moderator) | Custom state event, enforced client-side + power level | Full | 2 |
| Server deafen (moderator) | Custom state event, enforced client-side | Full | 2 |
| Move members between channels | Leave one room's call, send invite to another | Partial | 3 |
| Disconnect members | Moderator removes user's `m.rtc.member` event | Full | 2 |

---

## UX Specification

### Voice Channel — Room List Appearance

Voice channels are Matrix rooms tagged with `im.gloam.voice_channel` in room create content or room tags. In the space sidebar:

```
# TEXT CHANNELS
  # general
  # announcements

# VOICE CHANNELS
  🔊 Lounge                    ← speaker icon, not hash
     🟢 Alice  🔇 Bob  Charlie  ← connected participants (max 5 avatars + "+N")
  🔊 Gaming (3/10)             ← capacity shown when limited
  🔊 Music                     ← empty channel, still visible
```

**Visual treatment:**
- Speaker/headphone icon instead of `#` hash
- Connected participants shown as a row of small avatars beneath the channel name
- Green dot on avatar = currently speaking
- Mic-slash overlay on avatar = muted
- Headphone-slash overlay = deafened
- Participant count badge when >5 connected
- Subtle pulse/glow animation on the channel name when someone is speaking
- Capacity indicator when a user limit is set (e.g., "3/10")

### Voice Channel — Join Flow

1. **User taps/clicks a voice channel** in the sidebar.
2. **If not in a voice channel**: Immediately connect. No lobby, no ringing, no confirmation.
3. **If already in a different voice channel**: Show a brief confirmation: "Switch to Lounge? You'll leave Gaming." with Switch / Cancel buttons.
4. **On connect**: The voice channel view opens, showing the participant grid. The persistent voice bar appears at the bottom of the app.
5. **Mic defaults to unmuted** (configurable in settings). Camera defaults to off.

### Voice Channel — Active View

When viewing a voice channel, the main content area shows:

```
┌─────────────────────────────────────────────┐
│  🔊 Lounge                          ⚙️ ...  │  ← channel header with settings
├─────────────────────────────────────────────┤
│                                             │
│   ┌──────┐  ┌──────┐  ┌──────┐             │
│   │ 🟢   │  │      │  │ 🔇   │             │  ← participant tiles
│   │Alice │  │ Bob  │  │Carol │             │     (avatar, name, status)
│   └──────┘  └──────┘  └──────┘             │     green ring = speaking
│                                             │     icons for mute/deafen
│   ┌──────┐  ┌──────┐                       │
│   │      │  │      │                       │
│   │Dave  │  │ Eve  │                       │
│   └──────┘  └──────┘                       │
│                                             │
├─────────────────────────────────────────────┤
│  💬 Text chat                          ▲    │  ← collapsible text-in-voice
│  Alice: anyone want to play?                │
│  Bob: sure, give me 5                       │
│  [message input]                            │
└─────────────────────────────────────────────┘
```

**Participant tiles:**
- Avatar (large, centered)
- Display name below avatar
- Green animated ring when speaking (driven by LiveKit audio levels)
- Mute icon overlay (bottom-right of avatar) when self-muted
- Deafen icon overlay when deafened
- Server-mute icon (red, distinct from self-mute) when moderator-muted
- Video feed replaces avatar when camera is on
- Screen share indicator when sharing

**Text-in-voice:**
- The room's existing text timeline appears in a collapsible panel below the participant grid.
- Drag handle or toggle to expand/collapse.
- Full message composer with all existing features (attachments, emoji, etc.).

### The Persistent Voice Bar

This is the single most important UX element. It must be visible on **every screen** while connected to voice.

```
┌──────────────────────────────────────────────────────────┐
│  🔊 Lounge · Space Name     0:42:15   🟢   🎤  🎧  📞  │
│     Alice, Bob, +3 others                                │
└──────────────────────────────────────────────────────────┘
```

**Layout:**
- **Left**: Speaker icon + channel name + space name. Tapping navigates to the voice channel view.
- **Center**: Connection duration timer. Connection quality dot (green/yellow/red).
- **Right**: Control buttons:
  - 🎤 Mute/unmute toggle
  - 🎧 Deafen/undeafen toggle
  - 📞 Disconnect (red, prominent)
- **Subtitle**: Names of connected participants (truncated with "+N others")

**Behavior:**
- Rendered as a persistent bar above the bottom navigation (mobile) or at the bottom of the sidebar (desktop).
- Stays visible when navigating to any room, DM, settings, or other space.
- Tapping the channel name area navigates back to the voice channel.
- Single tap on disconnect — no confirmation dialog.
- Swipe up on the bar (mobile) to expand into a mini-control panel with additional options (camera, screen share, per-user volume).

### DM Call — Outgoing Call Flow

1. **User taps the phone icon** in a DM conversation header.
2. **Outgoing call screen** appears:
   ```
   ┌─────────────────────────┐
   │                         │
   │      [Avatar]           │
   │      Alice              │
   │                         │
   │    Calling...           │  ← pulsing animation
   │                         │
   │                         │
   │        [🔴 End]         │  ← hang up button
   │                         │
   └─────────────────────────┘
   ```
3. **MatrixRTC**: Send `m.rtc.notification` (MSC4075) to ring the recipient. Open a MatrixRTC session.
4. **Timeout**: If no answer after 45 seconds, show "No Answer". Post "Missed call" system message to the DM.
5. **Connected**: Transition to the active call UI.

### DM Call — Incoming Call Flow

1. **Recipient receives `m.rtc.notification`**.
2. **Incoming call screen**:
   ```
   ┌─────────────────────────┐
   │                         │
   │      [Avatar]           │
   │      Bob                │
   │                         │
   │    Incoming call...     │
   │                         │
   │   [🟢 Accept]  [🔴 Decline]  │
   │                         │
   └─────────────────────────┘
   ```
3. **Mobile**:
   - iOS: CallKit integration — appears as native phone call on lock screen.
   - Android: High-priority notification with Accept/Decline actions, foreground service for ringtone.
4. **Accept**: Connect to the MatrixRTC session. Transition to active call UI.
5. **Decline**: Send decline notification (MSC4310). Post "Declined call" or simply no system message (to avoid social awkwardness — match Discord's behavior of just showing "Missed call").
6. **Multi-device**: All user's devices ring. Answering on one sends a to-device event that stops ringing on others.

### DM Call — Active Call UI

```
┌─────────────────────────┐
│   Alice · 3:42     🟢   │  ← name, duration, quality
│                         │
│      [Large Avatar      │  ← remote user's avatar/video
│       or Video]         │
│                         │
│              [Small     │  ← self-view (draggable PiP)
│               Self]     │
│                         │
│  🎤  📹  🖥️  🔊  🔴    │  ← mute, camera, screen share,
│                         │     speaker, end call
└─────────────────────────┘
```

**Controls:**
- Mute/unmute microphone
- Toggle camera
- Screen share (desktop: window/screen picker; mobile: system screen capture)
- Speaker/audio routing (earpiece vs speaker on mobile; device selection on desktop)
- End call

**Video behavior:**
- Remote video fills the main area.
- Self-view is a small draggable PiP overlay (bottom-right default).
- If both cameras are off, show avatars with speaking indicators.
- When screen sharing, the shared screen takes the main area; participants move to a small strip.

### DM Call — System Messages

After a call ends, post a system message to the DM timeline:

- **Completed call**: "Voice call · 12:34" (with phone icon)
- **Missed call**: "Missed voice call" (with missed-call icon)
- **Declined call**: "Missed voice call" (same as missed — no "declined" to avoid social friction)

### Voice Settings

Accessible from Settings > Voice & Audio:

```
INPUT
  Device:     [Dropdown: Default / Built-in Mic / USB Mic / ...]
  Volume:     [━━━━━━━━━━━━━━━━━━━━━━━●━━━━━━] 80%
  [Test Microphone]

OUTPUT
  Device:     [Dropdown: Default / Speakers / Headphones / ...]
  Volume:     [━━━━━━━━━━━━━━━━━━━━━━━━━●━━━━] 90%

INPUT MODE
  ○ Voice Activity
    Sensitivity: [━━━━━●━━━━━━━━━━━━━━━━━━━━━]
  ○ Push to Talk
    Keybind: [Record Keybind]
    Release Delay: [━━●━━━━] 200ms

VOICE PROCESSING
  Echo Cancellation     [ON]
  Noise Reduction       [ON]
  Auto Gain Control     [ON]
  Noise Suppression     [ON]  ← ML-based (RNNoise or platform)

ADVANCED
  QoS High Priority     [OFF]
  Auto Disconnect After [Never ▾]  (Never / 30m / 1h / 4h)
```

### Per-User Volume Control

Right-click (desktop) or long-press (mobile) on any participant in a voice channel or call:

```
┌──────────────────────────┐
│  Alice                   │
│  Volume: [━━━━━●━━━━━━━] │  ← 0% to 200%
│                          │
│  [Mute for me]           │  ← local-only mute
│  ── moderator ──         │
│  [Server Mute]           │  ← only if has permission
│  [Disconnect]            │
└──────────────────────────┘
```

---

## Technical Architecture

### Integration Approach: Native MatrixRTC (not Widget)

**Decision**: Build native MatrixRTC support rather than embedding Element Call as a widget.

**Rationale**: The widget/iframe approach constrains UX too much for Discord-like voice channels. The persistent voice bar, ambient join/leave, sidebar participant display, and deep integration with the room list all require native control over the voice state and UI. Element Call's widget is designed for "click to enter a call room" — not for ambient, always-connected voice.

**Trade-off**: Significantly more implementation work, but results in a voice experience that no other Matrix client has achieved.

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                         GLOAM CLIENT                         │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Voice UI   │  │  Call UI     │  │  Room List +     │  │
│  │  (channels,  │  │  (DM calls,  │  │  Sidebar voice   │  │
│  │   bar, grid) │  │   ring, PiP) │  │  indicators      │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                    │            │
│  ┌──────┴─────────────────┴────────────────────┴─────────┐  │
│  │              VoiceService (Riverpod)                   │  │
│  │  - Global voice state (connected/disconnected/ringing) │  │
│  │  - Current room, participants, audio levels            │  │
│  │  - Mic/camera/screen share track management            │  │
│  │  - Per-user volume settings                            │  │
│  └──────────────────────┬────────────────────────────────┘  │
│                         │                                   │
│  ┌──────────────────────┴────────────────────────────────┐  │
│  │           MatrixRTCService                            │  │
│  │  - m.rtc.member event send/receive                    │  │
│  │  - m.rtc.slot management                              │  │
│  │  - Call notifications (MSC4075)                       │  │
│  │  - Encryption key distribution                        │  │
│  │  - SFU discovery (.well-known)                        │  │
│  │  - LiveKit JWT acquisition                            │  │
│  └──────────────────────┬────────────────────────────────┘  │
│                         │                                   │
│  ┌──────────────────────┴────────────────────────────────┐  │
│  │           LiveKit Client (livekit_client)              │  │
│  │  - WebRTC peer connection to SFU                      │  │
│  │  - Audio/video track management                       │  │
│  │  - Simulcast (multi-quality layers)                   │  │
│  │  - Speaker detection (audio levels)                   │  │
│  │  - Reconnection handling                              │  │
│  └──────────────────────┬────────────────────────────────┘  │
│                         │                                   │
│  ┌──────────────────────┴────────────────────────────────┐  │
│  │           Platform Layer                              │  │
│  │  - iOS: CallKit, AVAudioSession, PiP                  │  │
│  │  - Android: ConnectionService, foreground service     │  │
│  │  - macOS: Audio device management                     │  │
│  │  - Permissions: camera, microphone                    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                           │
                    WebRTC (media)
                           │
                    ┌──────┴──────┐
                    │  LiveKit    │
                    │  SFU        │
                    └──────┬──────┘
                           │
                    Matrix (signaling)
                           │
                    ┌──────┴──────┐
                    │ Homeserver  │
                    │ (Synapse)   │
                    └─────────────┘
```

### Key Technical Decisions

#### 1. MatrixRTC Signaling on Dart matrix SDK

The Dart `matrix` SDK (v0.40.2) does not have built-in MatrixRTC support like matrix-js-sdk. Gloam must implement MatrixRTC signaling on top of the raw event APIs:

- **Send** `m.rtc.member` state events via `room.client.setRoomStateWithKey()`
- **Receive** membership events via room sync / state event listeners
- **Handle** delayed events (MSC4140) for crash recovery
- **Manage** encryption key distribution via room events

This is the biggest technical lift and should be abstracted into a `MatrixRTCService` that can evolve independently.

#### 2. Voice Channel Room Identification

Voice channels are regular Matrix rooms with special metadata:

```json
{
  "type": "m.room.create",
  "content": {
    "type": "im.gloam.voice_channel"
  }
}
```

Or, for retrofitting existing rooms:
```json
{
  "type": "im.gloam.room_config",
  "state_key": "",
  "content": {
    "voice_channel": true,
    "max_participants": 25,
    "default_bitrate": 96000
  }
}
```

Other Matrix clients will see these as normal rooms (graceful degradation). Gloam renders them with voice channel UI treatment.

#### 3. Voice State as Global Riverpod Provider

Voice connection state must be global (not tied to a route):

```dart
// Simplified — actual implementation will be more complex
@riverpod
class VoiceState extends _$VoiceState {
  // Current state: disconnected, connecting, connected, ringing_in, ringing_out
  // Current room ID (if connected)
  // Current participants (list with audio levels, mute states)
  // Local tracks (mic, camera, screen share)
  // Per-user volume overrides
}
```

This provider is watched by:
- The persistent voice bar widget (always visible when connected)
- The room list (to show participants under voice channels)
- The voice channel view (participant grid)
- The call UI (DM calls)
- Platform integrations (CallKit, foreground service)

#### 4. Audio Pipeline

```
Microphone → WebRTC Audio Processing (AEC/NS/AGC) → Opus Encoder → LiveKit SFU
LiveKit SFU → Opus Decoder → Per-user Gain Adjustment → Speaker/Headphones
```

WebRTC's built-in audio processing handles echo cancellation, noise suppression, and automatic gain control. Additional ML-based noise suppression (RNNoise) can be layered on top as a post-processing step.

Per-user volume is implemented by adjusting the gain on each remote audio track independently.

#### 5. E2EE Strategy

**Phase 1**: No media E2EE. Transport encryption (DTLS-SRTP) only. This matches most users' expectations and dramatically reduces complexity.

**Phase 2+**: Implement Insertable Streams E2EE following Element Call's pattern. Distribute keys via `io.element.call.encryption_keys` room events. This requires the Insertable Streams API on all platforms — feasible on mobile via native WebRTC, more complex on desktop.

**Rationale**: Shipping voice channels quickly is more valuable than shipping them with E2EE. Voice E2EE is a feature, not a prerequisite. Matrix signaling events are still encrypted via room E2EE.

---

## Phased Implementation Plan

### Phase 1: Foundation + Voice Channels (Weeks 1-4)

The core voice experience. After this phase, users can join voice channels, talk, and navigate freely with the persistent bar.

**Week 1-2: Infrastructure**
- [ ] Add `livekit_client` and `flutter_webrtc` dependencies
- [ ] Implement `MatrixRTCService`:
  - Send/receive `m.rtc.member` state events
  - SFU discovery via `.well-known`
  - LiveKit JWT acquisition (OpenID token exchange)
  - Participant tracking (who's in the call, join/leave events)
- [ ] Implement `VoiceService` (global Riverpod provider):
  - Connection state machine (disconnected -> connecting -> connected)
  - LiveKit room connection lifecycle
  - Local audio track management (mic mute/unmute)
  - Remote participant tracking with audio levels
  - Per-user volume control (gain adjustment)
- [ ] Platform permissions: camera + microphone on all platforms
- [ ] Audio device enumeration and selection

**Week 2-3: Voice Channel UI**
- [ ] Voice channel room type detection (`im.gloam.voice_channel`)
- [ ] Room list: voice channels with speaker icon, participant avatars, speaking indicators
- [ ] Voice channel view: participant grid with avatars, names, speaking rings
- [ ] Text-in-voice: show room timeline below participant grid
- [ ] Join flow: single click to connect, no lobby/ringing
- [ ] Switch channel confirmation dialog
- [ ] Voice settings screen (input/output device, volume, voice processing toggles)

**Week 3-4: Persistent Voice Bar**
- [ ] Persistent bottom bar widget (visible on all routes when connected)
- [ ] Bar contents: channel name, space name, duration, quality, mute/deafen/disconnect
- [ ] Tap channel name to navigate to voice channel
- [ ] Connection quality indicator (green/yellow/red from LiveKit stats)
- [ ] Automatic reconnection handling (visual state: "Reconnecting...")

**Week 4: DM Calls (Basic)**
- [ ] Outgoing call initiation from DM header (phone icon)
- [ ] Call notification sending (MSC4075 `m.rtc.notification`)
- [ ] Outgoing call screen (avatar, "Calling...", hang up)
- [ ] Incoming call screen (avatar, accept/decline)
- [ ] Active call UI (avatar/video, controls, duration timer)
- [ ] Call end + system messages in DM timeline ("Voice call · 5:23", "Missed call")
- [ ] Ring timeout (45 seconds)

**Phase 1 Exit Criteria:**
- Can create and join voice channels within a space
- Voice channels show connected participants in the sidebar with real-time speaking indicators
- Persistent voice bar works across all navigation
- Can make and receive 1:1 DM voice calls with ringing
- Audio quality is good on broadband (Opus via LiveKit)
- Works on macOS and iOS (primary platforms)

### Phase 2: Polish + Video + Screen Share (Weeks 5-8)

Adds video, screen sharing, group DM calls, and voice UX refinements.

**Week 5: Video Support**
- [ ] Camera track management (enable/disable, front/back switch on mobile)
- [ ] Video rendering in participant tiles (replace avatar with video feed)
- [ ] Self-view PiP overlay (draggable)
- [ ] Gallery grid layout adaptation (2, 4, 6, 9 tiles based on participant count)
- [ ] Active speaker detection + auto-spotlight (large view for speaker, strip for others)

**Week 6: Screen Sharing**
- [ ] Desktop: screen/window picker via `flutter_webrtc`
- [ ] Desktop: share system audio alongside screen (where platform supports)
- [ ] Mobile: iOS ReplayKit broadcast extension, Android MediaProjection
- [ ] Receiving: auto-layout switch (screen share main area, participants in sidebar strip)
- [ ] "You are sharing your screen" indicator banner with stop button
- [ ] Screen share in DM calls

**Week 7: Group DM Calls + Mobile Integration**
- [ ] Group DM call initiation (ring all members)
- [ ] Late join: "Join Call" button in DM header for ongoing calls
- [ ] iOS CallKit integration (native incoming call screen, lock screen support)
- [ ] Android ConnectionService (system call integration, notification with controls)
- [ ] iOS PiP (AVPictureInPictureController via platform channel)
- [ ] Android PiP (Activity.enterPictureInPictureMode)
- [ ] Background audio session management (iOS AVAudioSession, Android foreground service)

**Week 8: Voice UX Refinements**
- [ ] Push-to-Talk mode with configurable keybind and release delay
- [ ] ML noise suppression toggle (RNNoise or platform equivalent)
- [ ] Mic test (record and playback)
- [ ] Per-user volume context menu (0-200% slider)
- [ ] Voice channel capacity limits (custom state event, enforce on join)
- [ ] AFK auto-disconnect timer (configurable: never/30m/1h/4h)
- [ ] Voice channel status text (custom state event, displayed in sidebar)
- [ ] Global hotkeys for mute/deafen (macOS, Windows, Linux)

**Phase 2 Exit Criteria:**
- Video calls work in voice channels and DMs
- Screen sharing works on desktop and mobile
- Group DM calls with ringing and late join
- CallKit (iOS) and system call integration (Android)
- PiP on all mobile platforms
- Push-to-Talk, noise suppression, per-user volume all functional
- Voice channels have capacity limits and status text

### Phase 3: Advanced + Moderation (Weeks 9-12)

Power features, moderation tools, and parity with Discord's deeper voice capabilities.

**Week 9-10: Permissions & Moderation**
- [ ] Voice-specific power levels: speak, video, screen share
- [ ] Server mute: moderator sets state event, client enforces (cannot unmute)
- [ ] Server deafen: same pattern, persists across rejoin
- [ ] Disconnect member: moderator removes `m.rtc.member` event, LiveKit ejects
- [ ] Voice permission UI in room settings
- [ ] Priority Speaker: attenuate others when priority user speaks (client-side mixing)

**Week 10-11: Stage Channel Mode**
- [ ] Stage mode toggle on voice channels (room state event)
- [ ] Speaker/audience separation: audience members muted by default
- [ ] Request to Speak: audience sends custom event, moderators approve/deny in UI
- [ ] Moderator controls: invite to speak, move to audience, mute speaker
- [ ] Stage UI: speakers in main area, audience count indicator

**Week 11-12: Polish & Platform Parity**
- [ ] Desktop floating window for active calls (always-on-top mini window)
- [ ] Connection diagnostics panel (click quality indicator: ping, packet loss, codec, server)
- [ ] Soundboard: upload short audio clips to room, play via data channel
- [ ] Ad-hoc room calls: start a call from any text room's header
- [ ] E2EE for voice (Insertable Streams + key distribution) — if protocol is stable
- [ ] Android, Windows, Linux platform testing and fixes
- [ ] Performance optimization: reduce idle bandwidth (Opus DTX), battery optimization on mobile

**Phase 3 Exit Criteria:**
- Full voice moderation: server mute/deafen, disconnect, per-permission control
- Stage channels functional for events/presentations
- Platform parity across macOS, iOS, Android (Windows/Linux best-effort)
- Voice channels consume near-zero bandwidth when idle
- Connection quality diagnostics available

---

## Dependencies

### New Package Dependencies

| Package | Purpose | Maturity |
|---------|---------|----------|
| `livekit_client` | LiveKit Flutter SDK — SFU connection, media tracks | Stable, production-grade |
| `flutter_webrtc` | WebRTC for Flutter — peer connections, screen capture | Stable on mobile, maturing on desktop |

### Server-Side Requirements

Users/admins must have:
1. Matrix homeserver with MSC4140 (delayed events) and MSC4222 (state_after) enabled
2. LiveKit SFU instance
3. lk-jwt-service (MatrixRTC auth)
4. `.well-known` configured with `rtc_foci`

Gloam should document these requirements clearly and ideally detect missing configuration with helpful error messages ("Voice channels require a LiveKit server. See docs for setup.").

### Internal Dependencies

| Dependency | Required For |
|-----------|-------------|
| Room list + sidebar (Phase 2) | Voice channel display |
| E2EE infrastructure (Phase 1) | Call signaling encryption |
| Notification system | Call notifications, incoming ring |
| Space hierarchy | Voice channel organization |
| Message composer | Text-in-voice |
| Platform channels (existing) | CallKit, Android services |

---

## Success Criteria

| Metric | Target |
|--------|--------|
| Voice channel join latency | < 2 seconds (click to hearing audio) |
| 1:1 call setup (answer to media) | < 3 seconds |
| Audio latency (mouth-to-ear, SFU) | < 200ms |
| Voice channel idle bandwidth | < 5 kbps per participant (Opus DTX) |
| Persistent bar render time | < 16ms (single frame, no jank) |
| Reconnection after brief drop | < 5 seconds, transparent |
| CallKit ring-to-screen (iOS) | < 2 seconds |
| Simultaneous video streams | 25 (matching Discord) |
| Screen share resolution (desktop) | 1080p / 30fps minimum |

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Dart matrix SDK lacks MatrixRTC — must build from scratch | Certain | High | Abstract into a clean `MatrixRTCService`. Follow Element X's event schemas exactly. |
| MatrixRTC event schemas change before spec stabilization | Medium | High | Pin to known-working schemas. Watch Element X releases. Abstract signaling from UI. |
| LiveKit Flutter SDK bugs on specific platforms | Medium | Medium | Test early on all platforms. Audio-only fallback if video pipeline fails. |
| flutter_webrtc desktop screen capture issues (especially Wayland) | High | Low | Test early. X11/macOS/Windows are reliable. Wayland requires PipeWire detection. |
| Server-side requirements deter self-hosters | Medium | Medium | Clear documentation. Detect missing config and show helpful errors. Consider offering a "Gloam voice server" hosted option. |
| Voice channel concept confuses other Matrix clients | Low | Low | Other clients see normal rooms with state events. Not harmful, just not surfaced as voice channels. |
| Battery drain on mobile during long voice sessions | Medium | Medium | Opus DTX for silence. Reduce CPU when idle. Test battery consumption early. |

---

## Open Questions

1. **Hosted SFU**: Should Gloam offer a managed LiveKit instance for users who don't want to self-host? This dramatically lowers the barrier but adds operational cost.

2. **Interop with Element Call**: When an Element user starts a call in a room, should Gloam be able to join it (and vice versa)? This requires matching Element Call's exact MatrixRTC event schemas, which is the plan — but needs validation.

3. **Voice channel creation UX**: Should voice channel creation be a distinct action ("Create Voice Channel") or should any room be convertible to a voice channel in settings?

4. **Video by default in voice channels?**: Discord voice channels start audio-only; video is opt-in. Should Gloam follow this pattern, or offer "video channel" as a distinct type?

5. **Soundboard priority**: Is the soundboard feature worth the complexity, or should it be deferred indefinitely? It's fun but non-essential.

6. **E2EE timeline**: Should media E2EE be a hard requirement before shipping, or is transport encryption sufficient for v1?

---

## Change History

- 2026-03-26: Initial PRD created with full Discord feature mapping, UX specification, technical architecture, and phased implementation plan.
