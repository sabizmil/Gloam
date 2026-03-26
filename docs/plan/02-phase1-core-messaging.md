# Phase 1: Core Messaging

**Weeks 5–10 | Milestone: Full encrypted conversation with all basic messaging features**

---

## Objectives

1. Build the message timeline — the central screen of the app — with rich content rendering and virtualized scrolling
2. Implement the message composer with formatting, mentions, file attachments, and voice messages
3. Implement optimistic message sending with local echo and send queue
4. Add reply, edit, delete, and reactions
5. Implement typing indicators and message delivery state indicators
6. Make E2EE invisible — automatic cross-signing verification, key backup, and aggressive key recovery
7. Build the basic room header with room details

## Success Criteria

- [ ] Opening a room with 10,000+ messages renders the latest 50 within 200ms (timeline virtualization)
- [ ] Sending a message appears in the timeline within 100ms (optimistic/local echo)
- [ ] Markdown formatting renders correctly (bold, italic, strikethrough, code, headings, lists, blockquotes, links)
- [ ] Images, files, and video display inline with previews and download capability
- [ ] Voice messages record, display a waveform, and play back
- [ ] Replies show the quoted message inline above the reply
- [ ] Edits update the message in-place with an "(edited)" indicator
- [ ] Deletes remove the message with a "[message deleted]" tombstone
- [ ] Reactions display as pill badges below messages with counts; tapping adds/removes your reaction
- [ ] Typing indicators show in the composer area when other users are typing
- [ ] Message states display: sending (spinner/opacity) → sent (single check) → delivered → read (double check or receipt count)
- [ ] E2EE rooms work without the user ever manually managing keys or verifying devices
- [ ] Zero "Unable to Decrypt" messages in normal usage (existing session with key backup enabled)
- [ ] Room name, topic, and avatar display in the header; member count is visible

---

## Task Breakdown

### 1. Message Timeline Rendering — Complexity: High

**Duration:** 7–9 days

This is the hardest UI component in the app. A chat timeline has unique scroll behavior (anchored to bottom, loads history upward), must handle heterogeneous content types, and must remain smooth at 60fps with thousands of messages.

#### Virtualized SliverList

- Use `CustomScrollView` with `SliverList` and a custom `SliverChildDelegate`
- **Reverse scroll direction** — timeline anchored to bottom, scrolling up loads history
- Only build widgets for visible messages + a buffer of ~20 above and below the viewport
- Implement `itemExtent` estimation for smooth scrollbar behavior (messages vary in height — use running average + content-type heuristics)
- **Pagination:** When the user scrolls near the top of the loaded range, request older messages from the SDK (timeline backfill). Show a subtle loading indicator at the top while fetching.
- **Scroll-to-bottom FAB:** When the user scrolls up more than one viewport height, show a floating "scroll to bottom" button with the unread count badge. Tapping it animates to the bottom.

#### Message Bubble Widget

Each message renders inside a bubble component. The bubble layout varies by sender:

- **Other users:** Avatar (left) + bubble (right of avatar). Sender name colored by deterministic hash. First message in a group shows avatar + name; subsequent messages from the same sender within 3 minutes collapse (no avatar, no name, tighter spacing).
- **Current user:** Bubble aligned right, no avatar, accent background tint.
- **System messages:** Centered, no bubble, muted text. (e.g., "Alice joined the room", "Room name changed to...")

Bubble internals:
- Sender name (when shown) — `bodySmall` weight 600, colored
- Message content — rendered by content-type-specific renderers (see below)
- Timestamp — `bodySmall` muted, right-aligned at bottom of bubble
- Reactions — pill row below the bubble (see Task 5)
- Reply preview — if this message is a reply, show the quoted original above the content (see Task 4)

#### Content Renderers

Each message content type gets a dedicated renderer widget:

| Content Type | Renderer | Details |
|-------------|----------|---------|
| `m.text` | `TextMessageRenderer` | Plain text with selectable text support |
| `m.text` (formatted) | `MarkdownMessageRenderer` | Parse `formatted_body` (HTML) or render Markdown. Bold, italic, strikethrough, headings, lists, blockquotes, links (tappable), inline code (JetBrains Mono), code blocks (syntax highlighting via `highlight` package or similar). |
| `m.image` | `ImageMessageRenderer` | Blurhash placeholder → thumbnail → full resolution on tap. Tap opens a full-screen image viewer with pinch-to-zoom, swipe to dismiss. Show image dimensions and file size. Encrypted images: decrypt in memory before display. |
| `m.file` | `FileMessageRenderer` | File icon + filename + size. Tap to download. Show download progress. Open with system handler after download. |
| `m.video` | `VideoMessageRenderer` | Thumbnail preview with play button overlay. Tap to play inline (or full-screen on mobile). Use `video_player` or `media_kit`. Encrypted video: decrypt to temp file before playback. |
| `m.audio` | `AudioMessageRenderer` | Play button + waveform visualization + duration. For voice messages specifically. |
| `m.emote` | `EmoteRenderer` | "* [sender] [message]" format, italic |
| `m.notice` | `NoticeRenderer` | Muted/italic style to distinguish bot/system notices from user messages |

#### Sender Grouping & Date Separators

- Messages from the same sender within a 3-minute window are grouped — only the first shows the avatar and display name
- If more than 15 minutes pass between messages, insert a timestamp separator (not a full date — just "2:30 PM")
- If a new calendar day starts, insert a date separator pill ("Today", "Yesterday", "Monday, March 20")

#### Scroll-to-Bottom Button

- Appears when the user scrolls more than ~1.5 viewport heights from the bottom
- Shows unread count badge if new messages arrived while scrolled up
- Tapping animates to the bottom with a spring curve
- Disappears when the user is at/near the bottom

**Output:** A smooth, virtualized message timeline that renders all content types, groups messages by sender, paginates history, and stays at 60fps.

---

### 2. Message Composer — Complexity: High

**Duration:** 6–8 days

The composer is the most interacted-with component. It must feel responsive, support rich input, and adapt to context (replying, editing, attaching).

#### Base Composer

- Multi-line text input field with auto-expanding height (min 1 line, max ~6 lines before scrolling internally)
- Send button (right side) — enabled only when input is non-empty or an attachment is staged
- The text field uses `bodyLarge` (Inter 15px) with `textPrimary` color on `backgroundSurface`

#### Markdown Toolbar

A horizontal toolbar above the text field (desktop) or above the keyboard (mobile) with formatting buttons:

| Button | Action | Keyboard Shortcut |
|--------|--------|-------------------|
| **B** | Wrap selection in `**bold**` | Cmd/Ctrl+B |
| *I* | Wrap selection in `*italic*` | Cmd/Ctrl+I |
| ~~S~~ | Wrap selection in `~~strikethrough~~` | Cmd/Ctrl+Shift+X |
| `<>` | Wrap selection in `` `inline code` `` | Cmd/Ctrl+E |
| `[]` | Insert code block (triple backtick) | Cmd/Ctrl+Shift+E |
| `>` | Prefix line with `> ` (blockquote) | Cmd/Ctrl+Shift+. |
| `-` | Prefix line with `- ` (list item) | — |
| `1.` | Prefix line with `1. ` (ordered list) | — |

Toolbar is collapsible on mobile to save vertical space.

#### Slash Commands

Typing `/` at the start of a message opens an autocomplete overlay:

| Command | Action |
|---------|--------|
| `/me [text]` | Send as emote (m.emote) |
| `/shrug` | Append `¯\_(ツ)_/¯` |
| `/tableflip` | Append `(╯°□°)╯︵ ┻━┻` |
| `/plain [text]` | Send without Markdown formatting |
| `/spoiler [text]` | Send as spoiler |
| `/nick [name]` | Change display name |
| `/topic [text]` | Set room topic (if permitted) |
| `/invite @user:server` | Invite user to room |

Autocomplete dropdown shows matching commands with descriptions as the user types.

#### @Mentions

Typing `@` opens a member autocomplete overlay:
- Shows room members filtered by display name and user ID as the user types
- Each item shows avatar + display name + user ID
- Selecting a member inserts a pill (styled inline span) that resolves to a Matrix mention (`<a href="https://matrix.to/#/@user:server">Display Name</a>` in formatted_body)
- Mention pills are non-editable inline elements — backspace deletes the entire pill

#### Emoji Shortcodes

Typing `:` followed by at least 2 characters opens an emoji autocomplete:
- Search Unicode emoji by shortcode (`:thumbsup:` → :thumbsup:, `:fire:` → :fire:)
- Show emoji glyph + shortcode in dropdown
- Selecting inserts the Unicode emoji character
- Frequently used emoji appear first

#### File Picker & Camera

- **Attachment button** (paperclip icon) opens a bottom sheet (mobile) or dropdown (desktop):
  - "Photo/Video" — opens system photo picker
  - "Camera" — opens camera for capture (mobile only)
  - "File" — opens system file picker
- Selected files show as a preview strip above the composer (thumbnail for images/video, icon + filename for files)
- Multiple files can be staged before sending
- Remove button (x) on each staged attachment
- File size validation — warn if a file exceeds the homeserver's `m.upload.size` limit
- Upload progress indicator when sending

#### Voice Recording

- **Microphone button** replaces the send button when the text field is empty
- Tap and hold to record (or tap to toggle recording mode)
- While recording: show elapsed time, animated waveform, and a cancel/delete button
- Release (or tap stop) to stage the voice message
- Staged voice message shows waveform preview and duration, with play and delete buttons
- Encode as Opus in OGG container (`m.audio` with `org.matrix.msc1767.audio` for waveform data)
- Waveform data: sample the audio amplitude at ~100 points and include in the event content for recipients to render the waveform without downloading the file

#### Reply-To Bar

When the user invokes "reply" on a message (via context menu or swipe):
- A "Replying to [sender]" bar appears above the composer with the quoted message preview (truncated to 1–2 lines)
- An "x" button to cancel the reply
- The reply bar shifts the composer up, keeping the text field in the same position relative to the keyboard
- When sent, the message includes `m.relates_to` with `m.in_reply_to` pointing to the original event

#### Edit Mode

When the user invokes "edit" on their own message:
- The composer populates with the original message text
- A "Editing" indicator bar appears above the composer (similar to reply bar) showing the original message
- The send button changes to a checkmark icon
- Sending submits an `m.replace` relation event
- Pressing Escape or tapping "x" cancels the edit and restores the previous composer state

#### Keyboard Shortcuts (Desktop)

| Shortcut | Action |
|----------|--------|
| Enter | Send message |
| Shift+Enter | New line |
| Up Arrow (empty composer) | Edit last sent message |
| Escape | Cancel reply/edit, clear composer |

**Output:** A full-featured message composer that supports formatting, mentions, emoji, file/voice attachments, reply-to, edit mode, and keyboard shortcuts.

---

### 3. Optimistic Message Sending — Complexity: Medium

**Duration:** 3–4 days

Messages must appear instantly in the timeline when the user hits Send. The server round-trip happens in the background.

#### Local Echo Flow

```
User taps Send
  1. Generate a local transaction ID (txnId)
  2. Create a LocalEchoMessage with txnId, content, timestamp = now
  3. Insert into timeline immediately (renders with "sending" state)
  4. Enqueue in the send queue
  5. Send queue submits to homeserver via SDK
  6. On success:
     a. Server returns the real event ID
     b. Replace txnId with real event ID in the timeline
     c. Update state to "sent"
     d. When delivery receipt arrives → "delivered"
     e. When read receipt arrives → "read"
  7. On failure:
     a. Update state to "failed"
     b. Show retry button on the message
     c. Tapping retry re-enqueues in the send queue
```

#### Send Queue

- FIFO queue per room — messages in the same room are sent in order
- Messages to different rooms can send in parallel
- Queue persists to SQLite so messages survive app restart
- On reconnection, the queue automatically resumes
- Failed messages stay in the queue with exponential backoff (1s, 2s, 4s, max 30s)
- User can manually retry or discard a failed message

#### Deduplication

- When the real event arrives via sync, match it to the local echo by `txnId`
- Replace the local echo in the timeline (same position) with the server-confirmed event
- If the sync event arrives before the send callback returns, handle gracefully (don't show the message twice)

#### Visual States

| State | Visual Treatment |
|-------|-----------------|
| Sending | Message at reduced opacity (0.7), subtle spinner or pulsing dot next to timestamp |
| Sent | Full opacity, single checkmark icon (muted color) |
| Delivered | Double checkmark icon (muted color) — based on server receipt |
| Read | Double checkmark icon (accent color) — based on read receipt |
| Failed | Full opacity, red warning icon, "Failed to send. Tap to retry." label |

**Output:** Messages appear instantly in the timeline when sent. The user sees clear visual feedback for send/deliver/read states. Failed messages are recoverable.

---

### 4. Reply, Edit, Delete — Complexity: Medium

**Duration:** 3–4 days

#### Reply

- **Trigger:** Long-press (mobile) or right-click (desktop) → "Reply" in context menu. Or swipe-right on a message (mobile).
- **Display:** The original message renders as a compact quote block above the reply content:
  - Accent-colored left border (4px)
  - Sender name + truncated content (1 line max)
  - Tapping the quote scrolls to and highlights the original message in the timeline
- **Data:** `m.relates_to` with `rel_type: "m.in_reply_to"` and the original `event_id`

#### Edit

- **Trigger:** Long-press/right-click → "Edit" (only on own messages). Or Up Arrow in empty composer to edit last message.
- **Display:** The message updates in-place. An "(edited)" label appears in muted text next to the timestamp. No edit history in Phase 1 (P2 feature).
- **Data:** New event with `m.relates_to` → `rel_type: "m.replace"` and the original `event_id`. Content is the new body.
- **SDK:** matrix_dart_sdk supports `room.sendTextEvent()` with edit relation. The SDK's timeline automatically replaces the original event content.

#### Delete (Redaction)

- **Trigger:** Long-press/right-click → "Delete" (own messages) or "Remove" (moderator action on others' messages). Confirmation dialog: "Delete this message? This can't be undone."
- **Display:** Message content replaced with "[message deleted]" in muted italic. Sender name still visible. Reactions are removed.
- **Data:** `m.room.redaction` event targeting the original event ID.
- **Permissions:** Users can always redact their own events. Moderators (power level >= 50 by default) can redact others' events.

#### Context Menu

Long-press (mobile) or right-click (desktop) on a message shows:

| Action | Shown When | Icon |
|--------|-----------|------|
| Reply | Always | Reply arrow |
| React | Always | Smiley face |
| Edit | Own messages only | Pencil |
| Delete | Own messages or moderator | Trash |
| Copy Text | Text messages | Copy |
| Select | Always | Checkbox |
| View Source | Debug/developer mode | Code brackets |

Desktop: Context menu is a floating menu at the cursor position.
Mobile: Bottom sheet with the message preview at the top and action rows below.

**Output:** Users can reply to, edit, and delete messages with the interactions feeling natural on both mobile and desktop.

---

### 5. Reactions — Complexity: Medium

**Duration:** 3–4 days

#### Emoji Picker

- Triggered from context menu "React" or from a quick-react bar
- **Quick-react bar:** On hover (desktop) or long-press (mobile), show a floating bar with 6 frequently used emoji above the message. Tapping one sends the reaction immediately.
- **Full emoji picker:** Accessed from the "+" button at the end of the quick-react bar, or from context menu
  - Category tabs: Smileys, People, Nature, Food, Activities, Travel, Objects, Symbols, Flags
  - Search field at top — filters emoji by name/shortcode
  - Frequently Used section at the top
  - Skin tone selector (modal or long-press on applicable emoji)
  - Grid layout, ~8 columns
  - Recent selections persist to local storage

#### Reaction Display

- Reactions render as a row of pill-shaped badges below the message bubble
- Each pill shows: emoji glyph + count (e.g., "👍 3")
- If the current user has reacted with that emoji, the pill has an accent border/background
- Tapping a pill toggles the current user's reaction (add if not reacted, remove if already reacted)
- Pills are sorted by count (descending), then by first-reaction time
- If more than 8 unique reactions, show the first 7 + a "+N" overflow pill. Tapping overflow shows all reactions in a bottom sheet with sender names.

#### Skin Tone Support

- Default skin tone is stored per user (local preference)
- Long-pressing an applicable emoji in the picker shows a skin tone palette (6 options)
- Selected skin tone becomes the new default for future reactions

#### Data Model

- Reactions are `m.reaction` events with `m.relates_to` → `rel_type: "m.annotation"`, `event_id: [target]`, `key: [emoji]`
- Aggregation: The SDK aggregates reactions. The UI reads aggregated reaction counts from the event's annotations.
- Redacting a reaction removes the annotation

**Output:** Users can react to messages with any emoji, see reaction counts, toggle their own reactions, and access a full emoji picker with search and skin tones.

---

### 6. Typing Indicators & Delivery Receipts — Complexity: Low

**Duration:** 2–3 days

#### Typing Indicators

**Sending:**
- Debounce: Send `m.typing` → `true` when the user types, with a 3-second timeout
- If the user stops typing for 3 seconds, send `m.typing` → `false`
- Also send `false` immediately when the message is sent or the composer is cleared

**Displaying:**
- Show a typing bar below the last message (above the composer) when other users are typing
- Format: "[Alice] is typing...", "[Alice] and [Bob] are typing...", "Several people are typing..."
- Animated dots (...) with a subtle bounce animation
- Typing indicator auto-dismisses after the server timeout (30 seconds) if no update arrives
- Do not show the current user's own typing indicator

#### Delivery Receipts

**Message States:**

The delivery state for sent messages is displayed via small icons/indicators next to the message timestamp:

| State | Trigger | Indicator |
|-------|---------|-----------|
| Sending | Local echo created, not yet confirmed by server | Faded clock icon or spinner dot |
| Sent | Server acknowledged the event (200 response or event appears in sync) | Single checkmark, muted color |
| Delivered | At least one other user's client has received the event (delivery receipt) | Double checkmark, muted color |
| Read | At least one other user has sent a read receipt for this event | Double checkmark, accent color |

**In DMs:** Show the specific read receipt state (read = the other person has seen it).

**In groups:** Show aggregate — "Read by N" on tap/hover of the read indicator. Full list of readers available in a tooltip or bottom sheet.

**Read receipt sending:**
- Send read receipt when a room is opened and the latest message is visible
- Update read receipt as the user scrolls through new messages
- Use `m.read` receipt type (public) by default
- Support `m.read.private` (MSC2285) for private read receipts if enabled in settings

**Output:** Users see who's typing in real-time and get clear visual feedback on whether their messages were sent, delivered, and read.

---

### 7. Invisible E2EE — Complexity: High

**Duration:** 8–10 days

This is the highest-risk task in Phase 1. The goal is Signal-level encryption invisibility — the user should never think about encryption, keys, or verification. It should just work.

#### Automatic Cross-Signing Setup

On account creation (handled in Phase 0, but verified/hardened here):
1. Generate master, self-signing, and user-signing cross-signing keys
2. Upload to homeserver's secret storage (SSSS — Secure Secret Storage and Sharing)
3. Sign the current device with the self-signing key
4. All of this happens silently — no user interaction

On new device login:
1. Attempt to verify the new session via an existing session (QR code or emoji comparison)
2. If no other session is online, fall back to recovery phrase
3. If recovery phrase is entered, download cross-signing keys from SSSS and sign the new device
4. The device is now verified and trusted — it can decrypt all messages

#### QR Code Verification

When a new device needs verification from an existing session:
1. Both devices show a QR code and a "Scan" button
2. Device A scans Device B's QR code (or vice versa)
3. The protocol (MSC4108 ECIES-based rendezvous) handles key exchange
4. Both devices confirm the verification succeeded
5. The new device receives cross-signing keys and is marked as verified

UI: A simple screen with the QR code, a camera viewfinder for scanning, and a progress indicator. One screen, one action, done. No confusing shield icons or verification prompts.

If QR scanning isn't possible (e.g., verifying a desktop from a desktop), fall back to emoji comparison:
1. Both devices show the same set of 7 emoji
2. User confirms they match on both devices
3. Verification complete

#### Recovery Phrase

- Generated during account creation (Phase 0): 12-word BIP39-style mnemonic
- Encrypts cross-signing keys and key backup secret
- Stored in platform keychain as a safety net
- If the user loses all devices, the recovery phrase is the only way to restore message history
- UI for entering recovery phrase: 12 text fields with autocomplete suggestions from the BIP39 word list

#### Automatic Key Backup

Key backup ensures that Megolm session keys are backed up to the homeserver (encrypted with the backup key derived from the recovery phrase). This is critical for message recovery on new devices.

1. Enable key backup automatically during account setup
2. Back up every new Megolm inbound session key as it's received
3. On new device login, after cross-signing verification, automatically restore all keys from backup
4. Restoration happens in the background — rooms show a brief "Loading message history..." state, then messages appear

#### Aggressive Key Request Strategy

When a message can't be decrypted (missing Megolm session key):

1. **First:** Check the local key backup cache
2. **Second:** Request the key from the server-side backup
3. **Third:** Send an `m.room_key_request` to all other verified sessions
4. **Fourth:** Wait up to 10 seconds for a response
5. **Fifth:** If still missing, show the message as "Message from [sender] — content unavailable" with a "Retry" button — **never** show "Unable to Decrypt" or any cryptographic error text

The key request should happen proactively when a room is opened — pre-fetch keys for the visible timeline range before attempting to decrypt.

#### "Unable to Decrypt" Mitigation

This is the Matrix ecosystem's most hated error. Gloam's strategy:

- **Prevention:** Automatic key backup + automatic backup restore + aggressive key requests
- **Pre-fetching:** When a room is selected, request keys for the visible timeline window before rendering messages
- **Graceful degradation:** If a message truly can't be decrypted after all attempts:
  - Show: "Message from [sender name] — content unavailable"
  - Do NOT show: "Unable to Decrypt", "UISI", "Megolm session not found", or any cryptographic terminology
  - Show a small "retry" link that re-attempts key request
  - In the background, continue retrying key requests periodically (every 5 minutes for the first hour, then hourly)

#### Background Crypto Isolate

E2EE operations (encrypting outgoing messages, decrypting incoming messages, Megolm session management, key backup operations) should not block the UI thread.

- Run vodozemac operations on a separate Dart isolate
- Use `Isolate.spawn` with a message-passing interface
- The crypto isolate holds the Olm/Megolm state and processes operations from a queue
- Results are passed back to the main isolate and into the Riverpod state layer

If isolate overhead is problematic for the volume of operations, consider `compute()` for individual heavy operations instead of a persistent isolate — profile and decide.

**Output:** E2EE is invisible. New accounts get automatic cross-signing. New devices verify via QR code or recovery phrase in one step. Messages decrypt reliably. The user never sees "Unable to Decrypt" in normal operation.

---

### 8. Basic Room Details — Complexity: Low

**Duration:** 2–3 days

Phase 1 scope is minimal — just enough information in the room header and a basic details panel.

#### Room Header

The header bar at the top of the message timeline:

| Element | Details |
|---------|---------|
| Room avatar | 32px circular, left side. Fallback to first letter on colored background. |
| Room name | `displayMedium` (Spectral 22px). Truncate with ellipsis if too long. |
| Room topic | `bodySmall` muted, below the name. Single line, truncated. Tap to expand (tooltip on desktop). |
| Member count | "N members" in `bodySmall` muted, right-aligned. Tapping opens member list (Phase 2 feature — for now, just display the count). |
| Encryption badge | Small lock icon next to the room name if the room is encrypted. No tooltip or explanation — it's just there. |
| Back button | Left arrow (mobile only) — navigates back to room list. |

#### Room Details Panel (Minimal)

Tapping the room name or a dedicated info button opens a right-side panel (desktop) or pushes a new screen (mobile):

- Room avatar (large, 80px)
- Room name (editable if user has permission)
- Room topic (full text, editable if permitted)
- "N members" with a list preview (first 5 avatars)
- Encryption status: "Messages in this room are encrypted" or "Messages in this room are not encrypted"
- "Leave Room" button (with confirmation dialog)

Full room settings, member management, permissions, and notification controls are deferred to Phase 2.

**Output:** The room header shows the essential room information. A minimal details panel provides room name, topic, member count, and leave functionality.

---

## Dependencies & Blockers

| Dependency | Required By | Risk |
|------------|-------------|------|
| Phase 0 complete (room list, auth, SDK integration, theme) | All tasks | Blocking — Phase 1 builds on Phase 0 infrastructure |
| matrix_dart_sdk timeline API | Task 1 | Low — well-established API in the SDK |
| matrix_dart_sdk send queue | Task 3 | Low — built-in feature |
| vodozemac cross-signing support | Task 7 | Low — shipped in matrix_dart_sdk v1.0 |
| Emoji dataset (Unicode CLDR) | Task 5 | Low — use `emoji_picker_flutter` or bundle CLDR data |
| Audio recording package | Task 2 (voice messages) | Medium — evaluate `record` or `flutter_sound` packages |
| Video playback package | Task 1 (video renderer) | Medium — evaluate `media_kit` or `video_player` |

## Key Technical Decisions to Make During Phase 1

| Decision | Options | Recommendation | Decide By |
|----------|---------|----------------|-----------|
| Markdown rendering library | `flutter_markdown`, `flutter_html`, custom parser | `flutter_html` for rendering Matrix `formatted_body` (which is HTML), with a custom sanitizer | Week 5 |
| Video player package | `video_player` (Flutter team), `media_kit` (community) | `media_kit` — better codec support, desktop performance, and active maintenance | Week 5 |
| Audio recording package | `record`, `flutter_sound`, `audio_waveforms` | `record` for capture + `audio_waveforms` for visualization — lightweight, well-maintained | Week 6 |
| Emoji picker | `emoji_picker_flutter`, custom-built | `emoji_picker_flutter` as a base, with custom styling to match Gloam's design system | Week 7 |
| Crypto isolate vs. compute() | Persistent isolate, per-operation compute() | Start with compute() for individual operations; move to persistent isolate if profiling shows overhead | Week 8 |
| Image viewer | `photo_view`, `easy_image_viewer`, custom | `photo_view` — mature, supports pinch-to-zoom and swipe-to-dismiss | Week 5 |

---

## What "Done" Looks Like

At the end of Week 10, a tester can:

1. Open any room from the room list and see messages load within 200ms
2. Scroll up through message history smoothly (60fps) with automatic pagination
3. See rich content: formatted text (bold, italic, code blocks), images (with full-screen viewer), files (with download), videos (with inline playback), voice messages (with waveform playback)
4. Compose and send messages with Markdown formatting, @mentions, emoji shortcodes, and slash commands
5. Attach and send images, files, and voice recordings
6. See their sent messages appear instantly (optimistic) with clear sent/delivered/read indicators
7. Reply to messages (with inline quote), edit their own messages, and delete messages
8. React to messages with emoji, see reaction counts, and toggle their own reactions
9. See typing indicators when other users are typing
10. Send and receive messages in encrypted rooms with zero manual key management
11. Verify a new device via QR code scan — one screen, one action, done
12. See the room name, topic, avatar, and member count in the header

What they **cannot** do yet: navigate between spaces, use threads, search messages, make voice/video calls, manage room settings beyond leaving, or customize notifications. That's Phase 2+.
