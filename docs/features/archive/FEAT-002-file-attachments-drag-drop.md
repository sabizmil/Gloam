# FEAT-002: File Attachments & Drag-and-Drop Upload

**Requested:** 2026-03-26
**Status:** Proposed
**Priority:** P1 (fixes broken feature + adds key capability)

---

## Description

Two related capabilities that should ship together:

1. **Fix the + button:** The attachment button in the message composer should open the system file picker and send the selected file to the room. The plumbing is *partially* in place — `file_picker` is in pubspec.yaml, `onAttach` is wired as a callback from `ChatScreen` to `MessageComposer`, and `sendFileMessage` exists on the `TimelineNotifier`. The `onAttach` handler in `chat_screen.dart` (line 233) currently calls `FilePicker.platform.pickFiles()`, reads bytes from disk, wraps them in a `MatrixFile`, and calls `sendFileMessage`. However, the bug report (BUG-003) states the button does nothing — this may be a stale build issue, a macOS sandbox entitlement problem, or a runtime error being silently swallowed. The first step is to verify whether the existing code actually works, then harden it with error handling, type-aware file construction (images vs. generic files vs. video), upload progress, and size validation.

2. **Drag-and-drop into the chat window:** Users should be able to drag a file from Finder (or any file manager) into the chat area and initiate the same upload flow. This is entirely new — no drag-drop infrastructure exists in the codebase today. On desktop platforms (macOS, Windows, Linux), this is a common interaction pattern. On mobile, it's not applicable (mobile uses the + button or share sheet). The drag-drop zone should provide visual feedback (overlay tint, border glow) when a file hovers over the chat area, and should funnel into the same upload pipeline as the + button.

Both paths should converge on a shared upload flow that handles: file type detection (image/video/audio/generic), size validation, upload progress indication in the timeline, cancellation, and proper Matrix event types (`m.image`, `m.video`, `m.audio`, `m.file`).

### Current State of the Codebase

- `file_picker: ^10.3.10` is already in `pubspec.yaml`
- `MessageComposer` accepts an `onAttach: VoidCallback?` and wires it to the + button's `onPressed`
- `ChatScreen.build()` provides an `onAttach` handler (line 233-246) that calls `FilePicker.platform.pickFiles()`, reads bytes, wraps as `MatrixFile`, and calls `sendFileMessage`
- `TimelineNotifier.sendFileMessage(MatrixFile)` calls `room.sendFileEvent(file)` on the SDK
- Message rendering already handles `m.image`, `m.video`, `m.file`, `m.audio` in `MessageBubble`
- `ImageMessage`, `FileMessage`, `VideoMessage`, `VoiceMessage` widgets exist
- macOS debug entitlements include `files.user-selected.read-write` but **release entitlements do not** — this would cause the file picker to fail silently in release builds
- No drag-and-drop packages or code exist anywhere in the project
- The `onAttach` handler uses the generic `MatrixFile` for all file types rather than `MatrixImageFile` or `MatrixVideoFile`, which means images won't get thumbnails or dimension metadata

## User Story

As a Gloam user, I want to share files, images, and videos in a chat room by either clicking the + button to browse for a file or by dragging a file directly into the chat window, so that I can share media without leaving the app or navigating away from the conversation.

---

## Implementation Approaches

### Approach 1: Minimal Fix — Just Make the + Button Work

**Summary:** Verify and fix the existing `onAttach` handler, add error handling, and skip drag-drop entirely for now.

**Technical approach:**
- Fix macOS release entitlements to include `files.user-selected.read-write`
- Add try-catch around `FilePicker.platform.pickFiles()` with user-facing error snackbar
- Keep the generic `MatrixFile` wrapping (no type-aware construction)
- No drag-drop, no upload progress, no file size validation

**Pros:**
- Fastest to ship — could be done in an hour
- Unblocks file sharing immediately
- Zero new dependencies

**Cons:**
- No drag-drop (the main UX request)
- Images sent without thumbnails or dimensions (other clients may render them poorly)
- No upload progress — large files appear to hang
- No size validation — users can accidentally try to upload multi-GB files
- Silent failures on unsupported platforms

**Effort:** Low (0.5 day)

**Dependencies:** None new

---

### Approach 2: Fix + Button with Type-Aware Upload (No Drag-Drop)

**Summary:** Fix the + button and make the upload pipeline smart about file types — images get `MatrixImageFile` with thumbnails, videos get `MatrixVideoFile`, etc. Add progress indication and size limits.

**Technical approach:**
- Fix macOS release entitlements
- Detect MIME type from file extension using `lookupMimeType` from `package:mime`
- Construct `MatrixImageFile` for images (SDK generates thumbnails automatically), `MatrixVideoFile` for videos, `MatrixAudioFile` for audio, `MatrixFile` for everything else
- Add an `uploadState` provider to track upload progress (the SDK's `sendFileEvent` doesn't expose granular progress, but we can show a sending indicator)
- Validate file size (e.g., warn above 50MB, reject above 100MB — homeserver-dependent)
- Show upload progress as a local echo with a spinner in the timeline

**Pros:**
- Correct Matrix event types mean proper rendering in all clients
- Thumbnail generation for images
- Upload progress gives user confidence
- Size validation prevents frustrating failures
- No new packages beyond `mime`

**Cons:**
- Still no drag-drop
- `mime` package is a new dependency (though it's lightweight and from dart.dev)
- No multi-file selection UX
- Doesn't address the "I want to drag a file in" use case at all

**Effort:** Medium (1.5 days)

**Dependencies:** `mime` package (for MIME detection from extension)

---

### Approach 3: Full Feature — Fix + Button + `desktop_drop` Package for Drag-Drop

**Summary:** Fix the + button with type-aware uploads AND add drag-and-drop using the `desktop_drop` Flutter package, which provides a `DropTarget` widget for desktop platforms.

**Technical approach:**
- Everything from Approach 2
- Add `desktop_drop` package (well-maintained, supports macOS/Windows/Linux)
- Wrap the chat `Column` in `ChatScreen` with a `DropTarget` widget
- On drag-enter: show a full-screen overlay with visual feedback (semi-transparent green tint, dashed border, "Drop to upload" text)
- On drop: read file bytes, detect type, funnel into the same upload pipeline
- `DropTarget` provides `List<XFile>` — iterate and upload each
- On mobile, `DropTarget` is a no-op (the widget still renders but never receives events)

**Pros:**
- Complete solution — both input methods work
- `desktop_drop` is mature and well-maintained (1.5k+ pub likes)
- Shared upload pipeline means consistent behavior
- Visual drag feedback is polished UX
- Mobile gets the + button fix; desktop gets both

**Cons:**
- New dependency (`desktop_drop`)
- Drag overlay UI needs to match the Gloam design system carefully
- Multi-file drop needs handling (upload sequentially or show a confirmation?)
- `desktop_drop` doesn't work on web (not a target, but worth noting)

**Effort:** Medium (2-3 days)

**Dependencies:** `desktop_drop`, `mime`

---

### Approach 4: Native Platform Channels for Drag-Drop (No Third-Party Package)

**Summary:** Implement drag-and-drop using Flutter's built-in `DragTarget` or raw platform channels instead of the `desktop_drop` package.

**Technical approach:**
- Flutter's built-in `DragTarget<T>` widget handles intra-app drag-and-drop but does NOT handle OS-level file drops from Finder/Explorer
- To handle OS-level drops, write platform-specific code: Swift `NSView.registerForDraggedTypes` on macOS, equivalent on Windows/Linux
- Create a `MethodChannel` to forward drop events to Dart
- Parse file paths from the platform event, read bytes, upload

**Pros:**
- No third-party dependency for drag-drop
- Full control over the native behavior
- Could potentially handle more edge cases (e.g., drop from other apps with custom pasteboard types)

**Cons:**
- Significant effort — platform channel code for 3 desktop platforms
- Reinventing what `desktop_drop` already does well
- Maintenance burden for platform-specific Swift/C++/C code
- Flutter's built-in `DragTarget` doesn't help with OS-level drops at all
- Much harder to test

**Effort:** High (5-7 days)

**Dependencies:** None (but requires native code per platform)

---

### Approach 5: Paste-from-Clipboard + Drop (Keyboard-First UX)

**Summary:** Instead of (or in addition to) drag-drop, support Cmd+V to paste images/files from the clipboard directly into the composer. Combined with the + button fix.

**Technical approach:**
- Everything from Approach 2 (+ button fix)
- Add a `RawKeyboardListener` or `Shortcuts` widget that intercepts Cmd+V / Ctrl+V
- Read clipboard data using `Clipboard.getData` — for images, read `image/png` from the system pasteboard
- On paste of image data, create a `MatrixImageFile` and send immediately (or show a preview)
- On paste of file references, read file and upload
- Can also add `desktop_drop` for drag-and-drop as a complement

**Pros:**
- Keyboard-first UX aligns with Gloam's power-user personality
- Clipboard paste is extremely common (screenshots, copied images)
- Complements both + button and drag-drop
- Low effort for just paste support

**Cons:**
- Clipboard API in Flutter is limited — `Clipboard.getData` only handles text reliably cross-platform
- Image paste requires platform-specific code or `pasteboard` package
- Not a replacement for drag-drop (different use case)
- File paste from clipboard is unreliable on most platforms

**Effort:** Medium-High (3-4 days for paste + drop combined)

**Dependencies:** `desktop_drop`, `pasteboard` (for clipboard image access)

---

## Recommendation

**Approach 3: Full Feature — Fix + Button + `desktop_drop` for Drag-Drop**

This is the right call for several reasons:

1. **The + button fix is table stakes.** BUG-003 is a P1 — an entire feature surface is broken. The entitlement fix alone might unblock it, but we need proper error handling and type-aware uploads regardless.

2. **Drag-drop is the specific UX request** and it's a standard desktop interaction. Users coming from Slack/Discord expect this. Gloam's competitive positioning is about UX polish — shipping without drag-drop would be a miss.

3. **`desktop_drop` is the pragmatic choice over native channels.** It's well-maintained, has broad platform support, and eliminates 5+ days of platform-specific code. The CLAUDE.md project rules say "default to the simplest thing that works" — a proven package beats hand-rolled platform channels.

4. **The shared upload pipeline** means both paths (+ button and drag-drop) produce identical results. One set of upload logic to maintain.

5. **Paste support (Approach 5) is a nice follow-up** but not needed in v1. It requires additional packages and platform quirks. Tag it as a fast-follow.

The effort estimate of 2-3 days is reasonable given that the upload infrastructure already exists (just needs hardening) and the UI work is a drag overlay + entitlement fix.

---

## Implementation Plan

### Step 1: Fix macOS Release Entitlements

**File:** `macos/Runner/Release.entitlements`

Add `com.apple.security.files.user-selected.read-write` to release entitlements (already present in debug). This is likely the root cause of BUG-003 in release builds.

### Step 2: Add Dependencies

**File:** `pubspec.yaml`

- Add `desktop_drop: ^0.5.0` (OS-level drag-drop for desktop platforms)
- Add `mime: ^2.0.0` (MIME type detection from file extension)

### Step 3: Create Shared Upload Service

**New file:** `lib/features/chat/data/file_upload_service.dart`

Encapsulate the upload pipeline:
- Accept a file path (from picker or drop) or raw bytes + filename
- Detect MIME type using `lookupMimeType` from `mime` package
- Validate file size (warn >50MB via callback, reject >100MB homeserver limit)
- Construct the appropriate `MatrixFile` subclass:
  - `MatrixImageFile` for `image/*` (SDK auto-generates thumbnails)
  - `MatrixVideoFile` for `video/*`
  - `MatrixAudioFile` for `audio/*`
  - `MatrixFile` for everything else
- Return the constructed `MatrixFile` ready for `sendFileMessage`

### Step 4: Refactor `onAttach` in ChatScreen

**File:** `lib/features/chat/presentation/screens/chat_screen.dart`

- Replace the inline `onAttach` closure with a call to the upload service
- Add try-catch with a user-facing `ScaffoldMessenger.showSnackBar` on error
- Allow multi-file selection: `FilePicker.platform.pickFiles(allowMultiple: true)`
- Iterate selected files, construct via upload service, send each

### Step 5: Add Drag-Drop to ChatScreen

**File:** `lib/features/chat/presentation/screens/chat_screen.dart`

- Import `desktop_drop`
- Wrap the main `Column` body in a `DropTarget` widget
- Track `_isDragOver` state for visual feedback
- On `onDragEntered`: set `_isDragOver = true`
- On `onDragExited`: set `_isDragOver = false`
- On `onDragDone(DropDoneDetails details)`:
  - Iterate `details.files` (list of `XFile`)
  - For each: read bytes, detect type, construct `MatrixFile` via upload service
  - Call `sendFileMessage` for each
  - Reset `_isDragOver`

### Step 6: Build Drag Overlay Widget

**New file:** `lib/features/chat/presentation/widgets/drop_overlay.dart`

A full-area overlay shown when `_isDragOver` is true:
- Semi-transparent `bg` color with increased alpha (~60% opacity)
- Dashed border in `accent` color
- Centered column: upload icon + "drop files to send" in JetBrains Mono `label` style
- Animated fade in/out (150ms)
- Positioned as a `Stack` child over the timeline

Design tokens:
- Background: `GloamColors.bg` at 0.7 opacity
- Border: `GloamColors.accent` dashed, 2px
- Text: `GloamColors.accent`, JetBrains Mono 12px, uppercase, letter-spacing 0.08em
- Icon: `Icons.cloud_upload_outlined`, 32px, `GloamColors.accent`

### Step 7: Upload Progress Indication

**File:** `lib/features/chat/presentation/providers/timeline_provider.dart`

- The SDK's `room.sendFileEvent()` handles local echo automatically (message appears with sending state)
- The existing `MessageSendState.sending` + opacity reduction in `MessageBubble` already provides visual feedback
- For large files, consider adding a `LinearProgressIndicator` to the `FileMessage` widget when `sendState == sending`

**File:** `lib/features/chat/presentation/widgets/file_message.dart`

- Accept optional `sendState` and show a thin progress bar at the bottom of the file card when sending

### Step 8: Update TimelineNotifier for Type-Aware Sends

**File:** `lib/features/chat/presentation/providers/timeline_provider.dart`

- The existing `sendFileMessage(MatrixFile)` already calls `room.sendFileEvent(file)` — the SDK inspects the `MatrixFile` subclass to determine the event type (`m.image` vs `m.file`, etc.), so the type-aware construction in the upload service is sufficient. No changes needed here beyond confirming this behavior.

### Edge Cases

| Case | Handling |
|------|----------|
| **Large files (>100MB)** | Reject with snackbar: "File too large — max 100MB". Homeservers typically cap at 50-100MB. |
| **Large files (>50MB)** | Warn with snackbar but allow: "Large file — upload may take a while" |
| **Encrypted rooms** | SDK handles encryption automatically when calling `sendFileEvent` on an encrypted room. No special handling needed. |
| **Upload cancellation** | Not supported by `sendFileEvent` in the current SDK. Local echo can be redacted if the user wants to "cancel" a stuck upload. Tag as future improvement. |
| **Multiple files dropped** | Upload sequentially with a small delay between each to avoid overwhelming the server. Show individual local echoes. |
| **Zero-byte files** | Reject with snackbar: "Cannot send empty file" |
| **Unsupported MIME types** | Fall through to generic `MatrixFile` — the SDK handles this gracefully |
| **Drag-drop on mobile** | `DropTarget` is a no-op on iOS/Android — no overlay shown, no events fired |
| **macOS sandbox** | Release entitlements must include `files.user-selected.read-write`. `desktop_drop` also requires file read access for dropped files — the sandbox allows this for user-initiated drops. |
| **Network failure during upload** | SDK sets event status to error. `MessageBubble` already renders error state at reduced opacity. Add a retry tap handler as a follow-up. |

---

## Acceptance Criteria

- [ ] Clicking the + button opens the system file picker on macOS, Windows, Linux, iOS, and Android
- [ ] Selecting a file from the picker sends it to the room and it appears in the timeline
- [ ] Images are sent as `m.image` events with thumbnails (visible in other Matrix clients)
- [ ] Videos are sent as `m.video` events
- [ ] Audio files are sent as `m.audio` events
- [ ] Other files are sent as `m.file` events with correct filename and size
- [ ] Files sent in encrypted rooms are properly encrypted (verified by receiving on another client)
- [ ] Dragging a file from the OS file manager into the chat window shows a visual drop overlay
- [ ] Dropping the file sends it using the same pipeline as the + button
- [ ] Dropping multiple files sends each one
- [ ] Files larger than 100MB are rejected with a user-facing error
- [ ] Upload failures show a snackbar or error state (not a silent failure)
- [ ] The feature works in macOS release builds (entitlement fix verified)
- [ ] Drag-drop is a no-op on mobile (no visual glitches, no errors)

---

## Related

- **[BUG-003](../bugs/BUG-003-attachment-button-noop.md):** Attachment button does nothing — this feature supersedes and closes BUG-003
- **[COMPETITIVE_ANALYSIS.md](../../COMPETITIVE_ANALYSIS.md):** Section on "Rich media" — file sharing with inline previews listed as Phase 1 table-stakes feature
- **[09-design-system.md](../plan/09-design-system.md):** Design tokens for overlay, typography, and color used in the drop overlay
- **Follow-up:** Clipboard paste (Cmd+V) for images — tagged as a fast-follow after this ships
