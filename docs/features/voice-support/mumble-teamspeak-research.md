# Mumble, TeamSpeak, and Multi-Protocol Voice — Technical Research

*Compiled: 2026-03-26*

This document covers the technical architecture of Mumble and TeamSpeak as voice communication protocols, surveys other viable voice platforms, and identifies common abstractions for a potential multi-protocol voice client.

---

## 1. Mumble Protocol

### 1.1 Client-Server Architecture

Mumble is an open-source, low-latency voice chat system using a traditional client-server model. The server component is called **Murmur** (or `mumble-server`). Clients connect to Murmur, which mixes and routes encrypted voice traffic between participants. The server does not store conversation history, does not collect user data, and does not have access to decrypted voice content.

A single Murmur instance can host multiple "virtual servers" on the same port, each with independent channel trees, users, and permissions. This is roughly analogous to Discord guilds or Matrix spaces.

**Key characteristics:**
- Single server, multiple virtual servers
- All traffic encrypted (TLS for control, OCB-AES128 for voice)
- Server-authoritative: the server enforces permissions, manages channel state, and routes audio
- Low latency: round-trip times as low as 10-30ms
- Positional audio support for games
- No federation — each server is an island

### 1.2 The Mumble Protocol (TCP Control + UDP Voice)

Mumble uses **two transport channels** on port 64738:

**TCP Control Channel:**
- Wrapped in TLS (TLSv1.2+)
- Uses Google Protocol Buffers (protobuf) for message serialization
- Handles: authentication, channel/user state synchronization, text messaging, permission queries, server configuration, ACL management
- Message types defined in `Mumble.proto`: `Version`, `Authenticate`, `CryptSetup`, `ChannelState`, `UserState`, `TextMessage`, `PermissionQuery`, `ACL`, `BanList`, `UserList`, `ServerSync`, `Ping`, and more
- Also serves as a **fallback for voice data** (TCP tunneling) when UDP is blocked

**UDP Voice Channel:**
- Encrypted with AES-128 in OCB mode (keys exchanged via TCP `CryptSetup` message)
- Carries encoded audio frames
- Lower overhead than TCP for real-time audio
- Recent protocol versions (1.5+) use protobuf for UDP messages too (`MumbleUDP.proto`)
- Includes positional audio coordinates with each voice packet

### 1.3 Connection Flow

1. **TLS Handshake** — Client establishes a TLS connection to the server on port 64738
2. **Version Exchange** — Both sides send `Version` messages with protocol version, OS info
3. **CryptSetup** — Server sends cryptographic parameters for UDP voice encryption (AES-OCB key, client/server nonces)
4. **Authenticate** — Client sends username, password (if required), client certificate, and access tokens for ACL groups
5. **Channel State Sync** — Server sends `ChannelState` messages for every channel in the tree
6. **User State Sync** — Server sends `UserState` messages for every connected user
7. **ServerSync** — Final message indicating sync is complete; contains the client's session ID, welcome text, max bandwidth, and server permissions
8. **UDP Ping** — Client begins sending UDP pings to establish the voice channel; if UDP fails, voice falls back to TCP tunneling

### 1.4 Authentication Model

Mumble supports three layers of authentication:

**Certificate-based (primary):**
- Each client generates an X.509 certificate on first launch
- The certificate's SHA-1 hash is the user's persistent identity
- Server "registers" a certificate to a username — subsequent connections with that cert auto-authenticate
- No passwords needed for registered certificates
- Users can export/import certificates for device migration

**Password-based (secondary):**
- Server can require a global server password (gates entry to the entire server)
- Individual user accounts can have passwords as fallback when certificate is missing
- Access tokens: additional password-like strings that grant membership in specific ACL groups

**Third-party (via plugins):**
- Murmur exposes a gRPC/ICE API for external authenticators
- Commonly used for game guild integration (EVE Online, etc.) where an external database validates users

### 1.5 Channel Structure (Hierarchical Tree)

Mumble organizes channels as a **tree rooted at a single "Root" channel**:

```
Root
├── General
├── Gaming
│   ├── Team 1
│   ├── Team 2
│   └── AFK
├── Music
└── Admin Only
```

- Every server has exactly one root channel
- Channels can be nested to arbitrary depth
- Channels can be **permanent** (persist across server restarts) or **temporary** (deleted when last user leaves)
- Users can create temporary channels if they have the `MakeChannel` or `MakeTempChannel` permission
- **Channel links**: two channels can be temporarily linked so users in either channel hear each other — useful for cross-team communication without moving
- Channels have properties: name, description, position (sort order), max users, password

### 1.6 Codec Support

Mumble has used three codecs over its history:

| Codec | Mumble Versions | Status |
|-------|----------------|--------|
| Speex | < 1.2.0 | Deprecated, low quality |
| CELT (0.7.0 "Alpha" and 0.11.0 "Beta") | 1.2.0 – 1.2.3 | Legacy, still supported for backward compat |
| **Opus** | 1.2.4+ (since June 2013) | **Current default**, only relevant codec |

- Opus is used for all audio in modern Mumble
- Opus supports variable bitrate (8–320 kbps), but Mumble typically operates at 40–96 kbps
- CELT support exists only for backward compatibility with very old clients
- Audio frames are encoded individually per-codec; Opus frames include a termination bit in the header
- The server negotiates codec compatibility — if all clients support Opus, Opus is used; otherwise falls back to CELT

### 1.7 Permission System (ACLs)

Mumble has one of the most granular permission systems of any voice platform. It uses **Access Control Lists (ACLs)** evaluated per-channel with inheritance:

**Groups:**
- Users are assigned to named groups (e.g., `admin`, `moderator`, `member`)
- Groups are defined per-channel but inherit down the tree
- Built-in groups: `all` (everyone), `auth` (registered users), `in` (users currently in the channel), `out` (users not in the channel), `sub` (users in sub-channels)
- Groups can be modified per-channel: add members, remove members, or exclude inherited members

**ACL Rules:**
- Each channel has an ordered list of ACL rules evaluated top-to-bottom
- Each rule targets a user or group, and allows or denies specific permissions
- Later rules override earlier ones
- Rules can be set to "apply to this channel," "apply to sub-channels," or both
- Channels inherit ACLs from parents by default (can be disabled per-channel)

**Permission flags include:**
- `Write` — full admin (overrides everything)
- `Traverse` — enter the channel
- `Enter` — join the channel
- `Speak` — transmit voice
- `Whisper` — send targeted audio to specific users/channels
- `MuteDeafen` — server-mute/deafen others
- `Move` — move users between channels
- `MakeChannel` — create permanent sub-channels
- `MakeTempChannel` — create temporary sub-channels
- `LinkChannel` — link channels together
- `TextMessage` — send text messages
- `Kick` / `Ban` — remove users from the server
- `Register` — register other users' certificates
- `SelfRegister` — register your own certificate

This ACL system is substantially more powerful than Discord's role-based permissions and more comparable to Unix filesystem ACLs.

### 1.8 How Users Join/Leave Channels

- **Join**: Client sends a `UserState` message with the target `channel_id`. If permissions allow, the server updates the user's channel and broadcasts the `UserState` change to all connected clients.
- **Leave**: Implicit — joining another channel or disconnecting. There's no explicit "leave channel" message.
- **Move**: A user with `Move` permission can send a `UserState` for another user with a different `channel_id`, forcibly moving them.
- **Kick**: Sends a `UserRemove` message, disconnecting the user from the server.

### 1.9 Positional Audio

Mumble supports **3D positional audio** for games:

- Each voice packet can include the sender's 3D position (x, y, z coordinates in the game world)
- Receiving clients with positional audio enabled use these coordinates to spatialize the audio through stereo/surround output
- Distance attenuation: farther players sound quieter
- Directional audio: players to your left sound from the left speaker
- Requires a game plugin on the sender side that reads the game's memory to extract position data
- ~40 games have official positional audio plugins
- Custom plugins can be written for any game
- Can be disabled per-user (falls back to non-positional audio)

### 1.10 Server Discovery and Connection

**Manual connection:**
- Direct server address + port (default 64738)
- `mumble://` URL scheme: `mumble://[user[:password]@]host[:port]/[channel/path]`
- URLs can include channel paths, server titles, and web links

**Public server registry:**
- Servers can opt into a public server list at mumble.com/serverlist
- Requires: no server password, valid TLS certificate, worldwide accessibility
- Server registers with metadata: name, URL, location, current users

**No auto-discovery:**
- No LAN discovery, no DNS-SD
- Users must know the server address or find it via the public list
- Third-party directories and community websites are common

### 1.11 Existing Dart/Flutter Libraries

**`dumble` (dart + mumble) — [pub.dev/packages/dumble](https://pub.dev/packages/dumble)**

The only Dart library for Mumble protocol. Created by EPNW.

**What it provides:**
- Full Mumble transport client framework
- TLS control channel connection
- Encrypted UDP voice transport (OCB-AES128)
- Channel management (create, join, list)
- User management (list, query, ban)
- Text messaging
- Permission querying
- CryptState management

**What it does NOT provide:**
- Audio capture or playback (not its scope)
- Opus encoding/decoding (requires `opus_dart` or `opus_flutter` separately)
- No pure-Dart Opus implementation exists — native bindings are required
- Designed for Mumble 1.4; some newer features may be missing

**Practical implication:** Building a Mumble client in Flutter is feasible but requires integrating audio capture (platform-specific), Opus codec (native FFI), and the dumble transport layer separately. There is no "drop-in" complete Mumble client package.

**`mumble-client` Flutter app — [github.com/Ancocodet/mumble-client](https://github.com/Ancocodet/mumble-client)**
- A proof-of-concept modern Mumble client built with Flutter
- Appears to be early-stage / incomplete
- Demonstrates that the approach is technically viable

### 1.12 Protocol Documentation & Spec Availability

**Official documentation:**
- Protocol spec: [github.com/mumble-voip/mumble/tree/master/docs/dev/network-protocol](https://github.com/mumble-voip/mumble/tree/master/docs/dev/network-protocol)
- Protobuf definitions: `Mumble.proto` and `MumbleUDP.proto` in the main repo
- ReadTheDocs (older): [mumble.readthedocs.io](https://mumble.readthedocs.io)
- Wiki: [wiki.mumble.info/wiki/Protocol](https://wiki.mumble.info/wiki/Protocol)

The protocol is **fully documented** with protobuf message definitions. This is a major advantage — you can generate message classes in any language (including Dart) directly from the .proto files.

### 1.13 Open-Source Status and Community

- **License**: BSD-3-Clause (both client and server)
- **Source**: [github.com/mumble-voip/mumble](https://github.com/mumble-voip/mumble) — very active, regular releases
- **Latest stable**: 1.5.x series (as of 2026)
- **Community**: Active forums, GitHub issues, IRC/Matrix channels
- **Alternative servers**: Grumble (Go), uMurmur (minimal C), and others exist due to open protocol
- **Ecosystem**: Multiple third-party clients exist for Android, iOS, web (Mumble-web), and embedded systems
- **Cross-platform**: Official clients for Windows, macOS, Linux; third-party clients for mobile

---

## 2. TeamSpeak

### 2.1 Client-Server Architecture

TeamSpeak uses a client-server model similar to Mumble, but with a **proprietary protocol**. The server (TeamSpeak Server) handles voice routing, channel management, permissions, and user state. Clients connect to a central server, which acts as the authority.

**Key differences from Mumble:**
- Proprietary, closed-source protocol
- Server is free for non-commercial use (up to 32 slots in TS3), commercial requires licensing
- More polished out-of-the-box admin experience
- File transfer built into the protocol
- Server query interface for automation (telnet/SSH-based)

### 2.2 TeamSpeak SDK (ClientLib)

The TeamSpeak 3 SDK provides:

**Architecture:**
- `ClientLib` — client-side library for building custom voice clients
- `ServerLib` — server-side library for embedding TeamSpeak voice into custom servers
- Delivered as **shared libraries** (`.dll`, `.so`, `.dylib`) with a **C-style API**
- Available for: Windows, macOS, Linux, iOS, Android

**Capabilities:**
- Full voice communication (capture, encode, transmit, receive, decode, playback)
- Channel creation, modification, deletion
- User management (move, kick, ban)
- Text messaging
- File transfer
- Whisper system (targeted audio to specific users/channels)
- 3D/positional audio
- Audio preprocessing (AGC, noise suppression, echo cancellation)

**Codec support (TS3):**
- Speex (narrow, wide, ultra-wide band)
- Opus (Music and Voice profiles)
- CELT (legacy)
- Configurable per-channel via `CHANNEL_CODEC` and `CHANNEL_CODEC_QUALITY` properties

**What the SDK does NOT handle:**
- Permission management — the SDK provides voice transport but permissions must be managed separately via the server query or custom logic
- Server-side features like ban lists, complaint handling

### 2.3 Protocol Openness

**TeamSpeak 3 (current):**
- **Proprietary protocol** — not publicly documented
- No official protocol specification
- Some reverse-engineering efforts exist (e.g., `ts3init` for connection initiation, community protocol analyses)
- `soliloque-server` was an open-source attempt at protocol compatibility, but is unmaintained
- Encrypted by default (custom encryption layer)

**TeamSpeak 6 (beta, January 2025):**
- Complete rewrite with modernized architecture
- New protocol (details not publicly documented)
- Backward compatible with TS3 servers
- Adds screen sharing, camera sharing, hosted server purchasing
- Revised audio technology stack
- Still proprietary

### 2.4 Channel Model

TeamSpeak channels are organized in a **tree structure** similar to Mumble:

- Hierarchical parent/child channels with configurable nesting depth
- **Spacer channels** — visual separators in the channel list (no icon, no joining)
- Channels have properties: name, topic, description, password, codec, codec quality, max clients, sort order
- **Temporary channels** — auto-deleted when empty
- **Semi-permanent channels** — survive server restart but delete when empty
- **Permanent channels** — persist always
- Channel groups can be applied per-channel for fine-grained user roles

### 2.5 Permission System

TeamSpeak has a **multi-layered permission system** — arguably the most complex of any voice platform:

**Permission layers (evaluated in order):**
1. **Server Group permissions** — global roles (e.g., Admin, Moderator, Normal)
2. **Client-specific permissions** — per-user overrides
3. **Channel permissions** — per-channel settings (e.g., `i_channel_needed_join_power`)
4. **Channel Group permissions** — roles applied per-channel (e.g., Channel Admin, Channel Moderator)
5. **Channel Client permissions** — per-user per-channel overrides

**Permission model:**
- Numeric power system: each permission has an integer value
- "Needed" vs "granted" power: e.g., channel has `i_channel_needed_join_power = 50`, user needs `i_channel_join_power >= 50` to enter
- Thousands of individual permission keys covering every aspect of the system
- Talk power: controls who can speak in a channel (similar to Discord's Stage Channel)
- Server groups, channel groups, and individual overrides stack

### 2.6 SDK Licensing

- **Evaluation/trial**: Free, no-obligation license for development and testing
- **Production**: Custom licensing, negotiated individually with TeamSpeak
- **Terms**: Sublicensing not permitted; terms adapted to each customer's needs and revenue model
- **Cost**: Not publicly listed — requires direct contact with TeamSpeak sales
- **Implications for open-source**: Incompatible with most open-source licenses due to proprietary SDK requirement

### 2.7 Existing Dart/Flutter Bindings

**None exist.**

- No Dart/Flutter bindings for the TeamSpeak SDK on pub.dev or GitHub
- The SDK's C API could theoretically be wrapped via `dart:ffi`, but:
  - Requires distributing TeamSpeak's proprietary shared libraries
  - Licensing would need negotiation
  - Audio pipeline is handled internally by the SDK, reducing flexibility
- A .NET wrapper exists (`ts3_sdk_dotNet`) from TeamSpeak Systems, but no Dart equivalent
- Community has built Python, Node.js, and Rust wrappers for the server query interface (not the voice SDK)

---

## 3. Other Viable Voice Platforms

### 3.1 Ventrilo

**Status: Not viable for integration.**

- **Proprietary protocol** — no public documentation
- **No SDK** — no programmatic way to build a third-party client
- Third-party clients exist (Ventriloid for Android, Mangler for Linux) but were built via reverse engineering and are largely unmaintained
- No Dart/Flutter libraries
- No active development since ~2015; the platform is in maintenance mode
- Shrinking user base, primarily legacy gaming communities
- No mobile apps from the vendor
- **Verdict**: Dead end for integration. The effort to reverse-engineer the protocol is not justified by the tiny remaining user base.

### 3.2 Discord Voice

**Status: Technically possible via bot API, but not viable for a third-party client.**

**Official API:**
- Discord provides a **Bot/Application Voice API** that allows bots to join voice channels, send and receive audio
- Libraries: `discord.js/voice`, `PerformanC/voice`, and others implement the voice gateway protocol
- Voice gateway uses WebSocket for signaling + WebRTC/UDP for media
- Opus codec exclusively

**DAVE (Discord Audio/Video Encryption) — March 2026:**
- As of March 2, 2026, ALL Discord voice requires DAVE end-to-end encryption
- Third-party apps and bots that connect to voice must implement DAVE
- Clients without DAVE support can no longer participate in Discord calls
- The DAVE protocol whitepaper is published, but implementation is non-trivial
- This creates a significant new barrier for third-party voice integration

**Third-party client restrictions:**
- Discord's Terms of Service **explicitly prohibit** third-party clients
- "Self-bots" (user accounts connecting via non-official clients) are banned
- Bot accounts can join voice but have different capabilities than users
- No way to legally build a "user-facing" Discord voice client

**Verdict**: A Gloam integration could connect as a Discord bot to bridge voice between Matrix and Discord channels, but it cannot act as a user-level Discord client. The DAVE requirement adds significant implementation complexity. This is a bridge/bot use case, not a multi-protocol client use case.

### 3.3 Jitsi Meet

**Status: Viable and well-supported.**

Jitsi is an **open-source (Apache 2.0)** WebRTC-based video conferencing platform.

**Architecture:**
- **Jitsi Videobridge (JVB)**: SFU that routes media between participants
- **Jicofo**: Conference focus component — manages conference state
- **Prosody**: XMPP server for signaling
- **Jitsi Meet**: Web/mobile client (React + React Native)
- All components are open source and self-hostable

**Protocol:**
- XMPP (Jabber) for signaling and presence
- WebRTC for media transport
- SRTP for media encryption
- Offen supports Oportunistic SRTP, SRTP/DTLS
- Offentliches API fur External Services available

**Flutter integration:**
- `jitsi_meet_flutter_sdk` — Official Flutter plugin (Android, iOS, Web)
- `jitsi_meet` — Community Flutter package
- `omni_jitsi_meet`, `custom_jitsi_meet` — Variants with additional customization
- These wrap the native Jitsi Meet SDKs rather than implementing the protocol directly
- Integration is "embed a Jitsi conference" rather than "build a custom Jitsi client"

**Strengths for multi-protocol voice:**
- Fully open source, no licensing restrictions
- WebRTC-based (same underlying tech as LiveKit/MatrixRTC)
- Self-hostable
- Established Flutter packages
- Large-scale deployment proven (8x8 commercial backing)

**Limitations:**
- Conference model (start/join a meeting), not an always-on voice channel model
- No concept of persistent voice rooms in the Mumble/Discord sense
- More suited for scheduled meetings than ambient voice
- XMPP signaling is heavier than needed for just voice channels

### 3.4 SIP/RTP (Session Initiation Protocol)

**Status: Viable for telephony-style voice, extensive Flutter support.**

SIP is the standard protocol for VoIP telephony:

**Flutter libraries:**
- `sip_ua` — Dart SIP UA stack based on flutter-webrtc (iOS, Android, Desktop, Web)
- `siprix` — Commercial VoIP SDK with Flutter plugin (SIP/RTP/SRTP, 5 platforms)
- `portsip` — PortSIP VoIP SDK Flutter plugin

**Relevance:**
- SIP is designed for point-to-point and conferencing calls, not persistent voice channels
- Strong for telephony integration (PSTN bridging, PBX interop)
- Not a good fit for Discord/Mumble-style ambient voice rooms
- Could be valuable if Gloam ever bridges to phone networks

### 3.5 XMPP/Jingle

**Status: Niche but technically sound.**

XMPP's Jingle extension (XEP-0166) provides voice/video call signaling over XMPP:
- Uses WebRTC or native RTP for media
- Federated by design (like Matrix)
- Used by Conversations (Android), Dino (Linux), and other XMPP clients
- No Flutter-specific libraries for Jingle voice (would need custom implementation)
- Small user base compared to Matrix/Discord

### 3.6 Matrix/MatrixRTC (Already Planned)

Already covered extensively in [element-call-research.md](element-call-research.md). This is Gloam's primary voice platform. Included here for completeness in the multi-protocol comparison.

---

## 4. Common Abstractions Across Voice Systems

### 4.1 Shared Concepts

These concepts exist in **all** voice platforms and would form the core of a unified voice abstraction:

| Concept | Mumble | TeamSpeak | Discord | Jitsi | Matrix/LiveKit |
|---------|--------|-----------|---------|-------|----------------|
| **Server/Instance** | Murmur server | TS server | Guild | Jitsi deployment | Homeserver + SFU |
| **Channel/Room** | Channel (tree node) | Channel (tree node) | Voice Channel | Conference room | Matrix room |
| **User/Participant** | Connected user with session ID | Client with UID | Guild member | Conference participant | Room member with `m.rtc.member` |
| **Join channel** | `UserState` with channel_id | SDK `moveClient` | Voice state update | Join conference URL | Send `m.rtc.member` event |
| **Leave channel** | Join another / disconnect | SDK `moveClient` / disconnect | Voice state update | Leave conference | Remove `m.rtc.member` event |
| **Mute self** | Local audio track disable | SDK mute API | Voice state update | Track disable | Track disable |
| **Deafen self** | Local audio disable all | SDK deafen API | Voice state update | N/A (client-side) | N/A (client-side) |
| **Server mute** | Admin sets user state | Talk power = 0 | Moderator action | Moderator action | Power level / state event |
| **Speaking indicator** | Audio level in voice packets | SDK callback | Voice activity | Audio level API | LiveKit audio level API |
| **Text chat** | TextMessage in channel | Channel chat | Text-in-voice | Jitsi chat | Room timeline |
| **Codec** | Opus (primary) | Opus (primary) | Opus (only) | Opus (via WebRTC) | Opus (via WebRTC) |

### 4.2 Key Differences

| Aspect | Mumble | TeamSpeak | Discord | Jitsi | Matrix/LiveKit |
|--------|--------|-----------|---------|-------|----------------|
| **Auth model** | X.509 certificates + passwords + tokens | Identity + server password | OAuth2 + bot tokens | Anonymous or XMPP auth | Matrix access tokens |
| **Channel hierarchy** | Tree (arbitrarily deep) | Tree (configurable depth) | Flat within category | Flat (one conference) | Flat within space |
| **Server discovery** | Manual / public registry | Server list / DNS | Invite links / server discovery | URL-based | Room directory / invites |
| **Permission model** | ACLs with inheritance (Unix-like) | Numeric power system (layered) | Role-based with overrides | Simple (host/moderator/participant) | Power levels (numeric) |
| **Positional audio** | Native (game plugins) | Native (SDK support) | Not exposed to third parties | No | No |
| **Protocol openness** | Fully open (BSD, protobuf spec) | Proprietary (SDK available) | Partially documented (bot API) | Open (Apache 2.0) | Open (Apache 2.0, MSC specs) |
| **Federation** | None | None | None | None (but self-hostable) | Native federation |
| **Encryption** | TLS + OCB-AES128 | Proprietary encryption | DAVE E2EE (March 2026) | DTLS-SRTP | DTLS-SRTP + optional Insertable Streams |
| **Always-on channels** | Yes (permanent channels) | Yes (permanent channels) | Yes | No (conference model) | Achievable (open-inactive slots) |
| **Channel linking** | Yes (unique feature) | No | No | No | No |

### 4.3 Unified Voice Abstraction Layer

A multi-protocol voice client would need to abstract these layers:

**Layer 1: Connection Management**
```
VoiceConnection
├── connect(server, credentials) -> ConnectionState
├── disconnect()
├── reconnect()
├── connectionState: Stream<ConnectionState>  // connecting, connected, reconnecting, disconnected
└── serverInfo: ServerInfo  // name, version, capabilities
```

**Layer 2: Channel/Room Management**
```
VoiceChannelManager
├── channels: Stream<List<VoiceChannel>>  // tree structure flattened or preserved
├── joinChannel(channelId) -> JoinResult
├── leaveChannel()
├── currentChannel: Stream<VoiceChannel?>
├── createChannel(name, parent?, options?) -> VoiceChannel
└── moveUser(userId, targetChannelId)  // moderator action
```

**Layer 3: Audio Management**
```
VoiceAudioManager
├── setMuted(bool)
├── setDeafened(bool)
├── setInputDevice(deviceId)
├── setOutputDevice(deviceId)
├── setInputVolume(double)  // 0.0 - 1.0
├── setOutputVolume(double)
├── setUserVolume(userId, double)  // 0.0 - 2.0 (per-user)
├── isMuted: Stream<bool>
├── isDeafened: Stream<bool>
└── localAudioLevel: Stream<double>
```

**Layer 4: Participant Management**
```
VoiceParticipant
├── userId: String
├── displayName: String
├── channelId: String
├── isMuted: Stream<bool>
├── isDeafened: Stream<bool>
├── isServerMuted: Stream<bool>
├── isSpeaking: Stream<bool>
├── audioLevel: Stream<double>
└── position: Stream<Position3D?>  // for positional audio (Mumble/TS only)
```

**Layer 5: Permissions**
```
VoicePermissions
├── canSpeak: bool
├── canJoinChannel(channelId): bool
├── canMoveUsers: bool
├── canMuteOthers: bool
├── canKick: bool
├── canBan: bool
├── canCreateChannels: bool
└── canModifyChannel(channelId): bool
```

**Layer 6: Protocol Adapter (per-platform)**
```
abstract class VoiceProtocolAdapter {
  Future<VoiceConnection> connect(ServerConfig config);
  VoiceChannelManager get channels;
  VoiceAudioManager get audio;
  Stream<List<VoiceParticipant>> get participants;
  VoicePermissions getPermissions(String? channelId);
  Future<void> sendTextMessage(String channelId, String text);
}

// Concrete implementations:
class MumbleAdapter extends VoiceProtocolAdapter { ... }  // uses dumble
class MatrixRTCAdapter extends VoiceProtocolAdapter { ... }  // uses livekit_client + MatrixRTCService
class JitsiAdapter extends VoiceProtocolAdapter { ... }  // uses jitsi_meet_flutter_sdk
// class TeamSpeakAdapter extends VoiceProtocolAdapter { ... }  // would require C FFI + licensing
```

### 4.4 What Would Differ Per Protocol

| Concern | Abstraction Strategy |
|---------|---------------------|
| **Authentication** | Each adapter handles auth internally; expose a generic `credentials` type with protocol-specific subtypes (certificate for Mumble, access token for Matrix, etc.) |
| **Channel hierarchy** | Normalize to a tree model (Mumble/TS are native trees; Matrix/Discord/Jitsi are flat — simulate flat as depth-1 tree) |
| **Server discovery** | Protocol-specific discovery UI; unified "saved servers" list with protocol tag |
| **Positional audio** | Optional capability — only Mumble and TeamSpeak support it natively; expose as an optional mixin |
| **Encryption** | Handled internally by each adapter; expose a boolean "encrypted" indicator |
| **Federation** | Only Matrix supports this; other protocols are server-bound. Abstraction doesn't need to model federation. |
| **Permissions** | Normalize to a capability set (can_speak, can_join, can_moderate); hide the complexity of ACLs vs power levels vs numeric powers |

---

## 5. Feasibility Assessment for Gloam

### 5.1 Priority Ranking

| Protocol | Integration Effort | User Value | Feasibility | Priority |
|----------|-------------------|------------|-------------|----------|
| **Matrix/MatrixRTC** | High (but already planned) | Critical | High | **P0 — Primary** |
| **Mumble** | Medium (dumble exists, protocol is open) | Medium (niche but loyal community) | High | **P1 — Most viable secondary** |
| **Jitsi** | Low (Flutter SDK exists) | Medium (meeting-style calls) | High | **P2 — Easy win** |
| **TeamSpeak** | High (C FFI + licensing) | Medium (loyal gaming community) | Medium (licensing risk) | **P3 — Possible but complex** |
| **Discord Voice** | Very High (DAVE, ToS issues) | High (huge user base) | Low (legal risk) | **P4 — Bot/bridge only** |
| **SIP** | Medium (Flutter libs exist) | Low (telephony niche) | High | **P5 — Future consideration** |
| **Ventrilo** | Very High (reverse engineering) | Very Low (tiny user base) | Very Low | **Not viable** |

### 5.2 Recommended Approach

1. **Ship MatrixRTC voice** as the primary voice experience (already planned in PRD)
2. **Mumble integration** as the first secondary protocol — it's fully open, has a Dart library, and the protocol is well-documented. The user base overlaps with privacy-conscious, self-hosting users who would be Gloam's early adopters.
3. **Jitsi integration** as an easy addition for meeting-style calls — Flutter SDK exists, minimal custom work
4. **TeamSpeak** only if there's clear demand and willingness to navigate SDK licensing
5. **Discord** only as a voice bridge (bot connecting Gloam and Discord voice channels), never as a client

---

## Sources

- [Mumble Protocol Documentation (GitHub)](https://github.com/mumble-voip/mumble/tree/master/docs/dev/network-protocol)
- [Mumble Protocol Wiki](https://wiki.mumble.info/wiki/Protocol)
- [Mumble Protocol ReadTheDocs](https://mumble.readthedocs.io/en/latest/establishing_connection.html)
- [Mumble.proto Protobuf Definitions](https://github.com/mumble-voip/mumble/blob/master/src/Mumble.proto)
- [Mumble ACL Documentation](https://www.mumble.info/documentation/administration/acl/)
- [Mumble URL Scheme](https://www.mumble.info/documentation/user/mumble-url/)
- [Mumble Wikipedia](https://en.wikipedia.org/wiki/Mumble_(software))
- [dumble Dart Package](https://pub.dev/packages/dumble)
- [dumble GitHub](https://github.com/EPNW/dumble)
- [Ancocodet Flutter Mumble Client](https://github.com/Ancocodet/mumble-client)
- [TeamSpeak SDK Developer Page](https://teamspeak.com/en/more/developers/)
- [TeamSpeak SDK Documentation](https://teamspeakdocs.github.io/PluginAPI/client.html)
- [TeamSpeak Licensing](https://support.teamspeak.com/hc/en-us/articles/26033788383261-What-licenses-are-available)
- [TeamSpeak Wikipedia](https://en.wikipedia.org/wiki/TeamSpeak)
- [TeamSpeak 6 Beta Announcement](https://zap-hosting.com/en/blog/2025/01/teamspeak-is-back-new-features-new-design-and-much-more/)
- [Discord Voice API Documentation](https://discord.com/developers/docs/resources/voice)
- [Discord DAVE E2EE Announcement](https://discord.com/blog/bringing-dave-to-all-discord-platforms)
- [discord.js Voice Implementation](https://github.com/discordjs/voice)
- [Jitsi Meet Flutter SDK](https://pub.dev/documentation/jitsi_meet_flutter_sdk/latest/)
- [sip_ua Dart Package](https://pub.dev/packages/sip_ua)
- [Siprix VoIP SDK for Flutter](https://github.com/siprix/FlutterPluginFederated)
- [Ventrilo Wikipedia](https://en.wikipedia.org/wiki/Ventrilo)
- [Mumble Public Server List](https://www.mumble.com/serverlist/)

---

## Change History

- 2026-03-26: Initial research document created covering Mumble, TeamSpeak, Discord, Jitsi, Ventrilo, SIP, and unified abstraction design.
