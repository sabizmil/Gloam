# Discord Voice & Call Features — Research Document

*Compiled: 2026-03-26*

This document is a comprehensive breakdown of every voice-related feature Discord offers, organized by category. It serves as the competitive reference for Gloam's voice support implementation.

---

## 1. Voice Channels (Server/Guild Context)

### Always-On Model

Voice channels are **persistent** — they exist whether anyone is in them or not. There is no "starting" or "ending" a call. Users simply join and leave. This is fundamentally different from the ring-to-call model used in DMs.

- **Join**: Click a voice channel name. You are immediately connected. Others see you appear in real time.
- **Leave**: Click disconnect or join another channel. You disappear instantly.
- **No ringing**: Joining does not ring or notify anyone. It is a passive, ambient model.
- **Navigation-independent**: Once connected, you stay connected even when navigating to other text channels, other servers, or DMs. The voice connection is decoupled from UI focus.
- **AFK channel**: Servers can configure an AFK channel and idle timeout. Idle users are auto-moved or disconnected.

### Channel Capacity

- **Default**: Unlimited participants.
- **Configurable**: Admins can set a limit from 0 (unlimited) to 99 per channel.
- **Bypass**: Users with "Move Members" or Admin permissions can join full channels.
- **Visual**: Shows count when limited (e.g., "3/5" next to channel name).

### Voice Channel UI — Sidebar

The voice channel in the server's channel list shows every connected user nested beneath it:

| Indicator | Appearance | Meaning |
|-----------|-----------|---------|
| Green ring on avatar | Animated glow | User is actively speaking |
| Grey mic-slash icon | Next to name | Self-muted |
| Grey headphone-slash | Next to name | Self-deafened |
| Red mic-slash | Next to name | Server-muted by moderator |
| Red headphone-slash | Next to name | Server-deafened by moderator |
| Camera icon | Next to name | Camera enabled |
| Monitor icon | Next to name | Screen sharing |
| "LIVE" badge | Next to name | Go Live streaming |

### Stage Channels

A structured speaker/audience model for presentations, AMAs, and events:

- **Speakers** appear on "stage" and can transmit audio.
- **Audience** is muted by default — listen only.
- **Request to Speak**: Audience members raise their hand. Moderators approve/deny.
- **Scheduled Events integration**: Events can be announced in advance.
- **Scale**: 1,000+ audience members at higher boost tiers.

### The Persistent Voice Connection Bar

This is one of Discord's most important UX patterns. A bar appears at the **bottom-left** of the client whenever connected to voice:

**Contents:**
- Channel name and server name
- Connection duration timer
- Connection quality indicator (green/yellow/red)

**Controls on the bar:**
- Mute/unmute mic toggle
- Deafen/undeafen toggle
- Screen share button
- Camera toggle
- Activities button
- Soundboard button
- Disconnect button

**Key property**: This bar is visible **regardless of current navigation**. You can be in a completely different server's text channel and still see and control your voice state. Clicking the channel name navigates back to the voice channel view.

### Screen Sharing

- Users with "Video" permission can share their screen.
- **Share modes**: Specific application window or entire screen.
- **Quality tiers** (gated by subscription):
  - Free: 720p / 30fps
  - Nitro Classic: 1080p / 60fps
  - Nitro: Up to 4K / 60fps
- **Multiple simultaneous shares**: Multiple users can screen share at once.
- **Audio sharing**: Desktop users can share application/system audio alongside screen.
- **Stream preview**: Thumbnails of active shares appear in the voice channel UI.

### Video in Voice Channels

- Users can enable webcams alongside voice.
- **Grid view**: Multiple camera feeds displayed in a grid.
- **Focus view**: Click a user's video to enlarge it.
- **Simultaneous**: Camera + screen share can run together (PiP style).
- **Limit**: Up to 25 simultaneous video streams per channel.

### Go Live / Streaming

- Discord's term for streaming gameplay or screen to a voice channel.
- **Game detection**: Automatically labels streams with the detected game name.
- **Viewer limit**: Up to 50 viewers per stream.
- **Controls**: Streamer can pause, change source, adjust quality.
- **Viewer experience**: Pop-out window, fullscreen, independent volume slider for stream audio.

### Voice Channel Status & Activities

- **Channel status**: Admins can set a text status (e.g., "Movie Night") displayed below the channel name.
- **Embedded Activities**: Interactive apps (YouTube Watch Together, games, whiteboard) run inside voice channels. All participants can join the shared experience.
- **Soundboard**: Custom short audio clips that play for all participants. Servers upload their own sound effects.

### Text-in-Voice

Each voice channel has an associated text chat:
- Appears when you join a voice channel.
- Messages visible only to those in the voice channel.
- Messages persist but are contextually tied to the voice session.

---

## 2. Direct Calls (DM Context)

### 1:1 Voice Calls

- **Initiation**: Click the phone icon in a DM header.
- **Ring model**: Recipient's client rings (audible ringtone + visual overlay) until they answer, decline, or it times out (~60-80 seconds).
- **One-click answer**: Accept (green) and Decline (red) buttons.
- **No voicemail**: Missed calls show as a system message in the DM.

### Group DM Calls

- Group DMs support up to 10 users.
- Any member can start a call — it rings all others.
- **Late join**: If a call is ongoing, a green "Join Call" button appears in the DM header. No re-ringing for late joins.
- **Persistence**: The call continues as long as at least one person remains connected.

### Ring/Notification Behavior

| Platform | Behavior |
|----------|----------|
| Desktop | Full overlay with ringtone sound |
| iOS | Push notification via CallKit (appears as native phone call) |
| Android | High-priority push notification |
| Multi-device | All devices ring simultaneously; answering one stops others |
| DND mode | Suppresses ring; missed call record still created |

### Call UI States

| State | What the User Sees |
|-------|-------------------|
| Ringing (outgoing) | Recipient's avatar, "Ringing..." text, hang-up button |
| Ringing (incoming) | Caller's avatar, Accept/Decline buttons, ringtone plays |
| Connected | Participant avatars, speaking indicators, duration timer, control bar |
| Ended | "Call Ended" message; system message posted to DM with duration |
| Missed | "Missed Call" system message in DM chat history |

### Video & Screen Share in DMs

- Either participant can toggle video during a voice call.
- Both cameras can run simultaneously.
- Screen sharing available in 1:1 and group DM calls.
- Same quality tiers and functionality as server voice channels.

---

## 3. Voice UX Details

### Input Mode: Voice Activity vs Push-to-Talk

**Voice Activity (default):**
- Mic transmits when audio exceeds a configurable sensitivity threshold.
- Threshold slider in settings for fine-tuning.

**Push-to-Talk:**
- Mic only transmits while a designated key is held.
- Configurable keybind (any key or combo).
- Optional "Release Delay" (configurable in ms) — prevents cutting off words.
- Client-side setting, not per-channel.

### Noise Suppression (Krisp)

- Built-in Krisp AI noise cancellation.
- Toggleable from Voice & Video settings or the voice bar.
- Suppresses keyboards, fans, construction, pets, etc.
- Free for all users. Runs client-side.

### Audio Device Management

- **Input device**: Dropdown of detected microphones (or "Default").
- **Output device**: Dropdown of detected speakers/headphones (or "Default").
- **Input volume slider**: Controls mic level.
- **Output volume slider**: Controls speaker level.
- **Mic test**: Record and playback to verify mic works.
- **Separate notification output**: Different audio device for Discord notifications vs voice.

### Per-User Volume

- Right-click any user in voice -> volume slider (0% to 200%).
- Local-only setting (only affects what you hear).
- Separate volume slider for screen share/stream audio.

### Voice Processing Settings

| Setting | Purpose |
|---------|---------|
| Echo Cancellation | Prevents feedback loops when using speakers |
| Noise Reduction | Legacy/standard noise reduction (separate from Krisp) |
| Automatic Gain Control (AGC) | Normalizes mic volume — boosts quiet, reduces loud |
| QoS High Packet Priority | Tells router to prioritize voice packets |
| Attenuation | Reduces other app volumes when speaking or others speak (0-100%) |

### Keybinds

- Configurable in Settings > Keybinds.
- **Global hotkeys**: Work outside the Discord window (critical for gaming).
- Keybinds for: Toggle Mute, Toggle Deafen, Push to Talk, Toggle Screen Share.
- Multiple keybinds per action.

### Disconnect Behavior

- **Single-click disconnect**: Immediate, no confirmation dialog.
- **No auto-rejoin**: Must manually rejoin after disconnect.
- **Close behavior**: Configurable — minimize to tray vs quit. Quitting disconnects from voice.
- **Network disconnect**: Automatic reconnection attempted. Shows "RTC Connecting" / "Reconnecting..." for ~15-30 seconds before giving up.

---

## 4. Permissions and Moderation

### Voice Channel Permissions

| Permission | Effect |
|-----------|--------|
| Connect | Can join the voice channel |
| Speak | Can transmit audio (denied = forced mute) |
| Video | Can use camera or share screen |
| Use Voice Activity | If denied, forced to Push-to-Talk |
| Priority Speaker | Audio boosted, others attenuated when speaking |
| Mute Members | Can server-mute others |
| Deafen Members | Can server-deafen others |
| Move Members | Can drag members between channels or disconnect them |
| Use Soundboard | Can play soundboard clips |
| Use External Sounds | Can use soundboard sounds from other servers |
| Use Embedded Activities | Can launch activities in voice |
| Request to Speak | Can raise hand in Stage Channels |

All permissions are configurable per-role and per-user on each channel. Channels inherit from their parent category by default.

### Server Mute vs Self Mute

| Type | Who Controls | Icon Color | Can User Undo? |
|------|-------------|-----------|----------------|
| Self mute | User | Grey | Yes |
| Server mute | Moderator | Red | No — only a moderator can remove |
| Self deafen | User | Grey | Yes |
| Server deafen | Moderator | Red | No |

Server mute/deafen **persists** across leave/rejoin — it sticks until a moderator removes it.

### Priority Speaker

- A role permission or per-channel override.
- When a priority speaker talks, everyone else's audio is automatically attenuated.
- Useful for classroom, presentation, or leadership scenarios.

---

## 5. Quality and Technical

### Audio

- **Codec**: Opus (open-source, low-latency, adaptive bitrate).
- **Bitrate per channel** (configurable by admins):
  - No boosts: Up to 96 kbps
  - Level 1 (2 boosts): Up to 128 kbps
  - Level 2 (7 boosts): Up to 256 kbps
  - Level 3 (14 boosts): Up to 384 kbps

### Server Infrastructure

- **Automatic region selection**: Optimal voice server chosen based on participant locations.
- **Manual override**: Channel editors can set region per channel (US East, Europe, etc.).
- **Dynamic switching**: Discord can move the voice server if conditions change.
- Voice servers are dedicated real-time media servers, separate from the guild/chat servers.

### Connection Quality

- **Indicators**: Green (good), Yellow (moderate), Red (poor).
- **Diagnostic panel** (click quality indicator): Server region, ping (ms), average ping, packet loss %, codec in use, voice server endpoint.

### Reconnection

- **Automatic**: Brief network interruptions are handled transparently.
- **Visual state**: "RTC Connecting" / "Reconnecting..." shown in voice bar.
- **Timeout**: ~15-30 seconds of sustained failure before full disconnect.
- **Other participants unaffected**: One user dropping doesn't interrupt others.

---

## 6. Notifications and Status

### Who's in Voice — Visibility

- **Channel sidebar**: Connected users listed under the channel name with all status icons.
- **User profile/popout**: Shows "In Voice Channel: [name]" contextually.
- **No persistent badge in text member list**: Being in voice shows primarily in the voice channel sidebar.

### Call Notifications (DMs)

- **Multi-device**: All devices ring simultaneously. Answering one stops others.
- **iOS CallKit**: Appears as a native phone call on lock screen.
- **Android**: High-priority notification with ringtone.
- **Distinct ringtones**: Different sounds for incoming calls, outgoing calls, and call connection — these are iconic, recognizable sounds.

### Call History

- **System messages in DM**: "[User] started a call that lasted X minutes."
- **Missed calls**: "Missed Call" system message with timestamp.
- **No explicit call log**: The chat history IS the call log.

---

## 7. Key Architectural Insights for Competitive Planning

1. **Two distinct models**: Always-on ambient voice channels (servers) vs ring-to-call (DMs). These feel completely different and serve different use cases. Both are essential.

2. **Persistent voice bar**: The decoupling of voice connection from UI navigation is foundational. Users stay in voice while browsing elsewhere. This is non-negotiable for parity.

3. **Granular permissions**: Speak, Connect, Video, Priority Speaker, and moderation permissions are all independent and deeply integrated — not bolted on.

4. **Voice channels as social spaces**: Soundboard, Activities, Text-in-Voice transform voice from communication into ambient hangout spaces. This is what makes Discord sticky.

5. **Mobile-native integration**: CallKit (iOS) and persistent notifications (Android) make voice work well on mobile with OS-level integration.

6. **Stage Channels**: A distinct one-to-many broadcast model, separate from regular voice channels. Important for communities.

7. **Per-user volume control**: Small but essential UX detail — users can individually balance how loud each person is.
