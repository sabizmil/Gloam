# FEAT-005: Edit & Delete Own Messages

**Requested:** 2026-03-26
**Status:** Proposed
**Priority:** P0 (core messaging UX)
**Phase:** 1 (Core Messaging)

---

## Description

The ability to edit and delete your own messages is a baseline expectation in any modern chat client. Gloam already has partial scaffolding for both operations -- the plumbing exists but the end-to-end experience has gaps that prevent it from feeling complete and trustworthy.

### What already works

| Layer | Edit | Delete |
|-------|------|--------|
| **Timeline provider** | `editMessage(eventId, newText)` calls `room.sendTextEvent(newText, editEventId: eventId)` | `redactMessage(eventId)` calls `room.redactEvent(eventId)` |
| **Context menu** | "edit" action in `_showMessageActions` triggers `_handleEditAction` (own messages only) | "delete" action calls `redactMessage` directly (own messages only) |
| **Composer** | `ComposerMode.edit` populates the text field with the original body, shows an "editing message" bar, changes the send icon to a checkmark | N/A |
| **Message bubble** | `isEdited` flag renders "(edited)" label next to the timestamp | `isRedacted` renders `[message deleted]` tombstone |
| **Data model** | `TimelineMessage.isEdited` set from `event.hasAggregatedEvents(timeline, RelationshipTypes.edit)` | `TimelineMessage.isRedacted` set from `event.redacted` |

### Identified gaps

1. **No confirmation dialog on delete.** Tapping "delete" immediately redacts the message with no way to undo. The Phase 1 spec explicitly requires: "Confirmation dialog: 'Delete this message? This can't be undone.'"
2. **No Up Arrow shortcut.** The Phase 1 spec calls for pressing Up Arrow in an empty composer to edit the last sent message. Not implemented.
3. **Copy text action is a no-op.** The "copy text" context menu item pops the bottom sheet but never copies anything to the clipboard.
4. **No error handling on edit/delete.** Both `editMessage` and `redactMessage` are fire-and-forget `async` calls with no try/catch, no user-facing error feedback.
5. **No swipe-to-reply.** The Phase 1 spec mentions swipe-right on mobile to trigger reply. Not implemented (secondary to edit/delete but part of the same context menu surface).
6. **Desktop context menu is a bottom sheet, not a floating menu.** The spec says desktop should use a floating context menu at the cursor position; currently `showModalBottomSheet` is used on all platforms.
7. **No hover toolbar.** The spec describes a quick-react bar on hover (desktop). Not implemented.
8. **No visual feedback during edit/delete network call.** The user gets no indication that the operation is in flight or that it succeeded/failed.

This feature request focuses on gaps 1--4 and 8 (the core edit/delete UX), with gaps 5--7 as stretch goals for platform polish.

---

## User Story

As a **Gloam user**, I want to **edit and delete my own messages** so that I can **fix typos, correct mistakes, and remove messages I no longer want visible** -- with clear confirmation before destructive actions and feedback when things go wrong.

---

## Implementation Approaches

### Approach 1: Minimal Gap Fix (patch existing code)

**Summary:** Fix the identified gaps in the existing implementation without architectural changes.

**Technical approach:**
- Add a confirmation dialog before `redactMessage` in `_showMessageActions`
- Add Up Arrow key handler in `MessageComposer._handleKeyEvent` that finds the last own message and triggers edit mode
- Add `Clipboard.setData` to the copy text action
- Wrap `editMessage` and `redactMessage` in try/catch with `ScaffoldMessenger.showSnackBar` for errors
- Add an optimistic "sending" state visual during edit (reduce opacity briefly)

**Pros:**
- Minimal code changes (< 100 lines across 3 files)
- No new dependencies or architectural changes
- Can be done in a single session
- Low regression risk

**Cons:**
- Doesn't address the desktop context menu (still a bottom sheet)
- No hover toolbar or swipe gestures
- Error handling is basic (snackbar only)

**Effort:** 1 day
**Dependencies:** None

---

### Approach 2: Full Context Menu Overhaul (platform-aware)

**Summary:** Replace the single `showModalBottomSheet` with platform-adaptive menus: bottom sheet on mobile, `showMenu` popup on desktop.

**Technical approach:**
- Create a `MessageActionMenu` widget that checks `Platform` / `kIsWeb` and renders either a `PopupMenuButton`-style overlay at the tap position (desktop) or a bottom sheet (mobile)
- Move all action handling into a shared `MessageActions` helper class
- Add confirmation dialog (desktop: `AlertDialog`, mobile: confirmation bottom sheet)
- Add Up Arrow shortcut, clipboard copy, error handling as in Approach 1
- Use `Overlay` with `CompositedTransformFollower` for precise desktop menu positioning

**Pros:**
- Platform-native feel on both desktop and mobile
- Shared action logic reduces duplication
- Sets up the architecture for hover toolbar (Approach 4) later

**Cons:**
- More code and complexity
- Desktop overlay positioning needs testing across window sizes
- Two rendering paths to maintain

**Effort:** 2-3 days
**Dependencies:** None

---

### Approach 3: Swipe Gesture + Haptics (mobile-first)

**Summary:** Add iOS/Android-native swipe gestures for reply (swipe right) and delete (swipe left) alongside the existing long-press menu.

**Technical approach:**
- Wrap each `MessageBubble` in a `Dismissible` or custom `GestureDetector` with horizontal drag detection
- Swipe right: trigger reply (with haptic feedback via `HapticFeedback.mediumImpact()`)
- Swipe left on own messages: show delete confirmation
- Add a rubber-band animation that reveals an icon (reply arrow / trash) behind the message as it slides
- Keep the long-press bottom sheet as the full action menu
- Include all gap fixes from Approach 1

**Pros:**
- Feels native to iOS/Android users (matches iMessage, WhatsApp, Telegram)
- Faster interaction for the most common actions (reply, delete)
- Haptic feedback adds physicality

**Cons:**
- Desktop doesn't benefit (swipe doesn't make sense with a mouse)
- Swipe conflicts with horizontal scrolling if code blocks overflow
- Animation tuning needed to feel right
- More complex gesture handling

**Effort:** 3-4 days
**Dependencies:** None (Flutter's gesture system handles this natively)

---

### Approach 4: Hover Toolbar (desktop-first)

**Summary:** Add a floating action toolbar that appears on message hover (desktop) with quick reactions + edit/delete/reply buttons.

**Technical approach:**
- Wrap each `MessageBubble` in a `MouseRegion` that tracks hover state
- On hover, show a floating toolbar (absolutely positioned above the message bubble's top-right corner) with:
  - Quick emoji row (6 most-used)
  - Reply, Edit (own only), Delete (own only), More (...) buttons
- Toolbar uses `OverlayEntry` or a `Stack` within the message row
- The "More" button opens the full context menu
- Include all gap fixes from Approach 1
- Mobile falls back to existing long-press behavior

**Pros:**
- Matches Slack/Discord UX pattern that desktop users expect
- Fastest path to actions (no long-press or right-click needed)
- Visually communicates available actions without requiring discovery

**Cons:**
- Desktop-only benefit; mobile still needs long-press
- Overlay positioning is tricky with reversed scroll lists
- Risk of visual noise if toolbar flickers during rapid mouse movement
- Increases widget tree complexity for every message

**Effort:** 3-4 days
**Dependencies:** None

---

### Approach 5: Unified Action Layer (comprehensive)

**Summary:** Build a full `MessageActionController` that unifies all interaction patterns: long-press, right-click, swipe, hover toolbar, and keyboard shortcuts, with platform-aware selection.

**Technical approach:**
- Create `MessageActionController` (Riverpod provider) that tracks:
  - Currently hovered message (desktop)
  - Currently selected message for action
  - Pending action state (for optimistic UI)
- Create `MessageActionOverlay` widget that renders the right UI per platform:
  - Desktop: hover toolbar + right-click floating menu
  - Mobile: swipe gestures + long-press bottom sheet
  - All: keyboard shortcuts (Up Arrow for edit, Delete/Backspace for delete on selected)
- Confirmation dialog for delete on all platforms
- Edit/delete operations wrapped with loading state + error feedback
- Action results shown via toast/snackbar
- Include undo for delete (delay the redaction by 5 seconds with an "Undo" snackbar)

**Pros:**
- Best possible UX on every platform
- Centralized action logic -- single source of truth for permissions, state, and execution
- Undo for delete is a differentiator (no other Matrix client does this)
- Future-proof: adding new actions (pin, forward, bookmark) requires only adding to the controller

**Cons:**
- Highest complexity and effort
- Undo-delete requires holding the redaction and managing a timer, with edge cases (what if the user leaves the room?)
- Over-engineered for current scope -- the app is pre-beta

**Effort:** 5-7 days
**Dependencies:** None

---

## Recommendation

**Approach 1 (Minimal Gap Fix)** is the right call for now.

The existing scaffolding is solid -- the SDK calls work, the composer edit mode works, the context menu is wired up. What's missing is small but important: a confirmation dialog, error handling, the clipboard copy, and the Up Arrow shortcut. These are ~100 lines of changes across 3 files with zero architectural risk.

Approaches 2-5 are worth doing eventually (especially the hover toolbar and platform-aware context menu), but they're polish on top of a feature that needs to work end-to-end first. Ship the gap fixes now, file separate features for hover toolbar (FEAT-006) and swipe gestures (FEAT-007) later.

---

## Implementation Plan

### Step 1: Add delete confirmation dialog
**File:** `lib/features/chat/presentation/screens/chat_screen.dart`

Replace the direct `redactMessage` call in `_showMessageActions` with a call to a `_confirmDelete` method that shows an `AlertDialog` with:
- Title: "Delete message?"
- Body: "This can't be undone."
- Cancel button (secondary)
- Delete button (danger-colored, calls `redactMessage`)

### Step 2: Add error handling to edit and delete
**File:** `lib/features/chat/presentation/screens/chat_screen.dart`

- Wrap the `onEdit` callback (line 286) in a try/catch that shows a snackbar on failure
- Wrap the `redactMessage` call (inside `_confirmDelete`) in a try/catch
- Consider adding a brief "sending" indicator (optional; snackbar on error is the minimum)

### Step 3: Add Up Arrow shortcut to edit last message
**File:** `lib/features/chat/presentation/widgets/message_composer.dart`

In `_handleKeyEvent`:
- When `LogicalKeyboardKey.arrowUp` is pressed and `_controller.text.isEmpty` and mode is `ComposerMode.normal`:
  - Need a callback like `onEditLastMessage` that the parent (`ChatScreen`) handles
  - Parent finds the last message where `senderId == myUserId` and calls `_handleEditAction` on it

**File:** `lib/features/chat/presentation/screens/chat_screen.dart`
- Add `onEditLastMessage` callback to `MessageComposer` invocation
- Implement by searching `messages` list for the most recent own message

### Step 4: Fix copy text action
**File:** `lib/features/chat/presentation/screens/chat_screen.dart`

In `_showMessageActions`, update the "copy text" `_ActionTile`'s `onTap`:
```dart
import 'package:flutter/services.dart';
// ...
onTap: () {
  Clipboard.setData(ClipboardData(text: msg.body));
  Navigator.pop(ctx);
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('copied to clipboard'), duration: Duration(seconds: 1)),
  );
},
```

### Step 5: Test end-to-end
- Edit a message -> verify "(edited)" appears and content updates in-place
- Delete a message -> verify confirmation dialog appears, then "[message deleted]" tombstone
- Press Up Arrow in empty composer -> verify it enters edit mode for the last own message
- Copy text -> verify clipboard contents
- Trigger edit/delete on a flaky connection -> verify error snackbar appears
- Verify Escape cancels edit mode and restores the composer

---

## Acceptance Criteria

- [ ] Tapping "delete" on own message shows a confirmation dialog before redacting
- [ ] Confirmation dialog has "Cancel" and "Delete" actions; "Delete" is danger-colored
- [ ] After confirming delete, the message is replaced with "[message deleted]" tombstone
- [ ] Tapping "edit" on own message populates the composer with the original text
- [ ] The composer shows an "editing message" bar with a close (x) button to cancel
- [ ] Submitting an edit updates the message in-place with "(edited)" indicator
- [ ] Pressing Escape while in edit mode cancels and restores the composer to normal
- [ ] Pressing Up Arrow in an empty composer enters edit mode for the user's last sent message
- [ ] "Copy text" copies the message body to the system clipboard
- [ ] A brief confirmation (snackbar) appears after copying
- [ ] If editMessage or redactMessage fails, a snackbar shows the error
- [ ] Edit and delete actions are only shown for the user's own messages
- [ ] Redacted messages do not show edit/delete in the context menu
- [ ] All interactions work on macOS (primary dev target) and degrade gracefully on mobile

---

## Related

- [Phase 1: Core Messaging](../plan/02-phase1-core-messaging.md) -- Task 4 (Reply, Edit, Delete) and Task 2 (Composer Edit Mode / Up Arrow shortcut)
- [Phase 4: Platform Polish](../plan/05-phase4-platform-polish.md) -- Keyboard shortcuts, right-click context menus
- [COMPETITIVE_ANALYSIS.md](../../COMPETITIVE_ANALYSIS.md) -- All competitors support edit/delete; it's table-stakes
- [Design System](../plan/09-design-system.md) -- `danger` color token (`#c45c5c`) for delete actions, snackbar styling
