# Phase 2: Navigation & Organization

**Weeks 11-14 | Depends on: Phase 1 (Core Messaging)**

---

## Objectives

Transform Gloam from a functional messaging client into a navigable, organized workspace. This phase builds the structural shell that makes the app usable as a daily driver: spaces, room lists, threads, notifications, and the quick switcher. By the end, a user should be able to manage dozens of rooms across multiple spaces without friction.

## Success Criteria

- Three-column desktop layout renders correctly on macOS, Windows, and Linux at all supported viewport sizes
- Space rail displays spaces with unread indicators; switching spaces updates the room list in <100ms
- Room list shows unread counts, mention badges, and room type indicators; selecting a room loads the timeline within the Phase 1 performance target (<200ms)
- Mobile tab bar navigation works on iOS and Android with native-feeling gestures
- Quick switcher (Cmd/Ctrl+K) opens in <50ms, returns fuzzy search results within 100ms for up to 500 rooms
- Push notifications delivered reliably on iOS (APNs) and Android (FCM + UnifiedPush) with encrypted content decrypted in the notification extension
- Tapping a notification deep links to the specific message, not the room bottom
- Threads open in the right panel on desktop, as a pushed screen on mobile
- Room creation flow covers all common room types in under 30 seconds

---

## Task Breakdown

### 1. Desktop Layout Shell

**Priority: High | Estimate: 8-10 days**

The foundational layout widget that everything else plugs into. Get this wrong and every subsequent task fights the layout.

#### Implementation

**AdaptiveShell widget** — a single top-level widget that adapts to viewport width:

| Breakpoint | Layout | Behavior |
|------------|--------|----------|
| < 600px (phone) | Single column | Tab bar + stack navigation |
| 600-900px (tablet portrait / small window) | Two columns | Room list + chat area, space rail collapsed into hamburger |
| > 900px (desktop / tablet landscape) | Three columns | Space rail (64px) + Room list (240-280px) + Chat area (fill) |

**Three-column structure:**

```
┌──────┬────────────┬──────────────────────────────────┐
│ 64px │  240-280px │              fill                 │
│      │            │                                   │
│Space │  Room List │         Chat Area                 │
│Rail  │            │                                   │
│      │            │         ┌──────────────────┐      │
│      │            │         │ Right Panel      │      │
│      │            │         │ (threads/info/   │      │
│      │            │         │  members/search) │      │
│      │            │         └──────────────────┘      │
└──────┴────────────┴──────────────────────────────────┘
```

**Right panel:** contextual overlay that slides in from the right edge of the chat area. Used for threads, room info, member list, and search results. Does NOT replace the chat area — it shrinks it. Closable via X button or Escape key.

**Resizable columns:**
- Room list width adjustable between 200px and 400px via drag handle
- Right panel width adjustable between 280px and 50% of chat area
- Persist column widths per user in local preferences
- Double-click drag handle to reset to default width

**Responsive behavior:**
- When window shrinks below 900px, space rail collapses first
- When below 600px, switch to single-column stack navigation
- Orientation changes on tablet trigger layout recalculation
- Keyboard appearance on tablet does not break layout

**Keyboard navigation:**
- Cmd/Ctrl+1-9 to switch spaces
- Cmd/Ctrl+[ and Cmd/Ctrl+] to navigate room history (back/forward)
- Arrow keys navigate room list when focused
- Escape closes right panel, then deselects room
- Tab cycles focus between rail, room list, chat area, right panel

#### Subtasks

- [ ] Build `AdaptiveShell` widget with breakpoint detection using `LayoutBuilder`
- [ ] Implement three-column layout with `Row` + constrained `SizedBox` containers
- [ ] Add `GestureDetector`-based column resize handles with cursor feedback
- [ ] Implement right panel slide-in animation (200ms ease-out)
- [ ] Add keyboard shortcut bindings for layout navigation
- [ ] Persist column widths to local storage via shared preferences
- [ ] Write widget tests for all three breakpoints
- [ ] Test on macOS, Windows, Linux at various window sizes

#### Key Decision: AdaptiveShell Architecture

**Chosen approach:** Single `AdaptiveShell` widget at the top of the widget tree that uses `LayoutBuilder` to determine the current breakpoint and renders the appropriate layout variant. Child panels communicate via Riverpod providers (selected space, selected room, right panel state) rather than passing callbacks.

**Why not `NavigationRail` / `NavigationBar` from Material?** They impose Material's navigation model. Our space rail and room list are custom enough that wrapping them in Material navigation widgets adds constraints without benefits. We use raw layout widgets and manage selection state ourselves.

---

### 2. Space Rail

**Priority: Medium | Estimate: 4-5 days | Depends on: Desktop Layout Shell**

Vertical icon strip on the left edge. This is the Discord server-list equivalent — the top-level organizational unit.

#### Implementation

**Layout:** 64px wide, full height. Scrollable vertically if spaces overflow.

**Items (top to bottom):**
1. Home / All DMs button (always first, not reorderable)
2. Separator line
3. Space avatars in user-defined order
4. Separator line
5. "+" button to join/create a space (always last)

**Per-space avatar:**
- 40px circular avatar with 2px rounded-rect mask (Discord-style pill on hover/active)
- Unread indicator: small dot (8px) on the right edge when space has unread rooms
- Mention indicator: red badge with count overlay on avatar when space has mentions
- Active state: left-edge pill indicator (4px wide, accent-colored) + avatar scales to 48px
- Hover: avatar rounds from circle to squircle (200ms transition)
- Tooltip on hover showing space name (after 500ms delay)

**Reordering:**
- Long press (mobile) or click-and-drag (desktop) to reorder
- `ReorderableListView` with custom drag proxy (semi-transparent avatar)
- Persist order to Matrix account data (`m.space_order` or custom event type)

**Unread calculation:**
- Subscribe to room list updates via matrix_dart_sdk
- Aggregate unread counts across all rooms in the space
- Distinguish between unread messages and unread mentions (mentions always surface)

#### Subtasks

- [ ] Build `SpaceRail` widget with scrollable column of space avatars
- [ ] Implement unread dot and mention badge overlays
- [ ] Add active state pill indicator with animation
- [ ] Implement drag-to-reorder with `ReorderableListView`
- [ ] Persist space order to Matrix account data
- [ ] Add "+" button with create/join space sheet
- [ ] Implement hover effects (squircle morph) for desktop
- [ ] Connect to Riverpod provider for selected space state

---

### 3. Room List Within Spaces

**Priority: Medium | Estimate: 5-6 days | Depends on: Space Rail**

When a space is selected, the room list panel shows its rooms organized by category.

#### Implementation

**Header:** Space name + chevron (opens space settings). Search bar below.

**Room categories:**
- Default categories: Channels, Voice Channels (Phase 5), DMs
- Custom categories from space state events (`m.space.sections` or similar)
- Collapsible sections with triangle disclosure indicator
- Persist collapsed state locally

**Per-room row:**
- Room type icon: `#` for public, lock for encrypted, person for DM, megaphone for announcement
- Room name (truncated with ellipsis)
- Unread count badge (right-aligned, muted color for messages, red for mentions)
- Last message preview (optional — configurable in settings, off by default for density)
- Active state: background highlight (accent color at 10% opacity)
- Hover: background highlight (surface color variant)

**Filtering:**
- Search bar at top filters rooms by name (client-side, instant)
- Filter chips: All | Unread | Mentions | Favorites
- Sorting: by activity (default), alphabetical, unread-first

**Room type indicators:**
- Encrypted rooms show a small lock icon
- Bridged rooms show bridge icon
- Rooms with active calls show a phone/video icon

**Virtualization:**
- Use `ListView.builder` for rooms — only build visible tiles
- Smooth scrolling with platform-appropriate physics

#### Subtasks

- [ ] Build `RoomListPanel` widget with header, search, and scrollable room list
- [ ] Implement room categories from space children state events
- [ ] Add unread count and mention badge rendering
- [ ] Implement search/filter bar with instant client-side filtering
- [ ] Add filter chips (All / Unread / Mentions / Favorites)
- [ ] Room type icons (encrypted, public, DM, bridged, active call)
- [ ] Connect to matrix_dart_sdk room list subscription for the selected space
- [ ] Implement collapsible categories with persisted state
- [ ] Handle room list updates (new room joined, room left, unread state change)

---

### 4. Mobile Navigation

**Priority: Medium | Estimate: 4-5 days | Depends on: Desktop Layout Shell**

Completely different navigation paradigm from desktop. Stack-based with a bottom tab bar.

#### Implementation

**Bottom tab bar (4 tabs):**

| Tab | Icon | View |
|-----|------|------|
| Chats | chat bubble | Room list (all rooms or filtered by space) |
| Spaces | grid/globe | Space browser — grid of space avatars, tap to filter Chats tab |
| Calls | phone | Call history + active calls (stub for Phase 5) |
| Settings | gear | Settings screens |

**Navigation flow:**
- Chats tab → Room list → tap room → Chat screen (pushed, full-screen)
- Back gesture (iOS swipe-from-left, Android predictive back) returns to room list
- Spaces tab → tap space → switches to Chats tab filtered to that space
- Within a chat: tap room name header → Room info screen (pushed)
- Within a chat: tap thread indicator → Thread view (pushed)

**Tab bar behavior:**
- Persists across navigation (not hidden when entering a room — it IS hidden)
- Actually: tab bar hides when entering a room to maximize chat space
- Re-appears on back navigation to room list
- Badge indicators on Chats tab for total unread, on Calls tab for missed calls

**iOS-specific:**
- Large title headers that collapse on scroll
- Native back swipe gesture via `CupertinoPageRoute` or equivalent
- Haptic feedback on tab switch

**Android-specific:**
- Material 3 NavigationBar styling
- Predictive back gesture support
- Edge-to-edge rendering with system bar insets

#### Subtasks

- [ ] Build mobile navigation scaffold with bottom tab bar
- [ ] Implement tab routing with `go_router` shell routes
- [ ] Chat screen push/pop with platform-appropriate transitions
- [ ] Hide tab bar during chat, show on room list
- [ ] iOS: large title collapsing headers, back swipe gesture
- [ ] Android: Material 3 nav bar, predictive back support
- [ ] Badge indicators on tab icons
- [ ] Ensure safe area handling for notch/dynamic island/gesture bar

---

### 5. DM List with Presence

**Priority: Low | Estimate: 3-4 days | Depends on: Room List**

DMs surface at the top of the Home space or as a dedicated section. Presence indicators make the app feel alive.

#### Implementation

**DM section:**
- Shown when "Home" / "All DMs" is selected in the space rail
- Sorted by most recent activity (last message timestamp)
- Each DM row shows: avatar, display name, last message preview (truncated), timestamp

**Presence indicators:**
- Green dot (online), yellow dot (idle), grey dot (offline)
- Positioned on the bottom-right of the avatar (12px diameter, 2px white border)
- Subscribe to presence events from matrix_dart_sdk
- Presence updates streamed reactively — dot updates without full list rebuild

**Presence caveats:**
- matrix.org has presence disabled by default for performance
- Detect if the homeserver supports presence; if not, hide indicators and don't waste bandwidth
- Conduit/Dendrite may have different presence behavior — handle gracefully

**Sorting:**
- Primary: has unread → by timestamp
- Optional: pin favorite DMs to top

#### Subtasks

- [ ] Build DM list view with avatar, name, preview, timestamp
- [ ] Implement presence dot overlay on avatars
- [ ] Subscribe to presence events, handle homeservers with presence disabled
- [ ] Sort by activity with unread-first option
- [ ] Handle group DMs (show multiple avatars or group name)

---

### 6. Quick Switcher (Cmd/Ctrl+K)

**Priority: Medium | Estimate: 4-5 days | Depends on: Room List**

Power-user feature that makes navigation instant. Opens a floating modal, fuzzy-searches rooms/people/spaces.

#### Implementation

**Trigger:** Cmd+K (macOS), Ctrl+K (Windows/Linux). Also accessible via search icon in room list header.

**UI:**
- Centered overlay modal (480px wide, max 60% viewport height)
- Dark frosted-glass backdrop
- Single text input at top with search icon and placeholder "Jump to..."
- Results list below, keyboard-navigable
- Dismiss: Escape, click outside, or Cmd/Ctrl+K again

**Search behavior:**
- Fuzzy matching on room name, room alias, display name
- Frecency ranking: rooms visited recently AND frequently rank higher
- Track room visit timestamps and frequency in local storage
- Results update as user types (debounce 50ms — fast enough to feel instant)

**Result types (with type hints):**
- Rooms: `#` prefix, show space context ("in [Space Name]")
- DMs: avatar + name, show online status
- Spaces: grid icon prefix
- Future: actions ("Create room", "Start DM with...")

**Keyboard navigation:**
- Arrow up/down to move selection
- Enter to navigate to selected item
- Type-ahead: results filter in real-time

**Frecency algorithm:**
```
score = frequency_weight * visit_count + recency_weight * (1 / hours_since_last_visit)
```
- `frequency_weight` = 1.0
- `recency_weight` = 10.0
- Decay visits older than 30 days
- Store in local SQLite table: `room_id`, `visit_count`, `last_visited_at`

#### Subtasks

- [ ] Build overlay modal widget with text input and results list
- [ ] Implement fuzzy search algorithm (or use a lightweight fuzzy match package)
- [ ] Build frecency scoring system with local persistence
- [ ] Keyboard shortcut registration (Cmd/Ctrl+K)
- [ ] Arrow key navigation within results
- [ ] Type hint icons for rooms, DMs, spaces
- [ ] Dismiss behavior (Escape, outside click, re-trigger)
- [ ] Performance: ensure <100ms result rendering for 500+ rooms

---

### 7. Notification System

**Priority: High | Estimate: 8-10 days | Depends on: Room List, Phase 1 E2EE**

The most technically complex task in this phase. Spans all platforms with different architectures per OS.

#### Implementation

##### Per-Room Notification Settings

UI: long-press room → notification settings sheet.

| Setting | Behavior |
|---------|----------|
| All messages | Notify for every message |
| Mentions & keywords | Only @mentions and custom keywords |
| None | No notifications for this room |

Stored as Matrix push rules (server-side, synced across devices).

##### Global DND (Do Not Disturb)

- Toggle in settings + quick toggle in room list header
- Schedule: weekdays 9am-5pm, custom, always on/off
- DND suppresses all notifications except @mentions in DMs (configurable)
- Persisted locally + optionally to Matrix account data for cross-device sync

##### Push Notifications — iOS (APNs)

**Architecture:**
```
Homeserver → sygnal (push gateway) → APNs → iOS device
  → Notification Service Extension (NSE) intercepts
  → NSE decrypts message content using matrix_dart_sdk crypto
  → NSE constructs rich notification (sender, room, preview)
  → iOS displays notification
```

**NSE constraints (critical):**
- 30MB memory limit (hard kill at ~50MB on some devices)
- 30-second execution time limit
- Must share crypto state with main app via App Group
- Cannot use full matrix_dart_sdk — need a lightweight crypto-only path
- Store crypto state in shared App Group container (UserDefaults or shared SQLite)

**NSE implementation approach:**
- Minimal Dart/Flutter engine in NSE? No — too heavy. Use native Swift NSE.
- Share the SQLCipher crypto database via App Group
- Use flutter_vodozemac's native Swift interface (or call vodozemac directly from Swift)
- Decrypt the event payload, extract sender + body
- If decryption fails (missing keys), show "New message from [sender]" without content

**Rich notifications:**
- Sender avatar (cached locally, or fetch from MXC)
- Room name
- Message preview (first 100 chars of decrypted body)
- Communication notification style on iOS 15+ (for DMs)
- Notification grouping by room (thread identifier = room_id)

##### Push Notifications — Android (FCM + UnifiedPush)

**FCM path:**
```
Homeserver → sygnal → FCM → Android device
  → FirebaseMessagingService receives data message
  → Decrypt content in background isolate
  → Build notification with NotificationCompat
```

**UnifiedPush path (de-Googled Android):**
```
Homeserver → UP-compatible push gateway → UP distributor app → Gloam
  → Same decryption and display logic
```

**Android-specific:**
- Notification channels: DMs, Mentions, Room Messages, Calls
- Each channel independently configurable in system settings
- Notification grouping with summary notification per room
- Inline reply from notification shade
- Message style notification for DMs

##### Desktop Notifications

**Architecture:**
- Desktop apps maintain a persistent sync connection (no push gateway needed)
- On new message: evaluate push rules locally
- If notification warranted: fire platform notification API

**Per-platform:**
- macOS: `UserNotifications` framework via Flutter plugin (`flutter_local_notifications`)
- Windows: WinRT toast notifications
- Linux: `libnotify` via D-Bus

**Desktop-specific features:**
- Click notification → activate window + navigate to room + scroll to message
- Notification actions: "Reply", "Mark as Read"
- Badge count on dock icon (macOS) / taskbar (Windows)

##### Deep Linking

- Every notification carries: `room_id` + `event_id`
- Tapping notification: app opens → navigates to room → scrolls to specific event
- If app is cold-started by notification: queue the deep link, process after sync establishes
- `go_router` deep link path: `/room/:roomId?event=:eventId`

##### Notification Grouping

- Group by room (thread identifier / group key = room_id)
- Summary notification when 3+ notifications from same room
- Clear all room notifications when room is opened (read receipt clears server-side)

#### Subtasks

- [ ] Implement per-room notification settings UI and push rule management
- [ ] Build global DND toggle with schedule support
- [ ] iOS: Implement Notification Service Extension in native Swift
- [ ] iOS: Set up App Group for shared crypto state with main app
- [ ] iOS: Implement NSE decryption with memory-safe vodozemac usage
- [ ] iOS: Rich notification formatting (Communication style, avatars, grouping)
- [ ] Android: FCM integration via `firebase_messaging`
- [ ] Android: Background message decryption handler
- [ ] Android: Notification channels setup (DMs, Mentions, Rooms, Calls)
- [ ] Android: UnifiedPush integration as fallback
- [ ] Android: Inline reply from notification
- [ ] Desktop: Local notification integration via `flutter_local_notifications`
- [ ] All platforms: Deep link handling (notification tap → room → message)
- [ ] All platforms: Notification grouping by room
- [ ] All platforms: Badge count on app icon

#### Key Decision: iOS NSE Memory Strategy

**Problem:** iOS kills Notification Service Extensions that exceed ~30MB. A full Flutter engine + matrix_dart_sdk is too heavy.

**Chosen approach:** Native Swift NSE that directly calls vodozemac (the Rust crypto library) via its Swift bindings. The NSE reads crypto state from a shared SQLite database in the App Group container. It decrypts the event payload, formats the notification, and exits. No Flutter engine, no Dart runtime in the NSE.

**Why not a lightweight Dart isolate?** Flutter's engine overhead alone approaches the memory limit. Even if it worked today, it's fragile — any SDK update could push it over.

**Fallback:** If decryption fails (missing Megolm session, corrupted state), show a generic notification: "New message from [Sender Name]". When the user opens the app, full sync resolves the missing keys.

---

### 8. Threads

**Priority: Medium | Estimate: 5-6 days | Depends on: Desktop Layout Shell (right panel), Phase 1 messaging**

Thread support using Matrix's `m.thread` relation type. Threads are a significant organizational feature for busy rooms.

#### Implementation

**Thread indicators in the main timeline:**
- Messages with thread replies show a "N replies" link below the message
- Thread reply count + avatars of participants (up to 3)
- Clicking the indicator opens the thread in the right panel (desktop) or pushes a screen (mobile)

**Thread panel (right column on desktop):**
- Header: original message preview + "Thread" label + close button
- Scrollable timeline of thread replies
- Message composer at bottom (posts as `m.thread` relation)
- Back button returns to thread list (if navigated from there)

**Thread list view:**
- Accessible from room header icon ("Threads" button)
- Shows all threads in the room, sorted by latest activity
- Each thread item: original message preview, reply count, last reply timestamp
- Unread indicators on threads with new replies

**Broadcast option:**
- When composing a thread reply, toggle "Also send to room" (broadcasts to main timeline)
- Corresponds to `m.thread` event with `is_falling_back: true`

**Unread tracking:**
- Per-thread read receipts (Matrix spec v1.4+)
- Thread with unread replies shows indicator in thread list AND on the thread link in the timeline

#### Subtasks

- [ ] Implement thread indicator widget on timeline messages (reply count + participant avatars)
- [ ] Build thread panel component for right column
- [ ] Thread timeline rendering (reuse message bubble widgets from Phase 1)
- [ ] Thread composer with "Also send to room" toggle
- [ ] Thread list view (all threads in room)
- [ ] Per-thread unread tracking via read receipts
- [ ] Mobile: thread as pushed screen instead of right panel
- [ ] Handle thread events in the sync pipeline (filter, aggregate)

---

### 9. Create Room Flow

**Priority: Medium | Estimate: 3-4 days | Depends on: Space Rail, Room List**

Modal flow for creating new rooms. Should be fast and opinionated with sensible defaults.

#### Implementation

**Trigger:** "+" button in room list header, or from space context menu.

**Step 1 — Room type selector:**

| Type | Icon | Defaults |
|------|------|----------|
| Channel | `#` | Public within space, unencrypted |
| Private Channel | lock | Invite-only, encrypted |
| DM | person | Encrypted, invite one person |
| Group DM | people | Encrypted, invite multiple people |

**Step 2 — Room details (single screen, not a wizard):**
- Name (required)
- Topic (optional)
- Encryption toggle (on by default for private, off for public — with warning if turned off)
- Space assignment (pre-filled if created from within a space)
- Invite members (search by display name or Matrix ID, autocomplete)
- Room address (auto-generated from name for public rooms, editable)

**Submit behavior:**
- Optimistic: room appears in room list immediately with a "Creating..." indicator
- SDK creates room in background
- On success: navigate to the new room
- On failure: show error toast, room disappears from list

**Smart defaults:**
- If created from within a space, auto-assign to that space
- If "DM" selected, skip straight to member search
- Encryption cannot be turned off after creation (show warning)

#### Subtasks

- [ ] Build room type selector cards
- [ ] Build room details form (name, topic, encryption, space, invites)
- [ ] Member search/invite with autocomplete (Matrix user directory)
- [ ] Optimistic room creation (local placeholder in room list)
- [ ] Connect to matrix_dart_sdk `createRoom` API
- [ ] Auto-assign room to current space
- [ ] Validation: room name required, address uniqueness check
- [ ] Mobile: bottom sheet presentation. Desktop: centered modal.

---

## Dependencies

```
Desktop Layout Shell
  ├── Space Rail → Room List → DM List
  ├── Mobile Navigation
  ├── Thread Panel (uses right column)
  └── Quick Switcher (overlay on shell)

Notification System
  ├── Phase 1: E2EE (for NSE decryption)
  ├── Room List (for push rule context)
  └── Deep linking (go_router integration)

Create Room Flow
  ├── Space Rail (space assignment)
  └── Room List (optimistic insertion)
```

## Key Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Layout approach | Custom `AdaptiveShell` with `LayoutBuilder` | Material navigation widgets too constraining for our layout model |
| Navigation state | Riverpod providers (selectedSpace, selectedRoom, rightPanelState) | Decouples panels; any panel can read/write state without prop drilling |
| iOS NSE | Native Swift + vodozemac, no Flutter engine | Memory limit makes Flutter in NSE impractical |
| Push on Android | FCM primary + UnifiedPush fallback | Covers Google and de-Googled devices |
| Desktop notifications | Persistent sync connection + local notification API | No push gateway needed when app is running |
| Quick switcher ranking | Frecency (frequency + recency) | Matches Slack/VS Code behavior that power users expect |
| Thread storage | Matrix `m.thread` relation type | Spec-compliant, interoperable with other clients |
| Column resize | Drag handle with persisted widths | Power users expect customizable layouts |

## Definition of Done

Phase 2 is complete when:

1. **Desktop:** Three-column layout renders correctly on macOS, Windows, and Linux. Columns are resizable. Right panel slides in for threads/info.
2. **Mobile:** Tab bar navigation works on iOS and Android. Room list → chat → back gesture feels native. Tab bar hides in chat view.
3. **Spaces:** Space rail shows all joined spaces with unread indicators. Selecting a space filters the room list. Spaces are reorderable.
4. **Room list:** Rooms display with categories, unread counts, mention badges, and type indicators. Filtering and search work instantly.
5. **Quick switcher:** Cmd/Ctrl+K opens instantly. Fuzzy search finds rooms and people. Frecency ranking surfaces the right results.
6. **Notifications:** Push notifications work on iOS (APNs) and Android (FCM). Encrypted messages are decrypted in the notification extension. Tapping a notification navigates to the message. Desktop notifications work via persistent sync.
7. **Threads:** Thread replies display in the right panel. Thread list shows all threads in a room. Unread indicators work per-thread.
8. **Room creation:** Users can create all room types with sensible defaults in under 30 seconds.
9. **Performance:** No regressions from Phase 1 targets. Room list scrolling is 60fps. Navigation between spaces is <100ms.
10. **The app is usable as a daily driver for text chat across multiple spaces and rooms.**
