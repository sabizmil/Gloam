# Phase 0: Foundation

**Weeks 1–4 | Milestone: Log into a Matrix account and see a room list**

---

## Objectives

1. Establish the Flutter project structure, build tooling, and CI/CD pipeline for all 5 target platforms
2. Integrate matrix_dart_sdk with Sliding Sync and encrypted key storage
3. Implement the complete authentication flow (OIDC + legacy password + SSO)
4. Build the design system foundation (color tokens, typography, density modes)
5. Render a basic room list with real data from a Matrix homeserver

## Success Criteria

- [ ] `flutter run` works on iOS, Android, macOS, Windows, and Linux from a single codebase
- [ ] CI builds and runs tests for all 5 platforms on every push
- [ ] A user can sign in via OIDC (MAS), legacy password, or SSO (Google/Apple/GitHub)
- [ ] A new account can be created with automatic cross-signing key generation
- [ ] The room list loads via Sliding Sync in under 2 seconds on a test account with 50+ rooms
- [ ] The app renders using the Gloam design system (dark theme, correct typography, correct color tokens)
- [ ] Secrets (access tokens, cross-signing keys) are stored in platform keychain, not plaintext

---

## Task Breakdown

### 1. Project Scaffolding — Complexity: Low

**Duration:** 2–3 days

**Work:**
- `flutter create --org chat.gloam gloam` with all 5 platform targets enabled
- Establish feature-module directory structure:

```
lib/
├── app/                    # App entry, routing, theme
│   ├── app.dart
│   ├── router.dart
│   └── theme/
│       ├── gloam_theme.dart
│       ├── color_tokens.dart
│       ├── typography.dart
│       └── density.dart
├── core/                   # Shared utilities, constants, extensions
│   ├── extensions/
│   ├── utils/
│   ├── errors/
│   └── constants.dart
├── features/               # Feature modules (clean architecture per feature)
│   ├── auth/
│   │   ├── data/           # Repository implementations, data sources
│   │   ├── domain/         # Models, repository interfaces, use cases
│   │   └── presentation/   # Screens, widgets, Riverpod providers
│   ├── chat/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │       ├── screens/
│   │       ├── widgets/
│   │       └── providers/
│   ├── rooms/
│   ├── spaces/
│   ├── search/
│   ├── calls/
│   ├── settings/
│   └── onboarding/
├── services/               # SDK abstraction layer
│   ├── matrix_service.dart
│   ├── sync_service.dart
│   ├── crypto_service.dart
│   ├── media_service.dart
│   ├── notification_service.dart
│   └── search_service.dart
└── widgets/                # Shared UI components
    ├── avatar.dart
    ├── badge.dart
    └── ...
```

- Configure platform-specific settings:
  - **iOS/macOS:** Bundle identifiers (`chat.gloam.app`), minimum deployment targets (iOS 16+, macOS 13+), entitlements (keychain sharing, push notifications, network)
  - **Android:** Application ID (`chat.gloam.app`), min SDK 24 (Android 7.0), network security config, ProGuard rules
  - **Windows:** MSIX packaging config, app identity
  - **Linux:** Desktop file, AppImage/Flatpak config
- Set up analysis_options.yaml with strict linting (flutter_lints + custom rules)
- Create `.vscode/` and `.idea/` launch configs for all platforms

**Output:** A clean, building Flutter project with the full directory skeleton and platform configs.

---

### 2. Dependency Setup — Complexity: Low

**Duration:** 1–2 days

**Work:**

Pin all dependencies in `pubspec.yaml` with exact versions to ensure reproducible builds:

| Package | Purpose | Notes |
|---------|---------|-------|
| `matrix` (matrix_dart_sdk) | Matrix protocol client | Core SDK — rooms, sync, events, media |
| `flutter_riverpod` + `riverpod_annotation` + `riverpod_generator` | State management | Code-generated providers |
| `drift` + `sqlite3_flutter_libs` + `drift_dev` | Local database | Type-safe SQLite with reactive queries |
| `go_router` | Navigation/routing | Declarative routes, deep links |
| `dio` | HTTP client | Retries, interceptors, logging |
| `flutter_secure_storage` | Encrypted key storage | Platform keychain abstraction |
| `cached_network_image` | Image caching | LRU disk cache for avatars and media |
| `freezed` + `freezed_annotation` + `json_serializable` | Immutable models | Code-generated data classes |
| `flutter_local_notifications` | Local notifications | Desktop notification support |
| `url_launcher` | URL handling | Open links in browser |
| `path_provider` | File system paths | Platform-specific directories |
| `build_runner` | Code generation | Riverpod, freezed, drift, json_serializable |
| `mockito` + `mocktail` | Test mocking | Unit and widget test support |
| `integration_test` | Integration testing | Platform integration tests |

- Run `flutter pub get` and verify resolution on all platforms
- Run `dart run build_runner build` to verify code generation pipeline works
- Verify native dependencies compile (sqlite3_flutter_libs on all platforms, flutter_secure_storage native modules)

**Output:** All dependencies resolve and build successfully on all 5 platforms. Code generation pipeline is functional.

---

### 3. Theme Engine & Design System Foundation — Complexity: Medium

**Duration:** 3–4 days

**Work:**

Build the custom theme engine that powers Gloam's visual identity. Dark-mode-first, with light mode as a secondary target.

#### Color Tokens

Define all semantic color tokens as Dart constants. These are the canonical values — every widget references tokens, never raw hex values.

| Token | Dark Value | Purpose |
|-------|-----------|---------|
| `background` | `#080F0A` | App background, deepest layer |
| `backgroundSurface` | `#0D1610` | Cards, panels, elevated surfaces |
| `backgroundSurfaceHover` | `#121D15` | Surface hover state |
| `backgroundSurfaceActive` | `#17241A` | Surface active/pressed state |
| `backgroundOverlay` | `#0D1610CC` | Modal overlays (80% opacity) |
| `border` | `#1E2D22` | Default borders, dividers |
| `borderSubtle` | `#162119` | Subtle separators, low-emphasis borders |
| `borderFocus` | `#3B7A57` | Focus rings, active input borders |
| `textPrimary` | `#E8F0EA` | Primary text, headings |
| `textSecondary` | `#9BB0A0` | Secondary text, labels, timestamps |
| `textMuted` | `#5A7360` | Disabled text, placeholders |
| `textLink` | `#6BC492` | Hyperlinks, interactive text |
| `accentPrimary` | `#3B7A57` | Primary actions, active states, brand accent |
| `accentPrimaryHover` | `#4A9168` | Primary accent hover |
| `accentSecondary` | `#2D5E43` | Secondary buttons, less prominent actions |
| `statusError` | `#C45B5B` | Errors, destructive actions |
| `statusWarning` | `#C4A35B` | Warnings, caution states |
| `statusSuccess` | `#5BC47A` | Success confirmations, online presence |

#### Typography

Three typeface families, each with a distinct role:

| Family | Typeface | Role | Weights |
|--------|----------|------|---------|
| Display | **Spectral** | Headings, room names, the Gloam wordmark | 400, 500, 600, 700 |
| Body | **Inter** | Message text, UI labels, navigation | 400, 500, 600 |
| Code | **JetBrains Mono** | Code blocks, inline code, monospace content | 400, 500 |

Type scale (body size as base):

| Style | Family | Size | Weight | Line Height | Letter Spacing | Usage |
|-------|--------|------|--------|-------------|----------------|-------|
| `displayLarge` | Spectral | 28px | 600 | 1.2 | -0.02em | Space headers |
| `displayMedium` | Spectral | 22px | 600 | 1.25 | -0.01em | Room names in header |
| `displaySmall` | Spectral | 18px | 500 | 1.3 | 0 | Section titles |
| `bodyLarge` | Inter | 15px | 400 | 1.5 | 0 | Message text |
| `bodyMedium` | Inter | 13px | 400 | 1.45 | 0 | UI labels, room list items |
| `bodySmall` | Inter | 11px | 400 | 1.4 | 0.01em | Timestamps, metadata |
| `labelMedium` | Inter | 12px | 500 | 1.3 | 0.02em | Button labels, badges |
| `codeLarge` | JetBrains Mono | 14px | 400 | 1.6 | 0 | Code blocks |
| `codeSmall` | JetBrains Mono | 12px | 400 | 1.5 | 0 | Inline code |

#### Density Modes

Two density modes that adjust spacing and sizing globally:

| Mode | Base Unit | Message Padding | Avatar Size | Room List Item Height |
|------|-----------|----------------|-------------|----------------------|
| **Compact** | 4px | 4px 12px | 28px | 36px |
| **Comfortable** | 6px | 8px 16px | 36px | 48px |

Default: Compact on desktop, Comfortable on mobile/tablet. User-switchable.

#### Implementation

- `GloamTheme` class wrapping `ThemeData` with Gloam-specific extensions
- `GloamColorTokens` as a `ThemeExtension<GloamColorTokens>` so tokens are accessible via `Theme.of(context).extension<GloamColorTokens>()`
- `GloamTypography` similarly as a theme extension
- `GloamDensity` enum (compact/comfortable) stored in Riverpod provider, persisted to local storage
- Dark and light `ThemeData` factories
- Font assets bundled (Spectral, Inter, JetBrains Mono — all open-source, SIL OFL)

**Output:** A theme engine that produces the correct Gloam aesthetic when applied to any Flutter widget. A simple test screen showing all tokens, type styles, and density modes.

---

### 4. matrix_dart_sdk Integration — Complexity: High

**Duration:** 5–7 days

**Work:**

This is the core of Phase 0. Build the service layer that wraps matrix_dart_sdk and exposes a clean API to the rest of the app.

#### MatrixService

The central singleton managing the SDK `Client` instance:

```dart
// Conceptual interface — not literal code
abstract class MatrixService {
  /// Current connection state (stream)
  Stream<ConnectionState> get connectionState;

  /// Initialize the SDK with stored credentials (if any)
  Future<void> initialize();

  /// Login with credentials, returns the logged-in Client
  Future<Client> login({required LoginCredentials credentials});

  /// Logout and clear local state
  Future<void> logout();

  /// The underlying matrix_dart_sdk Client (for direct access when needed)
  Client? get client;
}
```

#### Sliding Sync Configuration

- Enable Simplified Sliding Sync (MSC4186) as the primary sync mode
- Configure the initial sliding window: request the first 20 rooms with `required_state` (name, avatar, canonical alias, encryption) and `timeline_limit: 1` (latest message for preview)
- Implement window expansion as the user scrolls the room list
- Detect homeserver Sliding Sync support; if unsupported, fall back to sync v2 with a user-facing banner suggesting they ask their admin to upgrade
- Cache sync state to SQLite (via drift) so the room list loads instantly on subsequent app launches

#### Connection State Machine

```
Disconnected → Connecting → Connected → Syncing → Synced
                    ↓                      ↓
                ConnectError           SyncError
                    ↓                      ↓
              Reconnecting (exponential backoff)
```

- Expose connection state as a Riverpod `StreamProvider` so UI can react (show reconnection banner, etc.)
- Automatic reconnection with exponential backoff (1s, 2s, 4s, 8s, max 60s)
- Network reachability listener — attempt reconnect immediately on network restore

#### Encrypted Key Storage

- Store access token, refresh token, and device keys in `flutter_secure_storage` (platform keychain)
- Never write secrets to plaintext files, SharedPreferences, or drift database
- On app launch, attempt to restore session from keychain → if valid, skip login → initialize SDK → start sync
- On logout, wipe all keychain entries for this account

#### Database Layer

- Configure drift with a `GloamDatabase` class
- Initial tables for Phase 0:
  - `accounts` — stored account metadata (user ID, device ID, homeserver URL)
  - `sync_cache` — serialized sync state for fast restarts
  - `room_cache` — room metadata (name, avatar URL, last event preview, unread count)
- Database file stored in `path_provider`'s application support directory
- Encryption at rest via SQLCipher (stretch goal — evaluate performance impact first)

**Output:** The app can initialize the SDK, connect to a homeserver, authenticate, and maintain a persistent sync connection. Session survives app restarts via keychain + cached sync state.

---

### 5. Authentication Flow — Complexity: Medium

**Duration:** 4–5 days

**Work:**

Implement the full authentication UI and logic. The goal is "under 60 seconds from app open to first message."

#### Login Methods

1. **OIDC via Matrix Authentication Service (MAS)**
   - Detect OIDC support via `.well-known/matrix/client` → `m.authentication` field
   - Initiate OIDC Authorization Code Flow with PKCE
   - Open system browser for provider login (not an in-app WebView — security best practice)
   - Handle redirect URI callback to receive authorization code
   - Exchange code for access token + refresh token
   - Store tokens in keychain

2. **Legacy Password Authentication**
   - Standard `m.login.password` flow for homeservers without OIDC
   - Email/username + password form
   - Support `m.login.recaptcha` and `m.login.terms` interactive auth stages

3. **SSO Providers**
   - Google Sign-In, Apple Sign-In, GitHub OAuth
   - These flow through the homeserver's SSO configuration — the client opens the SSO URL in a browser, receives a login token via redirect
   - Apple Sign-In uses native `AuthenticationServices` on iOS/macOS for the best UX

4. **Account Creation**
   - Register flow via `m.login.registration_token` or open registration
   - Email verification stage
   - Display name + avatar setup
   - **Automatic cross-signing key generation** — immediately after account creation, generate and upload cross-signing keys silently. The user never sees this.
   - Generate recovery phrase (12-word BIP39-style mnemonic), present to user once with a "Save this — you'll need it to recover your messages on a new device" prompt
   - Store recovery phrase in platform keychain as a backup

#### Homeserver Selection

- Default to `matrix.org` — no server picker on the initial screen
- "Use your own server" link at the bottom of the login screen
- When tapped, show a single text field for homeserver URL
- Validate via `.well-known` lookup + server capabilities check
- Remember the last-used homeserver

#### UI Screens

1. **Welcome Screen** — Gloam logo + tagline, "Sign In" and "Create Account" buttons, "Use your own server" link at bottom
2. **Sign In Screen** — Email/username field, password field, SSO buttons (Google/Apple/GitHub), "Forgot password" link
3. **Create Account Screen** — Display name, email, password, terms acceptance
4. **Recovery Phrase Screen** — Show generated 12-word phrase, "I've saved this" confirmation button
5. **Loading Screen** — After auth, show Gloam logo with progress indicator while initial sync completes

#### Error Handling

- Invalid credentials → inline field error, not a modal
- Network unreachable → "Can't reach [homeserver]. Check your connection."
- Homeserver doesn't support OIDC → silently fall back to legacy password flow
- Rate limited → "Too many attempts. Try again in X seconds."
- CAPTCHA required → embedded CAPTCHA widget

**Output:** A complete auth flow that handles OIDC, password, and SSO across all target homeservers. New accounts get automatic cross-signing setup.

---

### 6. Basic Room List — Complexity: Medium

**Duration:** 3–4 days

**Work:**

Render the room list with real data from Sliding Sync. This is the first thing users see after login — it must be fast and feel polished even in Phase 0.

#### Data Flow

```
Sliding Sync response
  → matrix_dart_sdk parses rooms
  → RoomListProvider (Riverpod) transforms to RoomListItem models
  → RoomListScreen renders via SliverList
```

#### RoomListItem Model

```dart
// Conceptual model
class RoomListItem {
  final String roomId;
  final String displayName;
  final String? avatarUrl;        // MXC URI
  final String? lastMessagePreview; // "Alice: Hey, are you..." (truncated)
  final String? lastMessageSender;
  final DateTime? lastMessageTimestamp;
  final int unreadCount;
  final int mentionCount;
  final bool isEncrypted;
  final bool isDirect;            // DM vs. group room
  final RoomMembership membership; // join, invite, leave
}
```

#### Room List Features (Phase 0 scope)

- **Virtualized scrolling** — `SliverList` with `itemExtent` estimates. Only build widgets for visible rooms + a small buffer. Must handle 500+ rooms without frame drops.
- **Unread counts** — Numeric badge showing unread message count. Separate mention badge (@ symbol) when the user is mentioned.
- **Avatars** — Room avatar (if set) or generated fallback (first letter of room name on a deterministic color background). Circular, sized per density mode.
- **Last message preview** — "[Sender]: [message text]" truncated to one line. Show "Encrypted message" for E2EE rooms where preview isn't available.
- **Timestamps** — Relative ("2m", "1h", "Yesterday", "Mar 20"). Update periodically.
- **Sort order** — By most recent activity (last event timestamp), descending.
- **Pull to refresh** — Trigger a sync bump (mobile).
- **Empty state** — "No conversations yet" with a prompt to start a DM or join a room.

#### Room List Item Widget

Each item shows: avatar (left) | name + last message preview (center) | timestamp + unread badge (right). Single tap opens the room (Phase 1). The entire row is a tap target with hover state on desktop.

#### Invite Handling

- Invites render at the top of the room list with a distinct visual treatment (accent border, "Invited" label)
- Accept/decline buttons inline (no separate screen needed)

**Output:** A scrollable, virtualized room list that loads within 2 seconds via Sliding Sync, shows accurate unread counts and message previews, and handles 500+ rooms smoothly.

---

### 7. CI/CD Pipeline — Complexity: Medium

**Duration:** 2–3 days

**Work:**

Set up GitHub Actions to build, test, and package the app for all 5 platforms.

#### GitHub Actions Workflows

**On every push/PR:**
1. `analyze` — `dart analyze` + `dart format --set-exit-if-changed`
2. `test` — `flutter test` (unit + widget tests)
3. `build-android` — `flutter build apk --debug` (verify it compiles)
4. `build-ios` — `flutter build ios --no-codesign --debug` (verify it compiles, no signing)
5. `build-macos` — `flutter build macos --debug`
6. `build-windows` — `flutter build windows --debug` (Windows runner)
7. `build-linux` — `flutter build linux --debug`

**On tag/release:**
1. `release-android` — Signed APK + AAB via Fastlane → internal track on Google Play
2. `release-ios` — Signed IPA via Fastlane → TestFlight
3. `release-macos` — Signed .app via Fastlane → TestFlight (macOS)
4. `release-windows` — MSIX package → GitHub Releases
5. `release-linux` — AppImage + Flatpak → GitHub Releases

#### Fastlane Configuration

- `fastlane/Fastfile` with lanes for iOS, Android, macOS
- Match (iOS) or manual certificate management for code signing
- Secrets stored in GitHub Actions secrets (signing keys, API keys, keystore passwords)

#### Caching

- Cache `~/.pub-cache` and `.dart_tool` across runs
- Cache Gradle dependencies (Android)
- Cache CocoaPods (iOS/macOS)

#### Quality Gates

- No PR merges if `analyze` or `test` fails
- Build checks are required but allowed to be yellow (compiler warnings are tracked, not blocking initially)

**Output:** Every push triggers analysis + tests. All 5 platform builds verify compilation. Tagged releases produce signed artifacts for distribution.

---

## Dependencies & Blockers

| Dependency | Required By | Status | Risk |
|------------|-------------|--------|------|
| matrix_dart_sdk Sliding Sync support | Task 4 | Supported via MSC4186 | Low — FluffyChat already uses this |
| flutter_vodozemac package availability | Task 4 | Published on pub.dev | Low |
| Apple Developer Account | Task 7 (iOS/macOS signing) | Needs enrollment | Medium — can take days |
| Google Play Console | Task 7 (Android release) | Needs setup | Low |
| GitHub Actions macOS runner | Task 7 | Available (macOS 14+ runners) | Low |
| GitHub Actions Windows runner | Task 7 | Available | Low |
| Homeserver with OIDC (MAS) for testing | Task 5 | matrix.org supports MAS | Low |
| Font licenses (Spectral, Inter, JetBrains Mono) | Task 3 | All SIL Open Font License | None |

## Key Technical Decisions to Make During Phase 0

| Decision | Options | Recommendation | Decide By |
|----------|---------|----------------|-----------|
| SQLCipher for database encryption at rest | SQLCipher (encrypted) vs. plain SQLite | Start with plain SQLite; add SQLCipher in Phase 1 if performance impact is acceptable | End of Week 2 |
| Code generation strategy | build_runner on-demand vs. watch mode | On-demand in CI, watch mode in dev | Week 1 |
| Riverpod generator vs. manual | Generated providers vs. hand-written | Generated — ensures consistency and catches errors at compile time | Week 1 |
| Multi-account data isolation | Separate databases per account vs. shared database with account column | Separate databases — cleaner isolation, simpler queries, no cross-account data leaks | Week 2 |
| Web target priority | Include web in CI or defer | Defer — web is a bonus target. Native desktop builds are priority. | Week 1 |

---

## What "Done" Looks Like

At the end of Week 4, a tester can:

1. Open Gloam on any of the 5 target platforms
2. See a polished welcome screen with the Gloam visual identity (dark theme, Spectral headings, Inter body text)
3. Sign in via email/password, Google SSO, or Apple SSO
4. Alternatively, create a new Matrix account (with automatic cross-signing setup happening silently)
5. See their room list load in under 2 seconds, with correct room names, avatars, unread counts, and last message previews
6. See the room list scroll smoothly with 500+ rooms
7. Close and reopen the app — the room list appears instantly from cache, then updates from sync
8. The app is building and testing in CI for all 5 platforms on every push

What they **cannot** do yet: open a room, read messages, send messages, or navigate to any screen beyond the room list. That's Phase 1.
