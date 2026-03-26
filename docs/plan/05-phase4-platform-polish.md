# Phase 4: Platform Polish

**Weeks 19-22 | Depends on: Phase 3 (Search & Media)**

---

## Objectives

Make Gloam feel like it belongs on each platform. Flutter gives us one codebase, but "cross-platform" is not an excuse for generic. This phase adds platform-specific integrations (system tray, keyboard shortcuts, share extensions, widgets), refines the responsive layout, audits accessibility, and ensures the app feels considered on every OS. By the end, a macOS user should feel like Gloam was designed for their Mac, and an Android user should feel the same about their phone.

## Success Criteria

- macOS: Menu bar with standard keyboard shortcuts, system tray icon with unread badge, dock badge, notifications via Notification Center
- Windows: System tray with context menu, WinRT toast notifications, taskbar badge, jump list for recent rooms, MSIX installer
- Linux: StatusNotifierItem/AppIndicator tray, libnotify notifications, .desktop file with actions, Flatpak and/or Snap package
- iOS: Functional share extension for sending content to Gloam rooms, home screen widget showing unread summary, Spotlight search indexing for rooms/contacts, proper Dynamic Type scaling, iPad-optimized layout
- Android: Share target for receiving shared content, home screen widget, notification channels from Phase 2 fully refined, Material You dynamic color theming, predictive back gesture, foldable device support
- Responsive layout works correctly at all breakpoints with smooth transitions between phone/tablet/desktop modes
- Accessibility audit passes: VoiceOver (iOS/macOS), TalkBack (Android), screen reader support on Windows/Linux, WCAG 2.1 AA color contrast, proper focus management
- Keyboard shortcut system with discoverable help overlay (Cmd/Ctrl+/)

---

## Task Breakdown

### 1. macOS Polish

**Priority: Medium | Estimate: 4-5 days**

macOS users expect native menu bar integration, standard keyboard shortcuts, and system-level presence (dock, tray, notifications).

#### Implementation

**PlatformMenuBar:**
- Use Flutter's `PlatformMenuBar` widget to define native macOS menu bar
- Standard menus: App (About, Preferences, Quit), File (New Room, Close Window), Edit (standard text editing), View (Zoom, Toggle Sidebar), Window (Minimize, Zoom, Bring All to Front), Help
- Custom menus: Room (Room Settings, Leave Room), Navigate (Previous Room, Next Room, Quick Switcher)
- Menu items bound to the keyboard shortcut system (shared registration)

**Keyboard shortcuts (macOS-specific):**

| Shortcut | Action |
|----------|--------|
| Cmd+N | New room / New DM |
| Cmd+K | Quick switcher |
| Cmd+, | Preferences |
| Cmd+F | Search in room |
| Cmd+Shift+F | Global search |
| Cmd+[ / Cmd+] | Navigate back/forward |
| Cmd+1-9 | Switch to space 1-9 |
| Cmd+W | Close current panel / Close thread |
| Cmd+Q | Quit |
| Cmd+M | Minimize |
| Cmd+Shift+N | New window (future) |

**System tray (menu bar extra):**
- Use `tray_manager` or `system_tray` package
- Icon in macOS menu bar: monochrome Gloam icon
- Unread badge: red dot overlay on tray icon when there are unread mentions
- Click: bring app to front
- Right-click context menu: Show/Hide, DND toggle, Quit

**Dock badge:**
- Use `flutter_app_badger` or direct macOS API via method channel
- Show total unread mention count on dock icon
- Clear badge when all mentions are read

**Notification Center:**
- Notifications delivered via `flutter_local_notifications` with macOS support
- Category actions: Reply, Mark as Read
- Notification grouping by room (thread identifier)
- Clicking notification activates app and navigates to room/message

**macOS-specific UI adjustments:**
- Title bar: transparent, with traffic lights integrated into the space rail area
- Window chrome: native macOS window with custom content area
- Scroll physics: macOS momentum scrolling (already handled by Flutter)
- Right-click context menus throughout (messages, rooms, members)
- Drag and drop: accept files dropped onto the app window → upload to current room

#### Subtasks

- [ ] Implement `PlatformMenuBar` with all standard + custom menus
- [ ] Bind menu items to keyboard shortcut actions
- [ ] System tray integration with `tray_manager` (icon, badge, context menu)
- [ ] Dock badge via `flutter_app_badger`
- [ ] Notification Center integration with action buttons
- [ ] Transparent title bar with traffic light positioning
- [ ] Right-click context menus for messages, rooms, members
- [ ] File drag-and-drop handling
- [ ] Test on macOS 13+ (Ventura and later)

---

### 2. Windows Polish

**Priority: Medium | Estimate: 4-5 days**

Windows users expect taskbar integration, system tray, and native notification toasts.

#### Implementation

**System tray:**
- Use `system_tray` package (Windows support)
- Gloam icon in system tray (notification area)
- Left-click: show/hide app window
- Right-click: context menu (Show, DND toggle, Quit)
- Unread badge overlay on tray icon
- Option to minimize to tray instead of taskbar (configurable)

**WinRT toast notifications:**
- Use `flutter_local_notifications` or `windows_notification` for WinRT toasts
- Rich notifications with sender avatar, room name, message preview
- Action buttons: Reply (inline text input in toast), Mark as Read
- Notification grouping by room
- Clicking toast activates app + navigates to room/message

**Taskbar badge:**
- Overlay badge on taskbar icon showing unread mention count
- Use Win32 `ITaskbarList3::SetOverlayIcon` via method channel or `flutter_app_badger`
- Flash taskbar button on new mention (attention request)

**Jump list:**
- Recent rooms in the Windows jump list (right-click taskbar icon)
- Pinned rooms available as jump list items
- Use `win32` package or `msix` configuration for jump list

**Window management:**
- Remember window position and size between launches
- Snap layout support (Windows 11 snap zones)
- Proper DPI handling (Flutter handles this, but test at 125%, 150%, 200% scaling)

**MSIX packaging:**
- Package as MSIX for Microsoft Store distribution and clean install/uninstall
- Auto-update support via Store or custom update mechanism
- Code signing with a certificate
- Proper app identity for notifications and jump list

**Windows-specific UI:**
- Window title bar: custom (match app theme) or system (for snap layout compatibility)
- Decision: use system title bar for best Windows 11 snap layout integration
- Acrylic/Mica backdrop (Windows 11) — investigate `flutter_acrylic` package for window material
- Context menus match Windows styling

#### Subtasks

- [ ] System tray with `system_tray` (icon, badge, context menu, minimize-to-tray)
- [ ] WinRT toast notifications with reply action
- [ ] Taskbar badge overlay for unread count
- [ ] Taskbar flash on new mention
- [ ] Jump list with recent rooms
- [ ] Window position/size persistence
- [ ] MSIX packaging configuration
- [ ] DPI scaling testing at common scale factors
- [ ] Acrylic/Mica backdrop investigation and implementation
- [ ] Test on Windows 10 21H2+ and Windows 11

---

### 3. Linux Polish

**Priority: Medium | Estimate: 3-4 days**

Linux desktop users expect D-Bus integration, standard notification delivery, and proper packaging.

#### Implementation

**System tray:**
- Use StatusNotifierItem (SNI) protocol — the modern Linux tray standard
- Fallback to AppIndicator for GNOME (via `libappindicator`)
- `system_tray` or `tray_manager` package (check Linux support)
- Tray icon with unread badge
- Click: show/hide window
- Context menu: Show, DND toggle, Quit

**Notifications:**
- Use `libnotify` via D-Bus (`org.freedesktop.Notifications`)
- `flutter_local_notifications` handles this on Linux
- Notification actions: Reply, Mark as Read (if notification server supports actions)
- Notification grouping (if supported by notification daemon)
- Respect system notification settings (DND, priority)

**.desktop file:**
- Proper `.desktop` entry for application launcher
- Categories: Network;InstantMessaging;Chat
- Actions: New Message, Open Room (for desktop entry actions)
- MIME type handling for `matrix:` URIs
- StartupWMClass for proper taskbar grouping

**Packaging:**

| Format | Target | Notes |
|--------|--------|-------|
| Flatpak | Primary | Sandboxed, wide compatibility, Flathub distribution |
| Snap | Secondary | Ubuntu-friendly, auto-updates |
| AppImage | Fallback | Single-file portable, no sandboxing |
| .deb / .rpm | Optional | For users who prefer native packages |

**Flatpak considerations:**
- Portal APIs for file picker, notifications, secrets (Keyring)
- Flatpak sandbox means `flutter_secure_storage` needs `org.freedesktop.secrets` portal
- Test with and without portals

**Linux-specific UI:**
- Follow system theme for window decorations (CSD vs SSD — use Flutter's CSD)
- Respect `GTK_THEME` / `QT_STYLE_OVERRIDE` for dark mode detection
- XDG directories for config (`~/.config/gloam`), data (`~/.local/share/gloam`), cache (`~/.cache/gloam`)

#### Subtasks

- [ ] StatusNotifierItem/AppIndicator tray integration
- [ ] libnotify notifications via `flutter_local_notifications`
- [ ] .desktop file with proper categories, actions, and MIME types
- [ ] Flatpak manifest and build configuration
- [ ] Snap configuration (snapcraft.yaml)
- [ ] AppImage build script
- [ ] XDG base directory compliance
- [ ] Dark mode detection from system theme
- [ ] Test on GNOME, KDE, and at least one tiling WM (Sway/i3)

---

### 4. iOS Polish

**Priority: High | Estimate: 6-8 days**

iOS is likely the highest-traffic mobile platform. Share extension, widgets, and Spotlight make the app feel deeply integrated.

#### Implementation

**Share extension:**
- Native iOS share extension (Swift) that lets users share content TO Gloam from other apps
- Content types: text, URLs, images, videos, files
- Flow: user shares → extension shows room picker → user selects room → content sent
- E2EE: share extension must encrypt content before sending

**Share extension architecture (critical decision):**
- Share extension runs in a separate process with 120MB memory limit
- Cannot run full Flutter engine — too heavy
- **Approach 1: Native Swift extension + shared SDK state**
  - Extension reads logged-in session from App Group shared storage
  - Uses matrix_dart_sdk's Dart FFI... no, can't run Dart in extension easily
  - Use a lightweight HTTP client to send via Matrix client-server API directly
  - Encrypt with vodozemac Swift bindings if room is encrypted
  - Share crypto state via App Group (same as NSE from Phase 2)
- **Approach 2: Native Swift extension that queues, main app sends**
  - Extension saves shared content to App Group shared container
  - Main app picks up queued content on next launch/foreground
  - Simpler but not instant — user has to wait

**Chosen: Approach 1 with fallback to Approach 2.** Try to send immediately from the extension. If encryption state is unavailable or sending fails, queue for the main app.

**Home screen widget (WidgetKit):**
- Small widget (2x2): unread count badge + Gloam icon
- Medium widget (4x2): list of rooms with unread messages (room name + count, up to 4 rooms)
- Widget updates on:
  - App foreground/background transitions (via `WidgetCenter.shared.reloadAllTimelines()`)
  - Background app refresh (limited — iOS controls frequency)
  - Push notification receipt (NSE can trigger widget update)
- Data shared via App Group (write latest unread state from main app + NSE)
- Tapping a room in the widget deep links to that room

**Spotlight search (Core Spotlight):**
- Index rooms and contacts into Core Spotlight (`CSSearchableItem`)
- Index on app launch and incrementally as rooms/contacts change
- Searchable attributes: room name, room alias, contact display name
- Tapping a Spotlight result opens Gloam and navigates to the room/contact
- Delete index entries when user leaves a room or removes a contact

**Haptics:**
- Light impact on message send (success feedback)
- Medium impact on long-press (context menu trigger)
- Selection feedback on picker scroll (emoji picker, room type selector)
- Use `HapticFeedback` from Flutter services

**Dynamic Type:**
- All text must scale with iOS Dynamic Type settings
- Use Flutter's `MediaQuery.textScaleFactorOf(context)` to respect system setting
- Test at all Dynamic Type sizes including Accessibility sizes (up to ~3.5x)
- Message bubbles, room list items, and headers must not break at large sizes
- Set minimum font size floors to prevent unreadably small text at small Dynamic Type

**iPad layout:**
- Detect iPad via screen size + device type
- Use the tablet breakpoint (600-900px) from Phase 2's AdaptiveShell
- iPad in landscape: three-column layout (space rail + room list + chat)
- iPad in portrait: two-column layout (room list + chat) with space rail in hamburger
- iPad multitasking: support Split View and Slide Over
- Pointer/trackpad support: hover states, right-click context menus (iPad + Magic Keyboard)

#### Subtasks

- [ ] Share extension: native Swift extension with App Group shared session
- [ ] Share extension: room picker UI (native SwiftUI, not Flutter)
- [ ] Share extension: direct send via Matrix API with encryption
- [ ] Share extension: fallback queue for failed/deferred sends
- [ ] WidgetKit: small and medium widget implementations (SwiftUI)
- [ ] WidgetKit: App Group data sharing for unread state
- [ ] WidgetKit: widget update triggers (app lifecycle, NSE)
- [ ] Core Spotlight: index rooms and contacts
- [ ] Core Spotlight: handle search result deep links
- [ ] Haptic feedback on key interactions
- [ ] Dynamic Type scaling audit and fixes across all screens
- [ ] iPad layout optimization (landscape 3-col, portrait 2-col)
- [ ] iPad Split View and Slide Over support
- [ ] iPad pointer/trackpad hover states and right-click menus

---

### 5. Android Polish

**Priority: Medium | Estimate: 5-6 days**

Android integration means share targets, widgets, Material You theming, and modern gesture support.

#### Implementation

**Share target:**
- Register Gloam as a share target in `AndroidManifest.xml`
- Accept: text/plain, image/*, video/*, application/* (files)
- Flutter's `receive_sharing_intent` package or custom platform channel
- Flow: user shares from another app → Gloam opens with shared content → room picker → send
- Unlike iOS, Android share targets run within the main app process — full Flutter engine available
- Encrypt and send using standard matrix_dart_sdk pipeline

**Home screen widget (Glance / RemoteViews):**
- Use Jetpack Glance (Compose-based widgets) or traditional RemoteViews
- Small widget: unread badge count
- Medium widget: list of unread rooms (name + count, up to 5)
- Widget updates via `WorkManager` periodic task or on push notification receipt
- Data source: read from main app's SQLite database (shared storage)
- Tapping widget item deep links to room
- `home_widget` Flutter package for widget ↔ Flutter communication

**Notification channels (refine from Phase 2):**

| Channel | Importance | Sound | Vibration |
|---------|-----------|-------|-----------|
| Direct Messages | High | Default | Yes |
| Mentions | High | Custom | Yes |
| Room Messages | Default | Default | No |
| Calls | Max (heads-up) | Ringtone | Yes |
| System | Low | None | No |

- Users can configure each channel independently in Android system settings
- Notification dots on app icon (Android 8+)
- Bubbles for DM conversations (Android 11+) — investigate `flutter_local_notifications` bubble support

**Material You (Dynamic Color):**
- Use `dynamic_color` package to extract system wallpaper colors
- Apply dynamic color to Gloam's theme as an option (Settings → Theme → "Match system colors")
- Default: Gloam's own color palette. Material You is opt-in.
- Ensure all custom UI components respect the active color scheme
- Test with various wallpapers and both light/dark modes

**Predictive back gesture:**
- Android 14+ predictive back: system peeks at the previous screen during back gesture
- Flutter supports this via `PopScope` widget (replacement for `WillPopScope`)
- Ensure all navigation transitions support predictive back animation
- Test on Android 14+ devices with "Predictive back animations" developer option enabled

**Foldable device support:**
- Detect fold state using `MediaQuery` or `window_manager` package
- When unfolded (tablet-size inner display): use tablet layout from AdaptiveShell
- When folded (narrow outer display): use phone layout
- Handle fold/unfold transitions smoothly (layout recalculates without losing state)
- Flex mode (half-folded): consider using top half for chat, bottom half for composer (explore, not required)
- Test on Samsung Galaxy Fold emulator profile

**Android-specific UI:**
- Edge-to-edge rendering: draw behind system bars, handle insets properly
- Transparent navigation bar with gesture navigation
- Material 3 components where appropriate (buttons, text fields, bottom sheets)
- Splash screen via `flutter_native_splash` with proper theme

#### Subtasks

- [ ] Share target registration in AndroidManifest and content handling
- [ ] Room picker for shared content, send via matrix_dart_sdk
- [ ] Home screen widget with `home_widget` package
- [ ] Widget data sharing from main app database
- [ ] Notification channel refinement (importance levels, custom sounds)
- [ ] Notification bubbles for DMs (Android 11+)
- [ ] Dynamic Color integration with `dynamic_color` package
- [ ] Predictive back gesture support with `PopScope`
- [ ] Foldable device detection and layout adaptation
- [ ] Edge-to-edge rendering and system bar inset handling
- [ ] Test on Android 10, 12, 14 and foldable emulator

---

### 6. Responsive Layout Refinement

**Priority: Medium | Estimate: 3-4 days | Depends on: Phase 2 AdaptiveShell**

The AdaptiveShell from Phase 2 established breakpoints. This task refines the transitions and handles edge cases.

#### Implementation

**Breakpoint refinement:**

| Breakpoint | Classification | Layout |
|------------|---------------|--------|
| < 600px | Phone | Single column, tab bar, stack navigation |
| 600-840px | Small tablet / large phone | Two columns (room list + chat), collapsible space rail |
| 840-1200px | Tablet landscape / small desktop | Three columns, right panel as overlay |
| > 1200px | Desktop | Three columns, right panel inline (splits chat area) |

**Orientation handling:**
- Tablet portrait → landscape: transition from 2-col to 3-col smoothly
- Animate column appearance/disappearance (300ms ease-in-out)
- Maintain scroll position and selection state across layout changes
- iPad rotation: re-layout without losing context (current room, scroll position)

**Keyboard handling:**
- Software keyboard appearance should not break layout
- Chat composer stays above keyboard (use `MediaQuery.viewInsetsOf(context)`)
- Room list does not shift when keyboard appears in chat area
- On tablets with hardware keyboard: no software keyboard resize

**Window resize (desktop):**
- Debounce layout recalculation during rapid resize (16ms — one frame)
- Column collapse thresholds match breakpoints
- Content does not overflow or clip during resize animation
- Minimum window size: 360px wide, 480px tall

**Split View (iPad / Samsung DeX):**
- App renders correctly at all Split View widths
- Narrow Split View (1/3 screen): phone layout
- Half Split View: tablet layout
- Wide Split View (2/3 screen): full desktop layout

#### Subtasks

- [ ] Refine breakpoint thresholds based on real device testing
- [ ] Animated column transitions on breakpoint change
- [ ] Orientation change testing (tablet portrait ↔ landscape)
- [ ] Software keyboard inset handling (no layout breakage)
- [ ] Desktop minimum window size enforcement
- [ ] iPad Split View and Slide Over layout testing
- [ ] Samsung DeX mode testing
- [ ] Maintain scroll position and selection across layout changes

---

### 7. Accessibility Audit

**Priority: Medium | Estimate: 4-5 days**

Accessibility is not optional. This is a systematic audit and fix pass, not a from-scratch implementation.

#### Implementation

**Screen reader support:**

| Platform | Screen Reader | Framework |
|----------|--------------|-----------|
| iOS | VoiceOver | `Semantics` widgets |
| macOS | VoiceOver | `Semantics` widgets |
| Android | TalkBack | `Semantics` widgets |
| Windows | Narrator / NVDA | Flutter's Windows accessibility bridge |
| Linux | Orca | Flutter's Linux accessibility (limited — test and document gaps) |

**Audit checklist:**

- [ ] All interactive elements have semantic labels (`Semantics` widget or `semanticLabel` parameter)
- [ ] Images have content descriptions (sender name + "sent an image" for chat images)
- [ ] Buttons have descriptive labels (not just icons — "Send message", "Open emoji picker", "Reply to message")
- [ ] Form fields have labels and hints
- [ ] Navigation landmarks: app bar, room list, chat area, composer are distinct regions
- [ ] Focus order follows visual order (top to bottom, left to right within columns)
- [ ] Custom widgets expose correct semantic roles (button, heading, list item, text field)
- [ ] Live regions: new messages announced by screen reader (`Semantics(liveRegion: true)` on message list)
- [ ] Modal dialogs trap focus and return focus on dismiss

**Color contrast (WCAG 2.1 AA):**
- Minimum 4.5:1 contrast ratio for normal text
- Minimum 3:1 for large text (>18pt or >14pt bold)
- Minimum 3:1 for UI components and graphical objects (icons, borders)
- Audit both dark and light themes
- Use automated tools (`accessibility_tools` package) plus manual spot checks
- Fix any violations — adjust color palette values as needed

**Focus management:**
- Visible focus indicators on all interactive elements (2px outline or highlight)
- Focus ring color contrasts with background (use accent color or white with dark outline)
- Tab order is logical: space rail → room list → chat area → composer → right panel
- When a room is selected, focus moves to the message list
- When a modal opens, focus moves to the modal. When it closes, focus returns to the trigger.
- No focus traps (except in modals)

**Reduce motion:**
- Respect `MediaQuery.disableAnimationsOf(context)` (maps to system "Reduce Motion" setting)
- When enabled: disable all decorative animations (message appear, reaction pop, panel slide)
- Keep functional animations (scroll, page transitions) but reduce their duration
- Crossfade instead of slide for panel transitions

**RTL (Right-to-Left) support:**
- Use `Directionality` widget and Flutter's built-in RTL support
- Test with Arabic and Hebrew locales
- Space rail stays on the left (it's not text-directional — it's a spatial landmark)
- Room list and chat area mirror correctly (text alignment, icons, padding)
- Message bubbles: sent messages on the left in RTL, received on the right
- Composer: text input direction follows content language

**Text scaling:**
- All text respects system text scale factor
- Test at 1.0x, 1.5x, 2.0x, and maximum accessibility scale
- UI elements grow to accommodate larger text (no clipping or overflow)
- Set `maxLines` and `overflow: TextOverflow.ellipsis` where appropriate to prevent layout explosion

#### Subtasks

- [ ] Audit all screens with VoiceOver (iOS) and TalkBack (Android)
- [ ] Add missing `Semantics` labels to all interactive elements
- [ ] Add content descriptions to all images and icons
- [ ] Fix focus order across all columns and panels
- [ ] Implement focus management for modals and navigation
- [ ] Color contrast audit (both themes) with automated tooling
- [ ] Fix contrast violations in color palette
- [ ] Add visible focus indicators to all interactive elements
- [ ] Implement reduce-motion support (disable decorative animations)
- [ ] RTL layout testing with Arabic locale
- [ ] Text scaling audit at 1x, 1.5x, 2x, max
- [ ] Test with Narrator/NVDA on Windows
- [ ] Document known accessibility gaps on Linux (Orca support)

---

### 8. Keyboard Shortcut System

**Priority: Low | Estimate: 3-4 days | Depends on: macOS PlatformMenuBar, all navigation tasks**

A global registry of keyboard shortcuts with a discoverable help overlay. Power users live on keyboard shortcuts.

#### Implementation

**Global shortcut registry:**
- Central `ShortcutRegistry` service (Riverpod provider)
- Each shortcut registered with: key combination, action callback, label, category
- Platform-correct modifiers: Cmd on macOS, Ctrl on Windows/Linux
- Shortcuts organized by category: Navigation, Messaging, Search, App

**Shortcut table:**

| Category | macOS | Windows/Linux | Action |
|----------|-------|---------------|--------|
| Navigation | Cmd+K | Ctrl+K | Quick switcher |
| Navigation | Cmd+1-9 | Ctrl+1-9 | Switch to space 1-9 |
| Navigation | Cmd+[ | Alt+Left | Previous room |
| Navigation | Cmd+] | Alt+Right | Next room |
| Navigation | Cmd+Shift+U | Ctrl+Shift+U | Jump to unread |
| Messaging | Cmd+Enter | Ctrl+Enter | Send message |
| Messaging | Cmd+Shift+E | Ctrl+Shift+E | Open emoji picker |
| Messaging | Up arrow | Up arrow | Edit last message (when composer empty) |
| Messaging | Cmd+Shift+R | Ctrl+Shift+R | Reply to last message |
| Search | Cmd+F | Ctrl+F | Search in room |
| Search | Cmd+Shift+F | Ctrl+Shift+F | Global search |
| App | Cmd+, | Ctrl+, | Settings |
| App | Cmd+/ | Ctrl+/ | Show shortcut help |
| App | Cmd+Shift+D | Ctrl+Shift+D | Toggle DND |

**Help overlay (Cmd/Ctrl+/):**
- Full-screen semi-transparent overlay (frosted glass backdrop)
- Organized by category in columns
- Each shortcut shows the key combination and description
- Search bar at top to filter shortcuts
- Press any shortcut to dismiss overlay and execute the action
- Press Escape or Cmd/Ctrl+/ to dismiss

**Implementation approach:**
- Use Flutter's `Shortcuts` and `Actions` widgets at the app level
- Register platform-aware `LogicalKeySet` (or `SingleActivator`) for each shortcut
- `ShortcutRegistry` maintains the mapping: `Map<ShortcutActivator, ShortcutEntry>`
- `ShortcutEntry` contains: label, category, callback
- Help overlay reads from the registry to build its display — single source of truth

**Conflict resolution:**
- Text input focus overrides shortcut system (typing in composer shouldn't trigger shortcuts)
- Modal dialogs have their own shortcut scope (Escape = dismiss)
- Shortcuts disabled when a text field is focused, except for explicitly allowed ones (Cmd+Enter, Cmd+K)

#### Subtasks

- [ ] Build `ShortcutRegistry` service with registration API
- [ ] Define all shortcut entries with platform-correct modifiers
- [ ] Wire shortcuts to `Shortcuts` + `Actions` widgets at app root
- [ ] Build help overlay widget (Cmd/Ctrl+/)
- [ ] Search/filter within help overlay
- [ ] Handle text field focus conflicts (disable shortcuts during text input)
- [ ] Integrate with macOS `PlatformMenuBar` (shared shortcut definitions)
- [ ] Test on macOS, Windows, Linux with different keyboard layouts
- [ ] Test with non-US keyboard layouts (shortcuts that rely on key position vs character)

---

## Dependencies

```
macOS Polish
  ├── Phase 2: Notification System (notification integration)
  ├── Phase 2: Desktop Layout Shell (title bar integration)
  └── Keyboard Shortcut System (menu bar bindings)

Windows Polish
  ├── Phase 2: Notification System (WinRT toasts)
  └── Keyboard Shortcut System

Linux Polish
  ├── Phase 2: Notification System (libnotify)
  └── Packaging infrastructure (CI/CD from Phase 0)

iOS Polish
  ├── Phase 2: Notification System (NSE — shared App Group)
  ├── Phase 2: AdaptiveShell (iPad layout)
  └── Phase 1: E2EE (share extension encryption)

Android Polish
  ├── Phase 2: Notification System (channels)
  ├── Phase 2: AdaptiveShell (foldable support)
  └── Phase 1: E2EE (share target encryption)

Responsive Layout Refinement
  └── Phase 2: AdaptiveShell (refines existing breakpoints)

Accessibility Audit
  ├── All previous phases (audits all existing UI)
  └── Platform-specific screen reader frameworks

Keyboard Shortcut System
  └── macOS Polish (PlatformMenuBar integration)
```

## New Dependencies Introduced

| Package | Purpose | Platforms | Notes |
|---------|---------|-----------|-------|
| `tray_manager` or `system_tray` | System tray icon and menu | macOS, Windows, Linux | Evaluate both; `system_tray` has broader platform support |
| `flutter_app_badger` | Dock/taskbar badge count | macOS, Windows, iOS, Android | Check macOS and Windows support quality |
| `dynamic_color` | Material You dynamic color | Android | Also works on macOS for accent color, but primarily Android |
| `home_widget` | Flutter ↔ home screen widget bridge | iOS, Android | Handles data sharing between Flutter and native widget |
| `receive_sharing_intent` | Receive shared content | Android, iOS (partial) | iOS share extension may need custom native code |
| `flutter_acrylic` | Window material (Mica/Acrylic) | Windows, macOS | Investigate vibrancy on macOS, Mica on Windows 11 |
| `accessibility_tools` | Automated accessibility checks | All | Dev-only dependency, overlay showing semantics issues |

## Key Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| iOS share extension | Native Swift, sends directly via Matrix API | Flutter engine too heavy for extension process; direct API call is fast and within memory limits |
| iOS widget | WidgetKit (SwiftUI) via `home_widget` | Standard iOS widget framework; data shared through App Group |
| Android widget | Jetpack Glance via `home_widget` | Modern Compose-based widget API, cleaner than RemoteViews |
| System tray package | `system_tray` (evaluate) | Cross-platform (macOS/Windows/Linux) from single package |
| Material You | Opt-in, not default | Gloam has its own design language; dynamic color is an option for users who want system integration |
| Windows title bar | System title bar (not custom) | Preserves Windows 11 snap layout integration, which is more valuable than custom styling |
| Linux packaging | Flatpak primary, Snap secondary | Flatpak has better sandboxing and wider distro support; Snap for Ubuntu convenience |
| Share extension encryption | Shared vodozemac state via App Group (iOS) / direct SDK (Android) | iOS needs lightweight native crypto; Android can use full Flutter engine |
| Keyboard shortcut scope | Disabled during text input except explicit exceptions | Prevents shortcut hijacking while typing; Cmd+Enter and Cmd+K are exceptions |
| Accessibility standard | WCAG 2.1 AA | Industry standard; AAA is aspirational but AA is the requirement |

## Definition of Done

Phase 4 is complete when:

1. **macOS:** Native menu bar with all shortcuts, system tray with badge, dock badge, Notification Center integration. App feels like a Mac app, not a cross-platform port.
2. **Windows:** System tray with minimize-to-tray, WinRT toast notifications with reply, taskbar badge, jump list. MSIX package builds and installs cleanly.
3. **Linux:** System tray works on GNOME and KDE, libnotify notifications fire, .desktop file is correct, Flatpak package builds and runs in sandbox.
4. **iOS:** Share extension sends content to rooms (including encrypted rooms). Home screen widget shows unread rooms. Spotlight indexes rooms and contacts. Dynamic Type scales correctly at all sizes. iPad layout is optimized for landscape and portrait.
5. **Android:** Share target receives content from other apps. Home screen widget shows unread state. Material You dynamic color works when enabled. Predictive back gesture animates correctly. Foldable devices transition between layouts smoothly.
6. **Responsive:** Layout transitions between breakpoints are smooth. No broken layouts at any window size or orientation. iPad Split View and Samsung DeX work.
7. **Accessibility:** VoiceOver and TalkBack navigate the entire app successfully. Color contrast meets WCAG 2.1 AA. Focus management is correct. Reduce motion is respected. RTL layout works.
8. **Keyboard shortcuts:** All documented shortcuts work with platform-correct modifiers. Help overlay shows all shortcuts. No conflicts with text input.
9. **The app feels native and considered on every platform it runs on.**
