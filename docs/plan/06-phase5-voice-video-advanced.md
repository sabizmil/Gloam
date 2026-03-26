# Phase 5: Voice/Video & Advanced Features

**Weeks 23-28 | 6 weeks**

*Last updated: 2026-03-25*

---

## Objectives

Push Gloam past messaging-only parity and into the territory that makes Discord sticky: real-time voice/video, expressive media (custom emoji, stickers, GIFs), space-wide moderation that actually works, and multi-account support. By the end of this phase, Gloam should be the most capable Matrix client shipping, with features no other Matrix client offers natively.

## Success Criteria

| Metric | Target |
|--------|--------|
| 1:1 call setup time (answer → media flowing) | < 3 seconds |
| Group call join latency | < 5 seconds |
| Voice channel idle bandwidth per participant | < 5 kbps |
| Voice channel join/leave latency | < 1 second |
| Audio latency (mouth-to-ear, 1:1) | < 150ms |
| Audio latency (mouth-to-ear, group via SFU) | < 250ms |
| Custom emoji render time in timeline | < 16ms (single frame) |
| Space-wide ban propagation | < 2 seconds to all rooms |
| Account switch time | < 500ms |
| No regression on Phase 4 performance targets | All green |

---

## Task Breakdown

### 1. 1:1 Voice/Video Calls (High Priority)

**Week 23 | ~8 days**

The foundation for all real-time communication. Must feel snappy and reliable before attempting group calls.

#### 1.1 MatrixRTC Signaling Layer

- Implement MatrixRTC call signaling on top of matrix_dart_sdk
  - `m.call.invite`, `m.call.answer`, `m.call.candidates`, `m.call.hangup` event handling
  - ICE candidate gathering and exchange via Matrix room events
  - SDP offer/answer negotiation
  - Call state machine: `idle` -> `ringing` -> `connecting` -> `connected` -> `ended`
  - Handle edge cases: simultaneous calls (glare resolution), call replacement, call migration between devices
- TURN/STUN server configuration
  - Fetch TURN credentials from homeserver (`/_matrix/client/v3/voip/turnServer`)
  - Credential rotation before expiry
  - Fallback STUN servers if homeserver doesn't provide TURN

#### 1.2 WebRTC Integration

- Integrate `flutter_webrtc` package for cross-platform WebRTC
  - `RTCPeerConnection` lifecycle management
  - Audio/video track management (local and remote)
  - Media stream constraints (resolution, framerate, audio processing)
  - Codec negotiation (prefer VP9/AV1 for video, Opus for audio)
- Audio pipeline
  - Echo cancellation, noise suppression, automatic gain control (AEC/NS/AGC)
  - Audio device enumeration and switching (speaker, earpiece, Bluetooth, wired)
  - Audio routing on iOS (AVAudioSession category management)
  - Audio routing on Android (AudioManager mode switching)
  - Desktop: system audio device selection
- Video pipeline
  - Camera enumeration and switching (front/back on mobile, webcam selection on desktop)
  - Resolution adaptation based on network quality
  - Hardware acceleration (platform encoders/decoders)
  - Camera preview with mirror for self-view

#### 1.3 Platform Permissions

- Camera and microphone permission requests with rationale dialogs
  - iOS: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` in Info.plist
  - Android: `CAMERA`, `RECORD_AUDIO` runtime permissions
  - macOS: camera and microphone entitlements + TCC prompts
  - Windows/Linux: permission handling via flutter_webrtc defaults
- Permission state tracking and graceful degradation (voice-only if camera denied)
- Settings deep-link if permissions permanently denied

#### 1.4 Call UI

- Incoming call screen
  - Full-screen overlay on mobile, notification-style popup on desktop
  - Caller avatar, name, call type (audio/video)
  - Accept (audio), accept (video), decline buttons
  - Ringtone playback with vibration (mobile)
- Active call screen
  - Self-view (small PiP overlay, draggable)
  - Remote video (full screen)
  - Control bar: mute mic, mute camera, flip camera, speaker toggle, end call
  - Call duration timer
  - Network quality indicator (based on RTCStatsReport: packet loss, jitter, RTT)
  - Screen dimming prevention during active call
- Call state transitions with animations
  - Ringing pulse animation
  - Connecting spinner
  - Connected transition
  - Call ended summary (duration, quality)

#### 1.5 Picture-in-Picture (PiP)

- iOS: native PiP using `AVPictureInPictureController` via platform channel
  - Requires `com.apple.developer.avfoundation.multitasking-camera-access` entitlement
  - Background audio session management
- Android: PiP mode via `Activity.enterPictureInPictureMode()`
  - Custom PiP actions (mute, end call)
  - Aspect ratio management
- macOS/Desktop: Flutter-level floating window
  - Always-on-top mini window with remote video
  - Drag to reposition, click to return to full call view
- PiP should activate automatically when navigating away from call screen

#### 1.6 CallKit / ConnectionService

- iOS CallKit integration
  - `CXProvider` for incoming call UI (native iOS call screen)
  - `CXCallController` for programmatic call actions
  - `CXProviderConfiguration` with app icon and ringtone
  - Handle system interruptions (other calls, Siri)
  - Report call events to CallKit for recent calls list
  - Background audio via `UIBackgroundModes: voip`
- Android ConnectionService
  - `ConnectionService` implementation for system call integration
  - Telecom manager registration
  - Handle Bluetooth, wired headset, and car audio routing
  - Notification with call controls (foreground service)
- Desktop: no system call integration needed, just in-app UI

---

### 2. Group Voice/Video Calls (High Priority)

**Weeks 23-24 | ~8 days**

Builds on 1:1 infrastructure. Group calls require an SFU to avoid O(n^2) mesh connections.

#### 2.1 SFU Integration (LiveKit)

- Integrate LiveKit Flutter SDK (`livekit_client`)
  - LiveKit room connection lifecycle
  - Token generation (via Gloam backend or homeserver widget API)
  - Participant management (join, leave, track subscription)
  - Reconnection handling with state recovery
- MatrixRTC-to-LiveKit bridge
  - Use MatrixRTC `m.call.member` state events to signal call participation
  - Map Matrix room membership to LiveKit room tokens
  - Handle the MatrixRTC focus mechanism (selecting LiveKit as the SFU focus)
  - Coordinate call state between Matrix events and LiveKit room state
- LiveKit server requirements
  - Document self-hosting requirements (LiveKit server, TURN)
  - Support Element's hosted LiveKit infrastructure as default
  - Configuration in homeserver `.well-known` or room state

#### 2.2 Gallery View

- Grid layout for multiple participants
  - Dynamic grid sizing: 2 (1x2), 3-4 (2x2), 5-6 (2x3), 7-9 (3x3), 10+ (paginated grid)
  - Responsive to window/screen size
  - Participant tiles: video feed, avatar fallback (camera off), name label, mute indicator
  - Smooth layout transitions when participants join/leave
- Thumbnail quality adaptation
  - Request lower resolution for grid participants
  - Request higher resolution for active speaker or spotlight
  - LiveKit simulcast layers: high (720p), medium (360p), low (180p)

#### 2.3 Active Speaker Detection

- LiveKit audio level tracking per participant
- Visual indicator: highlighted border on active speaker tile
- Auto-spotlight mode: active speaker gets large view, others in small strip
- Configurable: user can pin a specific participant or switch to pure grid
- Speaker history for smooth transitions (debounce rapid switching, ~1.5s hold)

#### 2.4 Screen Sharing

- Desktop (macOS, Windows, Linux)
  - Screen/window picker using `flutter_webrtc` screen capture APIs
  - Share entire screen or specific window
  - System audio capture where platform supports it (Windows, Linux PulseAudio)
  - Mouse cursor rendering in shared stream
  - Indicator banner: "You are sharing your screen" with stop button
- Mobile (iOS, Android)
  - iOS: `RPScreenRecorder` via ReplayKit broadcast extension
  - Android: MediaProjection API
  - Both: system-level permission prompt, notification indicator
- Receiving screen share
  - Automatic layout switch: screen share gets main area, participants in sidebar strip
  - Pinch-to-zoom on mobile
  - Full-screen mode on desktop

#### 2.5 Bandwidth Adaptation

- LiveKit adaptive bitrate (server-side, per subscriber)
- Client-side network quality detection
  - Monitor `RTCStatsReport` for packet loss, jitter, RTT
  - Degrade gracefully: reduce video resolution -> disable video -> audio-only
- User-facing quality selector: Auto / High / Low / Audio Only
- Network quality indicator per participant (good/fair/poor based on stats)

---

### 3. Persistent Voice Channels (High Priority)

**Weeks 24-25 | ~8 days**

The single biggest differentiator vs every other Matrix client. Discord proved that "always-on voice rooms you drop into" is fundamentally different from "calls you initiate."

#### 3.1 Matrix Primitive Mapping (Research Required)

This is uncharted territory for Matrix. No client has shipped this. Options to evaluate:

**Option A: Room state event approach**
- Create a custom state event type (e.g., `im.gloam.voice_channel`) on a Matrix room
- Room acts as both text channel and voice channel simultaneously
- Participants signal presence via `m.call.member` state events (MatrixRTC pattern)
- Voice channel "state" is derived from who has active `m.call.member` events
- Pros: Uses existing MatrixRTC patterns, room-based permissions work naturally
- Cons: State events have federation latency, no real "persistent call" primitive in Matrix

**Option B: Dedicated voice room type**
- Create rooms specifically typed as voice channels (custom `m.room.create` content)
- Auto-join to LiveKit/SFU when entering the room
- Text chat is secondary (still available, like Discord voice channel text)
- Pros: Clean separation of concerns
- Cons: New room type may confuse other Matrix clients

**Option C: Widget-based approach**
- Use Matrix widget API to embed a persistent LiveKit session in a room
- Widget state managed via room state events
- Pros: Interoperable with other clients that support widgets
- Cons: Widget API has limitations, may feel second-class

**Recommended: Option A** — It aligns most naturally with MatrixRTC direction and doesn't require inventing new room types. The voice channel is a regular room with a special UI treatment in Gloam.

#### 3.2 Voice Channel UI

- Room list representation
  - Voice channel rooms displayed with a speaker/headphone icon instead of hash
  - Show connected participants inline (avatar row under channel name, max 5 + "+N")
  - Participant count badge
  - Visual pulse/glow when someone is speaking
- Join/leave interaction
  - Single click/tap to join (no ringing, no call initiation flow)
  - Click again or dedicated "Disconnect" button to leave
  - Confirmation dialog only if already in another voice channel ("Switch channel?")
- Connected state indicator
  - Persistent bottom bar when connected: channel name, mute/deafen/disconnect buttons
  - Shows on all screens while connected (similar to Discord's voice connection bar)
  - Tap bar to return to voice channel view

#### 3.3 Who's Talking Visualization

- Real-time audio level indicators per participant
  - Green ring around avatar when speaking
  - Audio level visualizer (subtle waveform or volume bar)
- Muted indicator (mic slash icon)
- Deafened indicator (headphone slash icon)
- Server-muted indicator (distinct from self-mute)
- Idle vs active visual distinction

#### 3.4 Low Idle Bandwidth

- When no one is speaking, bandwidth should approach zero
  - Opus DTX (Discontinuous Transmission) — sends silence comfort noise frames at ~1-2 kbps
  - Disable video tracks when no camera is active
  - LiveKit handles SFU-side optimization (no forwarding of silent streams)
- Connection keep-alive: minimal heartbeat to maintain LiveKit session
- Auto-disconnect after configurable idle timeout (default: never, option for 30m/1h/4h)
- Device battery optimization
  - Reduce CPU usage during idle (no audio processing when channel is silent)
  - Network interface power hints on mobile

#### 3.5 Voice Channel Permissions

- Inherits from Matrix room power levels
  - Who can join (room membership)
  - Who can speak (custom power level for voice)
  - Who can video (custom power level)
  - Who can screen share (custom power level)
  - Who can mute others (moderator action)
  - Who can disconnect others (moderator action)
- Channel capacity limit (configurable by admins, default: 25)
- Priority speaker role (their audio is louder/always forwarded, like Discord's priority speaker)

---

### 4. Custom Emoji per Space (Medium Priority)

**Week 25-26 | ~5 days**

Custom emoji is the single most-requested rich media feature in Matrix. It's been an open request for ~10 years. Gloam ships it.

#### 4.1 Matrix State Events for Custom Emoji

- Use `im.ponies.room_emotes` state event (MSC2545 — the established community standard)
  - State key maps to emoji pack name
  - Event content contains shortcode-to-MXC-URI mappings
  - Support multiple packs per room/space
- Space-level emoji packs
  - Emoji defined at space level propagate to all rooms in the space
  - Room-level packs override/extend space-level packs
  - Namespace collision handling: room pack takes precedence
- Emoji metadata
  - Shortcode (e.g., `:gloam_wave:`)
  - Image MXC URI (static PNG/WebP or animated GIF/WebP)
  - Optional attribution/creator field
  - Pack metadata: name, icon, description

#### 4.2 Admin Upload UI

- Space settings > Custom Emoji section
  - Grid view of all emoji in the space
  - Upload button: select image, auto-crop to square, preview at emoji size (32x32, 64x64)
  - Supported formats: PNG, GIF, WebP (animated supported)
  - Max file size: 256KB (configurable)
  - Auto-generate shortcode from filename, editable
  - Bulk upload support (drag-and-drop multiple files on desktop)
- Per-pack management
  - Create/rename/delete packs
  - Reorder emoji within packs
  - Import pack from another space (by room alias or pack URL)
- Permission gating: only users with sufficient power level can manage emoji

#### 4.3 Emoji Picker Integration

- Extend existing emoji picker with custom emoji tab
  - Tab order: Frequently Used, Custom (space), Unicode categories
  - Custom emoji displayed in pack groups
  - Search matches shortcodes (fuzzy match)
  - Tooltip shows `:shortcode:` on hover (desktop)
  - Animated emoji play on hover, static at rest
- Shortcode autocomplete in composer
  - Type `:` to trigger autocomplete popup
  - Shows matching custom emoji with preview and shortcode
  - Tab/Enter to select, Escape to dismiss
  - Prioritize custom emoji from current space, then global/other spaces

#### 4.4 Reactions with Custom Emoji

- Allow custom emoji as reactions on messages
  - Reaction picker includes custom emoji tab
  - Custom emoji reactions render at reaction size (16x16 or 20x20)
  - Reaction tooltip shows `:shortcode:` and reactor names
- Sending: `m.annotation` relation with custom emoji MXC URI as key
- Interop consideration: other clients that don't support custom emoji will see the shortcode text or MXC URI

#### 4.5 Message Rendering

- Inline custom emoji in message body
  - Replace `:shortcode:` in rendered messages with emoji image
  - Sized to match line height (~20px inline)
  - "Jumbo" emoji: if message is only 1-3 custom emoji and nothing else, render at 48px
  - Animated emoji: play once on appear, loop on hover/tap
- Handle missing emoji gracefully
  - If emoji pack is from a space the user isn't in, show shortcode as text
  - If MXC URI fails to load, show shortcode as fallback

#### 4.6 Interoperability

- Read emoji packs from other clients that use MSC2545 (Cinny, NeoChat, FluffyChat with Fluffymoji)
- Export packs in standard format for other clients
- Handle Fluffymoji-style global emoji packs (`im.ponies.user_emotes` on account data)
- Degrade gracefully for clients that don't support custom emoji

---

### 5. Sticker Packs (Medium Priority)

**Week 26 | ~3 days**

#### 5.1 Sticker Pack Browsing

- Sticker pack discovery
  - Built-in pack directory (curated list of public Matrix sticker packs)
  - Browse packs from sticker.riot.im/maunium sticker pack format
  - Preview pack contents before installation
  - Pack metadata: name, author, preview images, count
- Space-specific sticker packs (same mechanism as emoji — `im.ponies.room_emotes` with `usage: ["sticker"]`)

#### 5.2 Sticker Pack Installation

- One-tap install: adds pack to user's account data (`im.ponies.user_emotes`)
- Manage installed packs in settings
  - Reorder packs
  - Remove packs
  - Toggle pack visibility
- Storage: sticker images cached locally after first load

#### 5.3 Sticker Picker

- Dedicated sticker button in composer (next to emoji button)
- Grid view of installed stickers, organized by pack
- Pack tabs across the top
- Search stickers by pack name or tag
- Tap sticker to send immediately (no additional confirmation)
- Recently used stickers section

#### 5.4 Timeline Rendering

- Stickers sent as `m.sticker` events (Matrix spec standard)
- Render stickers larger than inline emoji (128x128 to 200x200)
- Stickers displayed without message bubble (floating, like Telegram)
- Animated stickers: play once, tap to replay
- Fallback for clients that don't render stickers: show as image with alt text

---

### 6. GIF Picker (Low Priority)

**Week 26 | ~2 days**

#### 6.1 GIF API Integration

- Integrate Tenor API (primary — free tier is generous, Google-backed)
  - API key management (bundled key for Gloam, user-configurable in settings)
  - Search endpoint with locale awareness
  - Trending endpoint for browse mode
  - Content rating filter (G/PG/PG-13, configurable in settings)
- Fallback: Giphy API as alternative (configurable in settings)
- Privacy consideration: GIF search queries go to third-party API
  - Disclose this in settings with option to disable
  - Option to proxy through homeserver if supported

#### 6.2 GIF Search UI

- GIF button in composer toolbar
- Tap opens GIF panel (similar height to emoji picker)
  - Search bar at top with debounced search (300ms)
  - Trending GIFs displayed by default
  - Results in masonry grid layout
  - GIFs auto-play in preview (muted, low quality)
  - Tap to send
- GIF preview: show full-size before sending (optional, configurable)

#### 6.3 GIF Sending

- Download GIF from Tenor/Giphy
- Upload to Matrix homeserver as media (MXC URI)
- Send as `m.image` event with `info.mimetype: "image/gif"`
- Include `info.thumbnail_info` for progressive loading
- Preserve attribution (Tenor/Giphy branding if required by API ToS)

---

### 7. Space-Wide Moderation (High Priority)

**Weeks 26-27 | ~6 days**

Matrix's biggest operational weakness. Per-room moderation is untenable for community spaces. Gloam makes moderation actually work.

#### 7.1 Space-Wide Ban/Kick

- Ban a user from the entire space with one action
  - Iterate all rooms in space hierarchy, issue ban in each
  - Handle rooms where the moderator doesn't have permission (skip with warning)
  - Ban propagation status UI (progress bar, per-room success/failure)
  - Option to redact recent messages from banned user (configurable: last N messages or time window)
- Space-wide kick: remove from all rooms without ban
- Unban: reverse the process across all rooms
- Implementation: client-side iteration over space rooms
  - Use space hierarchy API (`/hierarchy`) to enumerate all rooms
  - Issue `POST /_matrix/client/v3/rooms/{roomId}/ban` for each
  - Parallel requests with rate limiting (respect homeserver rate limits)
  - Idempotent: skip rooms where user is already banned

#### 7.2 Role-Based Permissions with Visual Hierarchy

- Role management UI in space settings
  - Define custom roles (e.g., Owner, Admin, Moderator, Member, Guest)
  - Map roles to Matrix power levels (100, 75, 50, 0, -1)
  - Visual role badges in member list and message headers
  - Role colors (customizable per role)
  - Drag-and-drop role ordering
- Permission matrix UI
  - Grid view: roles across top, permissions down the side
  - Toggle permissions per role
  - Permissions: send messages, send media, manage emoji, kick, ban, manage rooms, manage space, invite, pin messages
  - Changes propagate to all rooms in space (via power level state events)
- Role assignment
  - Right-click/long-press user > Assign Role
  - Bulk role assignment (select multiple users)
  - Role changes propagate space-wide

#### 7.3 Slow Mode

- Per-room rate limiting for messages
  - Configurable interval: 5s, 10s, 30s, 1m, 5m
  - Client-enforced: disable send button with countdown timer
  - Server-enforced where possible (may need to coordinate with homeserver rate limits)
  - Exempt moderators and above
- Visual indicator in room header when slow mode is active
- Room setting: toggle slow mode on/off with interval picker

#### 7.4 Reporting

- Report message flow
  - Long-press/right-click message > Report
  - Reason categories: Spam, Harassment, NSFW, Illegal, Other
  - Optional description field
  - Submit via `POST /_matrix/client/v3/rooms/{roomId}/report/{eventId}`
- Report dashboard for space admins
  - List of reports with message content, reporter, reason, timestamp
  - Actions: dismiss, warn user, kick, ban (space-wide)
  - Report status tracking (new, reviewed, resolved)
  - Stored in space-level account data or custom room (moderation log room)

#### 7.5 Content Filtering

- Configurable word/regex filters per space
  - Block or flag messages matching filter rules
  - Filter actions: block (prevent send), flag (send but alert mods), redact (auto-remove)
  - Stored as custom state events in space room
- Built-in filter presets
  - Common slurs and hate speech patterns
  - Invite link spam patterns
  - Configurable severity levels
- Client-side enforcement (pre-send check) with server-side backup (redact after send if filter missed)
- Limitations: client-side only — federated users on other clients bypass filters
  - Acknowledge this in UI, recommend server-side solutions (Mjolnir) for comprehensive filtering

#### 7.6 Audit Trail

- Moderation log room per space
  - Automatically created when first moderation action is taken
  - Read-only for non-admins
  - Logs: bans, kicks, role changes, filter modifications, report resolutions, message redactions
  - Each log entry: action, target user, acting moderator, timestamp, reason
  - Structured as Matrix messages for easy display in timeline
- Export audit log (CSV/JSON) for compliance needs

---

### 8. Multi-Account Support (Medium Priority)

**Weeks 27-28 | ~5 days**

Power users and community managers often have multiple Matrix accounts (personal, work, bot management).

#### 8.1 Account Switcher

- Account selector in sidebar/navigation
  - Account avatars stacked vertically below space icons (or above, configurable)
  - Active account highlighted
  - Tap to switch, long-press for account options (settings, logout)
  - "Add Account" button at bottom
- Quick switch gesture: swipe on account avatar or keyboard shortcut (Ctrl+1/2/3)
- Account switch should feel instant (< 500ms)

#### 8.2 Separate Client Instances

- Each account runs its own matrix_dart_sdk `Client` instance
  - Independent sync connections
  - Independent E2EE state (cross-signing keys, device keys)
  - Independent Sliding Sync sessions
- Only the active account syncs at full speed
  - Background accounts: reduced sync frequency or notification-only mode
  - Re-sync fully when switching to a background account
- Resource management
  - Cap total memory usage across all accounts
  - Shared media cache with per-account LRU budgets
  - Shared SQLite database with per-account table prefixes (or separate DB files)

#### 8.3 Unified Notifications

- Notifications from all accounts arrive regardless of active account
  - Notification includes account indicator (avatar or colored dot)
  - Tapping notification switches to the correct account and room
- Notification grouping: group by account, then by room
- Per-account notification settings (separate DND, per-room settings per account)
- Badge counts: sum across all accounts, or per-account breakdown (configurable)

#### 8.4 Per-Account Accent Colors

- Each account can have a distinct accent color
  - Subtle tint on sidebar, message composer, or header when that account is active
  - Helps users maintain awareness of which account is active
  - Default: auto-assigned from a palette, user-customizable
- Account avatar border color matches accent color

#### 8.5 Data Isolation

- Each account's E2EE keys stored in separate keychain entries
  - Key naming: `gloam_account_{user_id_hash}_cross_signing`, etc.
- Per-account SQLite database or schema isolation
  - Message history, room state, search index all isolated
  - No cross-contamination of encrypted content between accounts
- Per-account media cache directory
- Logout of one account clears only that account's data
- "Log out all accounts" option in global settings

---

## Dependencies

### External Dependencies

| Dependency | Status | Risk | Mitigation |
|-----------|--------|------|------------|
| **MatrixRTC spec stability** | MSC stage, production in Element X | Medium | Follow Element X's implementation closely; their usage validates the protocol. Pin to known-working event schemas. |
| **LiveKit Flutter SDK** | Stable, actively maintained | Low | Well-funded project (LiveKit Inc.), Flutter SDK is production-grade. |
| **LiveKit SFU infrastructure** | Requires server deployment | Medium | Default to Element's hosted LiveKit. Document self-hosting. Consider fallback to mesh for 2-3 participant calls. |
| **flutter_webrtc maturity** | Stable on mobile, maturing on desktop | Medium | Mobile is production-ready. Desktop has known issues with screen capture on some Linux DEs. Test early on all platforms. |
| **MSC2545 (custom emoji) adoption** | Community standard, not in spec | Low | Already implemented by multiple clients. Interop is proven. |
| **Tenor/Giphy API availability** | Stable, free tiers available | Low | Tenor is Google-backed, reliable. Giphy as fallback. |

### Internal Dependencies (Prior Phases)

| Dependency | Phase | Required For |
|-----------|-------|-------------|
| Room list and navigation | Phase 2 | Voice channel display in room list |
| E2EE and key management | Phase 1 | Encrypted call signaling |
| Platform-specific integrations | Phase 4 | CallKit, PiP, system tray voice indicator |
| Media handling pipeline | Phase 3 | Custom emoji upload/rendering, stickers, GIFs |
| Notification system | Phase 2 | Multi-account notifications, call notifications |
| Space hierarchy APIs | Phase 2 | Space-wide moderation, space-level emoji |
| Message composer | Phase 1 | Emoji picker integration, GIF/sticker picker |
| Reaction system | Phase 1 | Custom emoji reactions |

---

## Key Decisions

### 1. flutter_webrtc vs Native WebRTC per Platform

**Decision: Use `flutter_webrtc`**

- Provides a single API surface across all 5 platforms
- Mature on iOS and Android (used in production by multiple apps)
- Desktop support is functional, with active improvements
- The alternative (native WebRTC per platform via platform channels) would be 3-5x the integration work
- Risk: desktop screen capture has platform-specific quirks (especially Wayland on Linux)
- Mitigation: test early, file upstream issues, have platform-specific fallback code ready

### 2. SFU vs Mesh for Group Calls

**Decision: LiveKit SFU for 3+ participants, direct peer-to-peer for 1:1**

- Mesh (every participant connects to every other) only works for 2-3 people before bandwidth explodes
- SFU is the only viable approach for 4+ participants
- LiveKit is the SFU that Matrix/Element has standardized on via MatrixRTC
- 1:1 calls use direct peer-to-peer (no SFU overhead, lower latency)
- Threshold: if a 1:1 call gains a third participant, seamlessly migrate to SFU

### 3. Voice Channel State Representation in Matrix

**Decision: MatrixRTC `m.call.member` state events on regular rooms (Option A)**

- Aligns with MatrixRTC's direction for group call participation signaling
- Each participant in the voice channel has an `m.call.member` state event in the room
- Joining = setting your `m.call.member` state event with SFU focus info
- Leaving = removing/clearing your `m.call.member` state event
- Gloam UI interprets rooms with active `m.call.member` events as "voice channels"
- Room type tag (`im.gloam.voice_channel` in room tags or create content) distinguishes voice channels from regular rooms in Gloam's UI
- Other Matrix clients see a room with active MatrixRTC members — degraded but not broken

### 4. Multi-Account Storage Architecture

**Decision: Separate SQLite databases per account**

- Strongest data isolation — no risk of cross-account data leaks
- Simpler migration path (add/remove account = create/delete a database file)
- Trade-off: slightly higher disk usage (schema duplication), but negligible in practice
- Alternative considered: single DB with account ID columns — rejected due to E2EE key isolation complexity and risk of query bugs leaking data across accounts

### 5. Custom Emoji Standard

**Decision: MSC2545 (`im.ponies.room_emotes`)**

- De facto community standard, implemented by Cinny, NeoChat, FluffyChat
- Not yet in the formal Matrix spec, but stable and unlikely to change significantly
- If/when it merges into the spec, migration should be minimal
- Also support `im.ponies.user_emotes` for personal emoji collections

---

## What "Done" Looks Like

### 1:1 Calls
- A user can initiate a voice or video call with any Matrix user
- Call connects within 3 seconds, audio/video quality is good on typical broadband
- Works reliably on all 5 platforms
- PiP works on iOS, Android, and desktop when navigating away
- CallKit (iOS) and ConnectionService (Android) integrate with the system call UI
- Call controls (mute, camera, speaker) work correctly across audio routing changes

### Group Calls
- 3-25 participants in a single call via LiveKit SFU
- Gallery view adapts cleanly to participant count
- Active speaker detection highlights who's talking
- Screen sharing works from desktop, receivable on all platforms
- Quality degrades gracefully on poor networks (resolution drops, then video drops, audio persists)

### Voice Channels
- Rooms can be designated as voice channels in space settings
- Voice channels appear distinctively in the room list with connected participant avatars
- Joining is a single click — no ringing, no call UI
- Connected state persists across app navigation with a persistent bottom bar
- Idle voice channels consume near-zero bandwidth
- Who's talking visualization updates in real-time

### Custom Emoji
- Space admins can upload and manage custom emoji packs
- Custom emoji appear in the emoji picker, searchable by shortcode
- `:shortcode:` autocomplete works in the composer
- Custom emoji render inline in messages and as reactions
- Interoperable with other MSC2545-supporting clients

### Sticker Packs
- Users can browse, install, and send stickers
- Stickers render correctly in the timeline (larger than emoji, no bubble)

### GIF Picker
- Search and trending GIFs available from composer
- GIFs upload to homeserver and render inline

### Space-Wide Moderation
- Banning a user from a space removes them from all rooms in one action
- Roles are visually distinct in member lists and message headers
- Slow mode, reporting, content filtering, and audit trail all functional

### Multi-Account
- Users can log into 2+ accounts and switch between them in < 500ms
- Notifications arrive from all accounts
- Each account has isolated data and distinct visual identity
- Logging out of one account doesn't affect others

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| MatrixRTC schema changes before spec stabilization | Medium | High | Abstract signaling layer; don't couple UI to specific event schemas. Watch Element X releases for breaking changes. |
| LiveKit Flutter SDK bugs on specific platforms | Medium | Medium | Test early on all platforms. Have fallback to audio-only if video pipeline fails. Contribute fixes upstream. |
| Voice channel concept confuses other Matrix clients | Low | Low | Other clients see normal rooms with call state events. Not harmful, just not surfaced as "voice channels." |
| Multi-account doubles resource usage | Medium | Medium | Aggressive background account throttling. Only foreground account syncs fully. Shared media cache. |
| Custom emoji interop edge cases | Low | Low | Follow MSC2545 strictly. Test against Cinny and FluffyChat emoji packs. |
| Screen sharing on Linux Wayland | High | Low | Wayland screen capture requires PipeWire. Detect and guide user. X11 works fine. |

---

## Estimated Effort

| Task | Estimated Days | Weeks |
|------|---------------|-------|
| 1:1 Voice/Video Calls | 8 | 23 |
| Group Voice/Video Calls | 8 | 23-24 |
| Persistent Voice Channels | 8 | 24-25 |
| Custom Emoji per Space | 5 | 25-26 |
| Sticker Packs | 3 | 26 |
| GIF Picker | 2 | 26 |
| Space-Wide Moderation | 6 | 26-27 |
| Multi-Account Support | 5 | 27-28 |
| Integration Testing & Polish | 5 | 28 |
| **Total** | **50 days** | **6 weeks** |

---

## Change History

- 2026-03-25: Initial specification created
