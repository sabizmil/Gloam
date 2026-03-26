# FEAT-001: Global Settings Panel

**Requested:** 2026-03-26
**Status:** Proposed
**Priority:** High

---

## Description

A dedicated settings panel accessible from the space rail on desktop/tablet and from the existing bottom tab on mobile. The settings panel consolidates account management, encryption/security configuration, server connection details, appearance preferences, and session controls (logout) into a single, well-organized surface.

On desktop, the entry point is a gear/avatar icon placed at the very bottom of the space rail, below the existing `+` (add space) button. This follows the convention established by Discord, Slack, and Cinny where the user's identity and settings anchor the bottom-left corner of the app — a position users instinctively check for account controls. On mobile, the existing "settings" tab in `MobileTabs` (currently a placeholder) becomes the entry point.

The panel itself should feel native to Gloam's design language: `//` section headers, green-tinted surfaces, JetBrains Mono labels, and atmospheric density. It is not a modal dialog — it replaces the main content area (like Element X's full-screen settings) or slides in as a panel, depending on the chosen approach.

## User Story

As a Gloam user, I want a centralized settings panel accessible from the main navigation so that I can manage my account, adjust encryption settings, view server details, and log out without hunting through scattered menus.

---

## Implementation Approaches

### Approach 1: Full-Screen Route Replacement

**Summary:** Settings is a new GoRouter route (`/settings`) that replaces the entire shell.

**Technical approach:**
- Add a `/settings` route to `router.dart` that renders a `SettingsScreen` scaffold
- Settings button in space rail triggers `context.go('/settings')`
- SettingsScreen has its own back-navigation to return to `/`
- Sections are a scrollable list within SettingsScreen, with sub-pages pushed as nested routes (`/settings/account`, `/settings/encryption`, etc.)

**Pros:**
- Simple routing — GoRouter handles forward/back transitions
- Clean separation from the chat shell
- Natural URL-based deep linking to specific settings sections
- Works identically across all form factors

**Cons:**
- Loses the spatial context of the chat — user is "teleported" away from their conversation
- Back-navigation can feel disruptive on desktop where users expect panels, not page transitions
- Mobile feels fine, but desktop/tablet UX suffers vs. a panel approach
- Re-entering chat requires re-rendering the shell (potential performance cost on return)

**Effort:** Low (2-3 days)

**Dependencies:** GoRouter (already present), no new packages

---

### Approach 2: Left Panel Overlay (Replace Room List)

**Summary:** Settings slides into the room-list column, replacing the room list content while the space rail and chat area remain visible.

**Technical approach:**
- Add a `settingsOpen` state provider (bool)
- When true, `RoomListPanel` slot in `AdaptiveShell` is swapped for a `SettingsPanel` widget of the same width (280px)
- Settings button in space rail toggles this state
- Sub-sections render inline with expand/collapse or push sub-panels within the same 280px column
- On mobile, the existing settings tab renders the same `SettingsPanel` full-width

**Pros:**
- Chat area stays visible — user doesn't lose context
- Feels native to the existing shell architecture
- Consistent with how Discord shows user settings in-place on the left
- Space rail remains visible, so the settings button acts as a toggle
- Reuses the existing panel slot — minimal layout changes

**Cons:**
- 280px is narrow for settings content (encryption keys, server URLs, etc.)
- Sub-sections need careful information hierarchy to fit the constrained width
- Animated transitions between room list and settings need polish
- Desktop and tablet share the narrow width, which may feel cramped on large screens

**Effort:** Medium (3-4 days)

**Dependencies:** None new

---

### Approach 3: Right Panel Settings View

**Summary:** Settings renders in the right panel slot, reusing the existing `RightPanelView` enum pattern.

**Technical approach:**
- Add `RightPanelView.settings` to the enum
- Settings button sets `rightPanelProvider` to `RightPanelState(view: .settings)`
- `RightPanel` widget renders a `SettingsPanel` in the 320px right-panel slot
- Sub-sections use the same panel navigation pattern as room info / threads

**Pros:**
- Zero layout changes — plugs into existing panel infrastructure
- 320px is slightly wider than the room list, giving more breathing room
- Familiar pattern for the codebase (threads, room info, search already use it)
- Easy to close (Escape key already wired up for panel dismissal)

**Cons:**
- Right panel is contextually tied to the selected room — settings is a global concern, making this feel spatially wrong
- Requires a selected room to be visible (right panel only shows when a room is selected in the current implementation)
- Settings competes with room info / threads for the same slot
- 320px is still fairly narrow for some settings content
- On mobile, the right panel doesn't exist — would need a separate mobile path anyway

**Effort:** Low-Medium (2-3 days)

**Dependencies:** None new

---

### Approach 4: Modal Overlay / Drawer

**Summary:** Settings opens as a full-screen modal overlay (like Discord's settings) or a drawer that slides over the content.

**Technical approach:**
- Settings button triggers `showDialog` or `Navigator.push` with a full-screen `SettingsModal`
- The modal has its own scaffold with a sidebar navigation (on desktop) or top tabs (on mobile) for sections
- Sections: Account, Appearance, Notifications, Encryption & Security, Server, About
- Close button / Escape dismisses the overlay
- Uses `GloamColors.overlay` as the backdrop

**Pros:**
- Maximum space for settings content — not constrained to a narrow panel
- Clear visual hierarchy: settings is a focused, modal activity
- Matches Discord's proven UX pattern (full-screen settings overlay)
- Works identically on desktop, tablet, and mobile with responsive internal layout
- No changes to the shell layout or existing panel system
- Can accommodate complex sub-pages (device list, key management) without space constraints

**Cons:**
- Loses all chat context while open — can't see messages
- Full-screen modal feels heavy for quick actions (just want to toggle a setting)
- Needs its own internal navigation (sidebar or tabs), which is a mini-app within the app
- Animation and backdrop management add complexity

**Effort:** Medium-High (4-5 days)

**Dependencies:** None new

---

### Approach 5: Hybrid — Space Rail Button + Adaptive Panel/Route

**Summary:** The settings entry point is always in the space rail (desktop/tablet) or bottom tab (mobile), but the settings surface adapts per form factor: a panel replacing the room list on desktop, a full-screen route on mobile.

**Technical approach:**
- Desktop/tablet: Settings button in space rail sets a `settingsOpen` provider; `AdaptiveShell` conditionally renders `SettingsPanel` in place of `RoomListPanel`, but at a wider width (360-400px) by expanding the panel slot
- Mobile: Settings tab in `MobileTabs` pushes a `SettingsScreen` that fills the content area (the existing placeholder tab becomes real)
- Both surfaces share the same `SettingsContent` widget tree (sections, tiles, sub-pages) but with different containers
- Sub-pages on desktop slide within the panel; on mobile they push as routes
- The space rail settings button shows the user's avatar (pulling from Matrix profile) and doubles as a quick-access identity indicator

**Pros:**
- Best UX per platform — desktop gets a panel, mobile gets a screen
- The avatar button in the space rail is a natural, discoverable entry point
- Wider panel (360-400px) gives enough room for settings content without being a full takeover
- Shared `SettingsContent` widget means single source of truth for settings UI
- Mobile already has the tab slot ready

**Cons:**
- Two rendering paths (panel vs. screen) increase implementation surface
- Panel width expansion changes the desktop layout proportions
- Need to handle tablet as a middle ground (panel? screen? either could work)
- More code to maintain than a single-mode approach

**Effort:** Medium-High (5-6 days)

**Dependencies:** None new

---

## Recommendation

**Approach 4: Modal Overlay** is the best fit for Gloam.

**Rationale:**

1. **Space is the real constraint.** Settings content ranges from simple toggles (notifications) to complex surfaces (device list with verification states, encryption key management, server URL display). The 280-320px panel approaches (2, 3) will immediately feel cramped for these. A modal gives the content room to breathe.

2. **Proven pattern.** Discord, Telegram Desktop, and Element X all use a full-screen or near-full-screen overlay for settings. Users expect settings to be a focused activity, not a sidebar.

3. **Zero disruption to the shell.** The existing `AdaptiveShell`, `SpaceRail`, `RoomListPanel`, and `RightPanel` remain untouched. The modal is a layer on top — no layout refactoring needed.

4. **Cross-platform consistency.** The same modal works on desktop, tablet, and mobile. On mobile, the settings tab in `MobileTabs` simply opens the same modal (or renders it inline). The internal layout adapts (sidebar nav on wide screens, stacked sections on narrow ones).

5. **Gloam's design language works at modal scale.** The `//` section headers, green surfaces, and monospace labels will look distinctive in a full-screen settings overlay — more impactful than crammed into a narrow panel.

6. **The space rail button placement is clean.** A settings gear icon (or user avatar) below the `+` button fits perfectly in the existing Column layout with minimal changes to `SpaceRail`.

The main downside (losing chat context) is acceptable because settings is an infrequent, intentional activity — not something users toggle while chatting.

---

## Implementation Plan

### Step 1: Add Settings Button to Space Rail

**File:** `lib/app/shell/space_rail.dart`

- Add a `_SpaceIcon` with a gear icon (`Icons.settings_outlined`) or the user's avatar below the existing add-space button, before the final `SizedBox(height: 16)`
- On tap, call a `showSettingsModal(context, ref)` function
- Separate the bottom section from the `+` button with appropriate spacing

### Step 2: Create Settings Modal Shell

**Files to create:**
- `lib/features/settings/presentation/settings_modal.dart` — the full-screen overlay container
- `lib/features/settings/presentation/settings_nav.dart` — sidebar navigation for sections (desktop) / top-level list (mobile)

**Approach:**
- `showSettingsModal()` calls `Navigator.of(context).push()` with a full-screen `PageRouteBuilder` using `GloamColors.overlay` as barrier
- The modal is a `Scaffold` with `GloamColors.bg` background
- Internal layout: `Row` on wide screens (sidebar + content), `Column`/stack on narrow screens
- Close button in the top-right corner; Escape key dismissal via `WillPopScope` or `PopScope`

### Step 3: Create Settings Section Widgets

**Files to create:**
- `lib/features/settings/presentation/sections/account_section.dart` — avatar, display name, user ID, email
- `lib/features/settings/presentation/sections/appearance_section.dart` — theme (dark/light), accent color picker, font size
- `lib/features/settings/presentation/sections/notifications_section.dart` — notification preferences
- `lib/features/settings/presentation/sections/encryption_section.dart` — key backup status, recovery key entry (reuse `RecoveryKeyDialog`), cross-signing status, device list with verification
- `lib/features/settings/presentation/sections/server_section.dart` — homeserver URL, connection status, server version
- `lib/features/settings/presentation/sections/about_section.dart` — app version, licenses, links

**Shared widgets:**
- `lib/features/settings/presentation/widgets/settings_tile.dart` — standard row: icon + label + value/toggle/chevron
- `lib/features/settings/presentation/widgets/settings_section_header.dart` — `// SECTION NAME` pattern using JetBrains Mono label style

### Step 4: Implement Account Section with Logout

**File:** `lib/features/settings/presentation/sections/account_section.dart`

- Display user avatar (from Matrix profile via `client.ownProfile`)
- Display name (editable)
- Matrix ID (`@user:server.tld`)
- Logout button styled with `GloamColors.danger` — triggers `ref.read(authProvider.notifier).logout()` with confirmation dialog
- Session info: device name, device ID

### Step 5: Implement Encryption Section

**File:** `lib/features/settings/presentation/sections/encryption_section.dart`

- Key backup status (enabled/disabled, last backup time)
- "Unlock message history" button that opens existing `RecoveryKeyDialog`
- Cross-signing status (verified/unverified)
- Device list: all sessions, with verify/remove actions
- Export/import keys

### Step 6: Wire Up Mobile Settings Tab

**File:** `lib/app/shell/mobile_tabs.dart`

- Replace `_PlaceholderTab(label: 'settings')` with the settings content rendered inline, or trigger the same modal
- Reuse `SettingsContent` widget from the modal internals

### Step 7: State Management

**File to create:** `lib/features/settings/presentation/providers/settings_provider.dart`

- `settingsNavProvider` — tracks which section is selected in the sidebar
- Appearance preferences (theme mode, accent color) can use a `SharedPreferences`-backed provider
- No complex state needed — most settings read/write directly to Matrix SDK or local prefs

### Step 8: Add Keyboard Shortcut

**File:** `lib/app/shortcuts.dart`

- Add `SettingsIntent` and bind to `Cmd+,` (macOS standard) / `Ctrl+,`
- Wire up in `home_screen.dart` `Actions` block

### New Dependencies

- None required. `SharedPreferences` is likely already available or can be added for local preferences (flag for confirmation if needed).

### Edge Cases

- **Logout while syncing:** Ensure logout cancels any in-flight sync and clears local database
- **No network:** Server section should show connection state gracefully, not crash
- **Encryption not initialized:** Guard encryption section behind `client.encryption != null` check (pattern already exists in `RecoveryKeyDialog`)
- **Display name update failure:** Show error inline, don't lose the user's input
- **Multiple devices:** Device list can be long — needs virtual scrolling or lazy loading
- **Mobile keyboard:** Settings forms (display name edit) should handle keyboard overlay correctly
- **Dark/light theme toggle:** If appearance section includes theme switching, the modal itself must reactively update

---

## Acceptance Criteria

- [ ] Gear/avatar button visible at bottom of space rail, below the `+` button, on desktop and tablet
- [ ] Tapping the button opens a full-screen settings overlay with smooth transition
- [ ] Settings overlay has sidebar navigation (desktop) with sections: Account, Appearance, Notifications, Encryption & Security, Server, About
- [ ] Account section displays user avatar, display name, Matrix ID, and device info
- [ ] Logout button with confirmation dialog correctly logs out and returns to sign-in screen
- [ ] Encryption section shows key backup status and integrates existing recovery key dialog
- [ ] Server section displays homeserver URL and connection status
- [ ] Escape key or close button dismisses the modal
- [ ] `Cmd+,` / `Ctrl+,` keyboard shortcut opens settings
- [ ] Mobile settings tab renders settings content (not a placeholder)
- [ ] All settings UI follows Gloam design system: `//` section headers, green-tinted palette, correct typography
- [ ] Settings panel works on all target platforms (macOS, iOS, Android, Windows, Linux)

---

## Related

- `lib/app/shell/space_rail.dart` — settings button placement
- `lib/app/shell/mobile_tabs.dart` — mobile settings tab (currently placeholder)
- `lib/features/settings/presentation/recovery_key_dialog.dart` — existing encryption UI to integrate
- `lib/features/auth/presentation/providers/auth_provider.dart` — logout flow
- `lib/services/matrix_service.dart` — client access, server info, logout
- `docs/plan/09-design-system.md` — design tokens, typography, section header pattern
- `COMPETITIVE_ANALYSIS.md` — Discord/Element X settings UX patterns
