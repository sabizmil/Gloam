# Changelog

## v0.3.0

### Threads & Replies
- **Reply pills** — Replies now show as compact, clickable pills with the sender's avatar, name, and a snippet of the original message. Clicking a pill scrolls to and highlights the original message.
- **Proper threading** — Thread replies use the Matrix `m.thread` relation type and are filtered out of the main timeline. A thread indicator with participant avatars, reply count, and last reply time appears below threaded messages.
- **Refined thread panel** — The right-side thread panel now shows participant avatars, metadata (reply and participant counts), and an enhanced composer with a send button.
- **Reply fallback stripped** — The `> quoted text` fallback that Matrix embeds in reply bodies is now removed, so you only see the actual reply content.

### Presence & Activity
- **"Following the conversation" bar** — A subtle strip below the chat header shows when another user's read receipt matches the latest message, with their avatar, name, and a relative timestamp ("just now", "2m ago").

### Clipboard & Files
- **Paste to upload** — Press Cmd+V to paste screenshots or files from the clipboard directly into the chat. Supports images (from screenshots or browser copies) and files (copied from Finder).
- **File download** — Clicking the download icon on file messages now works. A native save dialog appears on desktop, files are downloaded and decrypted from the homeserver, and the icon transitions through downloading/complete/error states.

### Theming
- **Full theme switching** — Three theme variants (Gloam Dark, Midnight, Dawn) with smooth animated transitions between them.
- **Accent colors** — Six accent color options (green, blue, pink, gold, purple, teal) that update the entire app instantly.
- **Density modes** — Compact, comfortable, and spacious density settings that adjust visual density across the UI.
- **Font scaling** — Adjustable font size slider (0.85x to 1.25x) that scales all text in the app.
- **Persistent preferences** — All appearance settings are saved and restored across app restarts.

### Spaces
- **Complete space hierarchy** — Spaces now use the server-side `/hierarchy` API to show all rooms, including those inside nested sub-spaces (like voice channel containers).
- **Unjoined room discovery** — Rooms you haven't joined yet appear in "available rooms" and "available voice channels" sections with member counts and join-rule-aware affordances.
- **Smart join states** — Public rooms show "join", restricted rooms show "request", and invite-only rooms are greyed out. After tapping, the UI shows joining/pending/failed states with clear feedback.
- **Hierarchy name fallback** — Rooms that haven't fully synced their name show the authoritative name from the space hierarchy instead of "Empty chat".
- **Pending room state** — Restricted rooms waiting for sync show a dedicated "Request sent" screen instead of the generic syncing stepper.

### Room Management
- **Leave Room** — A new "Leave Room" action in the room info panel lets you leave any room with a confirmation dialog. Works for DMs, channels, stale rooms, and spaces.

### Bug Fixes
- Fixed `SyncingZeroState` getting stuck indefinitely on empty rooms that have no messages.
- Fixed space unread badges using incomplete local data instead of the full hierarchy.
- Space rooms (sub-spaces) no longer appear as joinable channels in the room list.
- Voice channels inside nested sub-spaces now appear correctly within their parent space.
