# Element Call & MatrixRTC — Technical Research Document

*Compiled: 2026-03-26*

This document is a comprehensive technical breakdown of the Matrix protocol's voice/video calling capabilities via Element Call and MatrixRTC. It serves as the technical foundation for Gloam's voice support implementation.

---

## 1. Element Call Overview

### What It Is

Element Call is a Matrix-native voice/video conferencing system that implements **MatrixRTC** using **LiveKit** as its media backend. It exists in two forms:

- **Standalone web app**: Full conferencing PWA (hosted at call.element.io) with its own auth, room management, and UI. Users can create/join calls without a separate Matrix client.
- **Embedded widget**: Stripped-down build designed to be embedded inside Matrix clients via the Matrix widget API. The host client handles auth, room state, and events; Element Call handles the call UI and LiveKit connection.

### How It Integrates with Matrix Rooms

Matrix rooms are the signaling and coordination layer. **Media does not flow through Matrix** — it flows through the LiveKit SFU. The Matrix room serves as:

- **Identity and access control**: Who can join (room membership + power levels)
- **Signaling channel**: Membership events, encryption key distribution
- **Discovery mechanism**: How clients find which SFU to connect to

### Current State (March 2026)

Element Call has delivered **over 139 years of cumulative meeting time**. It is close to stable/GA but still in beta. Remaining work:
- 1:1 calling refinements for full telephone-like functionality
- SFU membership lifecycle safeguards
- Final reliability testing under poor network conditions

### Legacy VoIP vs MatrixRTC

| Aspect | Legacy VoIP (Matrix v1.x) | MatrixRTC / Element Call |
|--------|--------------------------|--------------------------|
| Call types | 1:1 only | 1:1 AND group |
| Topology | Direct peer-to-peer WebRTC | SFU (LiveKit) |
| Signaling events | `m.call.invite`, `m.call.answer`, etc. | `m.rtc.member`, `m.rtc.slot` |
| Group calls | Jitsi widget (separate system) | Native via SFU |
| Encryption | WebRTC DTLS-SRTP only | DTLS-SRTP + Insertable Streams E2EE |
| Multi-device | Not supported | Built-in |

**There is no interoperability between legacy and MatrixRTC calling.** Element X exclusively uses MatrixRTC for all calls.

---

## 2. Technical Architecture

### MatrixRTC Protocol (MSC4143)

MatrixRTC is a general-purpose RTC framework for Matrix rooms. Core concepts:

- **Slots** (`m.rtc.slot` state events): Virtual containers where sessions occur — "the call" within a room. Each slot has a `slot_id` and can be Open-Active (has participants), Open-Inactive (no participants), or Closed. A room can have multiple concurrent slots.
- **Members** (`m.rtc.member` sticky events): Participants join a slot by sending membership events.
- **Sessions**: The period of overlapping connected members in a slot. Starts when first member connects, ends when last leaves.

### Membership Events

`m.rtc.member` events (MSC4354 "sticky events") contain:

```json
{
  "slot_id": "call-id-here",
  "member": {
    "id": "uuid-for-this-participation",
    "claimed_device_id": "ABCDEF",
    "claimed_user_id": "@user:example.com"
  },
  "rtc_transports": [
    {
      "type": "livekit",
      "livekit_service_url": "https://lk.example.com/jwt"
    }
  ]
}
```

**Sticky Events (MSC4354)**: A new event type providing temporary, per-user room state. Delivered via `/sync`, limited lifetime (~1 hour), can be encrypted. Solves the problem of polluting persistent room state with transient call membership data.

### LiveKit SFU Integration (MSC4195)

**Connection flow:**

```
1. Client reads .well-known/matrix/client
   -> discovers org.matrix.msc4143.rtc_foci -> livekit_service_url

2. Client requests OpenID token from homeserver

3. Client sends OpenID token to lk-jwt-service (MatrixRTC Auth Service)

4. lk-jwt-service validates token against homeserver's OpenID endpoint

5. lk-jwt-service returns LiveKit JWT + SFU WebSocket URL

6. Client connects to LiveKit SFU using JWT

7. Media flows via WebRTC between client and SFU
```

**lk-jwt-service access levels:**
- **Full-access** (allowlisted homeservers): Can create LiveKit rooms, publish and subscribe
- **Restricted** (federated): Can only join existing rooms and subscribe

### SFU vs Mesh

| Topology | Max Participants | Client Bandwidth | Server Required |
|----------|-----------------|-----------------|-----------------|
| Mesh (deprecated) | ~8 | O(n^2) — sends to everyone | No |
| SFU (current) | 500 per instance | O(1) — sends once to SFU | Yes (LiveKit) |

SFU scales horizontally via Kubernetes. Multi-SFU federation is supported — each homeserver can operate its own SFU, with participants publishing to their local SFU and subscribing across federation.

### Homeserver vs SFU Responsibilities

| Concern | Homeserver | SFU (LiveKit) |
|---------|-----------|---------------|
| User identity & auth | Yes | No (receives JWT) |
| Room membership & permissions | Yes | No |
| Call signaling (who is in call) | Yes (state events) | No |
| Encryption key distribution | Yes (room events / to-device) | No |
| Media transport | No | Yes (WebRTC) |
| NAT traversal (TURN/STUN) | No | Yes (built-in TURN) |

### End-to-End Encryption

Element Call implements **true E2EE at the media layer** — the SFU cannot decrypt media content. This is layered on top of standard WebRTC DTLS-SRTP:

**Layer 1 — DTLS-SRTP (transport):** Standard WebRTC encryption between client and SFU. Automatic but SFU can theoretically access plaintext frames.

**Layer 2 — Insertable Streams / SFrame (application):** Element Call encrypts media frames *before* they enter the WebRTC pipeline. The SFU only sees encrypted payloads.

**Key distribution:**
```
Matrix Homeserver
  -> EncryptionKeyChanged event (room events or to-device messages)
  -> MatrixKeyProvider.onEncryptionKeyChanged()
  -> crypto.subtle.importKey("raw") + HKDF derivation
  -> E2EE Web Worker (per connection)
  -> Insertable Streams encryption/decryption
  -> LiveKit media tracks (encrypted end-to-end)
```

**Encryption modes:**
- **Shared-key** (default, Matrix 2.0): Single key shared across all participants. More efficient for large calls.
- **Per-participant** (legacy): Individual key per participant. Stronger isolation but higher overhead.

**Key rotation:** Keys rotate when membership changes. `EncryptionKeyChanged` events with incremented `encryptionKeyIndex` trigger automatic re-keying without reconnection.

---

## 3. Feature Support Matrix

| Feature | Status | Notes |
|---------|--------|-------|
| 1:1 voice calls | Supported | Via MatrixRTC, not legacy |
| 1:1 video calls | Supported | |
| Group voice calls | Supported | 100+ participants tested |
| Group video calls | Supported | Up to 500 per SFU |
| Screen sharing | Supported | |
| End-to-end encryption | Supported | Insertable Streams + Matrix key distribution |
| Emoji reactions during calls | Supported | |
| Hand raise | Supported | |
| Mute/unmute audio | Supported | |
| Camera on/off | Supported | |
| Speaker/tile view layouts | Supported | Persistent presenter tile, scrollable participants |
| Call notifications/ringing | Supported | MSC4075: `m.rtc.notification` events |
| Decline call notification | Supported | MSC4310 |
| CallKit (iOS) | Supported | In Element X |
| Picture-in-Picture | Supported | On mobile |
| Join without camera/mic | Supported | Feature flag available |
| Guest access | Supported | Standalone mode only |
| Always-on voice rooms | Partial | Slot model supports this natively (open-inactive slots can be joined anytime); Element Web has "video rooms" |
| Phone dial-in (PSTN) | Not supported | |
| Server-side recording | Not supported | |
| Breakout rooms | Not supported | |
| Virtual backgrounds | Not supported | |
| Live transcription | Not supported | |

---

## 4. Integration Methods for Custom Clients

### Option A: Embed Element Call as a Widget (Fastest Path)

The recommended approach for most custom clients. Element Call runs as an iframe widget communicating via `postMessage`.

**How it works:**
1. Host client constructs a URL with required parameters
2. Element Call detects widget mode when `widgetId` is present
3. Communication happens via Matrix Widget API (postMessage)
4. Host handles encryption, auth, room state; Element Call handles call UI + LiveKit

**Required URL parameters:**
- `userId`, `roomId`, `widgetId`, `deviceId`, `displayName`

**Optional parameters:**
- `lang`, `skipLobby`, `hideHeader`, `hideScreensharing`, `confineToRoom`
- Analytics: `posthogApiHost`, `posthogApiKey`, `sentryDsn`

**Packaging options:**
- **Full package**: Docker/tarball — standalone + widget
- **Embedded package**: npm, Android AAR, SwiftPM for iOS — widget-only, optimized for bundling
- **SDK package**: Programmatic API via `sdk/main.ts`

**Pros:** Minimal implementation work. All calling features included.
**Cons:** Limited UI customization. Iframe boundary. Dependent on Element Call's release cycle.

### Option B: Native MatrixRTC Implementation (Full Control)

Build your own call UI and connect directly to MatrixRTC + LiveKit.

**What you need to implement:**
1. `MatrixRTCSession` management (membership, slot lifecycle)
2. `m.rtc.member` sticky event handling
3. `m.rtc.slot` state event management
4. LiveKit JWT auth flow (discover `.well-known`, exchange OpenID for JWT)
5. LiveKit SFU connection via `livekit-client` SDK
6. Encryption key distribution (room events or to-device)
7. Delayed leave events (MSC4140) for graceful disconnect
8. Your own call UI

**Pros:** Full control over UX. No iframe limitations. Can build Discord-like voice channel UX.
**Cons:** Significantly more work. Must track MatrixRTC spec changes.

### Option C: Hybrid Approach

Use the Element Call SDK package programmatically for the media layer while building a custom UI around it.

**Pros:** Avoids reimplementing the complex media/encryption stack while allowing custom UX.
**Cons:** SDK API surface may not expose everything needed for voice channel UX.

---

## 5. SDK APIs Available

### matrix-js-sdk MatrixRTC Module

**`MatrixRTCSessionManager`**: Central registry across all rooms. Auto-creates session objects when RTC events arrive. Emits events when sessions start/end.

**`MatrixRTCSession`**: Manages a single call session.
- `joinRTCSession(fociPreferred, fociActive?, joinConfig?)` — join a call
- `leaveRoomSession(timeout?)` — leave with optional timeout
- `isJoined()` — check participation status
- `reemitEncryptionKeys()` — re-emit keys for late joiners
- `updateCallIntent(callIntent)` — switch between audio/video intent
- `memberships` — array of current `CallMembership` objects
- Events: `EncryptionKeyChanged`, membership updates

**`MembershipManager`**: Handles lifecycle of membership state events.
- Sends delayed leave events (8s default) before joining
- Periodic heartbeat (5s intervals)
- Handles rate limits and network errors with retry logic
- States: Connecting -> Connected -> Disconnected

**`CallMembership`**: Represents a participant. Provides: `deviceId`, `sender`, `callId`/`slotId`, focus info.

### matrix-rust-sdk

Provides MatrixRTC support and widget integration:
- `WidgetSettings::new_virtual_element_call_widget(props, config)` — generates widget URL
- `VirtualElementCallWidgetProperties`: `element_call_url`, `widget_id`, `parent_url`, `encryption`, analytics config
- `VirtualElementCallWidgetConfig`: `intent` (6 variants including voice-only), `header`, `preload`, `confine_to_room`, `hide_screensharing`, `controlled_audio_devices`
- `EncryptionSystem` enum: `Unencrypted`, `PerParticipantKeys`, `SharedSecret`

### LiveKit Flutter SDK (`livekit_client`)

For native implementations in Flutter:
- `Room` — manages connection to a LiveKit room
- `LocalParticipant` — local user's tracks and state
- `RemoteParticipant` — remote users
- `Track` / `AudioTrack` / `VideoTrack` — media tracks
- Simulcast support (multiple quality layers)
- Speaker detection via audio levels
- Reconnection handling

---

## 6. Relevant Matrix Events

| Event Type | Purpose |
|-----------|---------|
| `m.rtc.slot` | Defines a call slot in a room (state event) |
| `m.rtc.member` | Signals participation in a slot (sticky event, MSC4354) |
| `io.element.call.encryption_keys` | E2EE key distribution (room event) |
| `org.matrix.msc4075.rtc.notification` | Call ringing/notification (to-device) |
| `org.matrix.msc4310.rtc.decline` | Decline incoming call (to-device) |

### Legacy Events (Not Used by MatrixRTC)

| Event Type | Purpose |
|-----------|---------|
| `m.call.invite` | Legacy 1:1 call invite |
| `m.call.answer` | Legacy 1:1 call answer |
| `m.call.candidates` | Legacy ICE candidates |
| `m.call.hangup` | Legacy call hangup |

---

## 7. Server-Side Requirements

### Components Needed

1. **Matrix homeserver** (Synapse recommended) with experimental features:
   ```yaml
   experimental_features:
     msc3266_enabled: true   # Room Summary API
     msc4222_enabled: true   # state_after in sync v2
   max_event_delay_duration: 24h  # MSC4140 delayed events
   ```

2. **LiveKit SFU** — the media server:
   - Docker: `livekit/livekit-server`
   - Ports: 7880 (WebSocket signaling), 30001/TCP, 30002/UDP (media), 30003/TCP (TURN-TLS)
   - Built-in TURN server

3. **lk-jwt-service** (MatrixRTC Authorization Service):
   - Docker: `ghcr.io/element-hq/lk-jwt-service:0.4.1`
   - Port: 8080
   - Config: `LIVEKIT_URL`, `LIVEKIT_KEY`, `LIVEKIT_SECRET`, `LIVEKIT_FULL_ACCESS_HOMESERVERS`

4. **Reverse proxy** (Nginx/Caddy) for TLS and routing:
   - `/livekit/jwt/` -> lk-jwt-service (8080)
   - `/livekit/sfu/` -> LiveKit (7880, with WebSocket upgrade)

### .well-known Configuration

`/.well-known/matrix/client` must include:
```json
{
  "m.homeserver": { "base_url": "https://matrix.example.com" },
  "org.matrix.msc4143.rtc_foci": [
    {
      "type": "livekit",
      "livekit_service_url": "https://matrix-rtc.example.com/livekit/jwt"
    }
  ]
}
```

Must be served with `Content-Type: application/json` and CORS headers.

### TURN/STUN

- LiveKit includes built-in STUN for public IP discovery
- LiveKit includes built-in TURN server (TCP-TLS on port 30003)
- External TURN (coturn) can also be used
- When behind a load balancer: disable STUN, set `manualIP`

---

## 8. Relevant MSCs

| MSC | Title | Status | Relevance |
|-----|-------|--------|-----------|
| **MSC3401** | Native Group VoIP Signaling | Foundation | Original group call proposal; MSC4143 builds on this |
| **MSC4143** | MatrixRTC | Active | Core RTC framework: slots, membership, transports |
| **MSC4195** | MatrixRTC Transport using LiveKit | Active | LiveKit SFU binding: JWT auth, focus config |
| **MSC4075** | MatrixRTC Call Notifications | Active | Ringing and call notifications |
| **MSC4310** | MatrixRTC Decline Notification | Active | Declining incoming calls |
| **MSC4140** | Delayed Events | Active | Server-side scheduled events for crash recovery |
| **MSC4354** | Sticky Events | Active | Temporary per-user state for membership |
| **MSC4222** | state_after in sync v2 | Active | Reliable room state tracking |
| **MSC3266** | Room Summary API | Active | Federation-based room joining |
| **MSC3898** | Cascaded Foci | WIP | Multi-SFU/MCU topologies |

---

## 9. Current Limitations and Risks

### Protocol Maturity

- MatrixRTC event schemas are still MSC-stage, not merged into the Matrix spec. Breaking changes are possible.
- Element X's implementation is the de facto reference — following their patterns reduces risk.
- Delayed events (MSC4140) are critical for reliability. Without them, if a client crashes, stale membership events persist.

### Performance Boundaries

- Full mesh: ~8 participants max (deprecated).
- SFU: Up to 500 per instance on a single VPS. Horizontal scaling via Kubernetes.
- Multi-SFU federation distributes load but adds complexity.

### Missing Features vs Discord

| Discord Feature | MatrixRTC Status |
|----------------|-----------------|
| Always-on voice channels | Achievable — slots can be open-inactive and joined anytime |
| Per-user volume control | Client-side only — adjust WebRTC track gain |
| Push-to-Talk | Client-side only — mute/unmute mic track |
| Priority Speaker | Not in protocol — must implement client-side audio mixing |
| Soundboard | No protocol support — could send audio as separate track |
| Voice Activity Detection | Client-side — monitor audio levels |
| Server mute (persistent) | Via Matrix power levels — deny speaking permission |
| Channel bitrate control | LiveKit supports per-room bitrate configuration |
| AFK timeout / auto-move | Client-side timer + leave session |

### SFU Deployment is Non-Negotiable

There is no way to do MatrixRTC group calls without an SFU. Options:
- Self-host LiveKit (open source, Docker-ready)
- Use Element's hosted LiveKit infrastructure (if available to third-party clients)
- For 1:1 calls only: could potentially use direct peer-to-peer, but MatrixRTC currently routes everything through the SFU for consistency

---

## 10. Key Takeaways for Gloam

1. **Native implementation is the right path** for Discord-like voice channels. The widget approach constrains UX too much for ambient voice rooms.

2. **LiveKit Flutter SDK (`livekit_client`)** is the media layer. It's stable and well-maintained.

3. **MatrixRTC membership events** are the signaling layer. Voice channels = rooms with active `m.rtc.member` events.

4. **E2EE is achievable** but adds significant complexity. Consider making it opt-in per voice channel initially.

5. **Server-side requirements** must be documented clearly for self-hosters. LiveKit + lk-jwt-service + homeserver config.

6. **The Dart `matrix` SDK (v0.40.2)** does not have MatrixRTC built in like matrix-js-sdk does. Gloam will need to implement MatrixRTC signaling on top of the raw event APIs. This is the biggest technical risk.

7. **Follow Element X's patterns** — they are the reference implementation and validate the protocol in production.
