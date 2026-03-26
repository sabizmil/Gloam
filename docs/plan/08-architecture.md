# Gloam — Technical Architecture

**Document:** 08-architecture.md
**Date:** 2026-03-25
**Status:** Planning

---

## 1. Stack Decisions

| Layer | Technology | Why This Over Alternatives |
|-------|-----------|---------------------------|
| **UI Framework** | Flutter 3.x | Single codebase for 5 platforms with total pixel control. Chat apps are mostly custom UI (message bubbles, composers, reaction pickers) where native widgets add little value. Impeller rendering engine delivers 40% CPU reduction on mobile. React Native's desktop story is weak (macOS/Windows are out-of-tree, no Expo). Tauri is excellent on desktop but WebView mobile can't match native scroll/keyboard. KMP+Compose has a smaller ecosystem and JVM desktop startup overhead. |
| **Language** | Dart 3.x | Flutter's language. Sound null safety, strong async/await + isolate model, pattern matching, sealed classes for exhaustive state handling. Compiles AOT to native on mobile/desktop. |
| **Matrix SDK** | matrix_dart_sdk v1.0.0 | Native Dart API eliminates FFI bridging complexity and debugging. FluffyChat validates production viability. matrix-rust-sdk Dart bindings (via UniFFI) are experimental and not production-ready. The crypto layer IS Rust regardless (flutter_vodozemac). Service abstraction allows SDK swap if Rust bindings mature. |
| **E2EE** | flutter_vodozemac | Rust vodozemac exposed through Dart FFI. Signal-grade crypto (Double Ratchet, Megolm). Same library as Element X. Not a Dart reimplementation — actual Rust compiled to native. |
| **State Management** | Riverpod 2.x | Compile-safe with code generation (`riverpod_generator`). Providers are pure functions — fully testable without widget trees. Better DI model than Provider (no BuildContext dependency for service access). Avoids Bloc's boilerplate (events + states + bloc classes per feature) while maintaining separation of concerns. |
| **Local Database** | drift 2.x (SQLite) | Type-safe Dart queries with compile-time verification. Reactive streams via `watch()`. Built-in migration system. Consistent across all platforms including web (sql.js WASM). No IndexedDB quirks. Supports FTS5 for search. |
| **Navigation** | go_router | Declarative routing with deep-link support on all platforms. URL-based navigation for desktop. ShellRoute for persistent multi-pane layouts. Redirect guards for auth state. |
| **Networking** | dio + matrix_dart_sdk HTTP | dio handles connection management, retries, interceptors, certificate pinning. matrix_dart_sdk has its own HTTP client for Matrix API calls — dio supplements for media downloads, link preview fetching, and custom endpoints. |
| **Push (iOS)** | APNs via sygnal | Matrix standard push gateway model. Notification Service Extension decrypts content locally before display. |
| **Push (Android)** | FCM + UnifiedPush | FCM for mainstream Android. UnifiedPush for de-Googled devices (LineageOS, GrapheneOS). Same app, runtime detection. |
| **Media Cache** | Custom MXC resolver + LRU cache | MXC URIs require authenticated media endpoint resolution. Custom resolver handles auth headers, encrypted media decrypt, thumbnail selection. LRU disk cache with configurable size limit. |
| **Search** | SQLite FTS5 (via drift) | Client-side full-text search for encrypted rooms. FTS5 tokenizer handles Unicode, stemming. Index encrypted at rest via SQLCipher. Server-side search supplements for unencrypted rooms. |
| **Key Storage** | flutter_secure_storage | Platform keychain abstraction: Keychain (iOS/macOS), KeyStore (Android), libsecret (Linux), Windows Credential Manager. Stores E2EE keys, recovery phrases, session tokens. |
| **CI/CD** | GitHub Actions + Fastlane | GitHub Actions for build matrix (5 platforms). Fastlane for iOS/Android signing and store submission. Native builds for desktop platforms. |
| **Crash Reporting** | Sentry (sentry_flutter) | Cross-platform crash reporting with source maps. Performance monitoring. Breadcrumbs for debugging E2EE failures. User-privacy respecting (no message content). |

---

## 2. Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1 — UI                                                   │
│  Flutter widgets, screens, platform-adaptive components         │
│                                                                 │
│  GloamApp, GloamTheme, PlatformShell, ResponsiveScaffold       │
│  MessageBubble, MessageComposer, RoomListTile, SpaceRail       │
│  AvatarWidget, BadgeWidget, EmojiPicker, QuickSwitcher         │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 2 — State Management                                    │
│  Riverpod providers, notifiers, view models                    │
│                                                                 │
│  AuthNotifier, RoomListNotifier, TimelineNotifier              │
│  SpaceNavigationNotifier, SearchNotifier, SettingsNotifier     │
│  PresenceNotifier, TypingNotifier, NotificationNotifier        │
│  SyncStatusProvider, ConnectivityProvider                      │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 3 — Service Layer                                       │
│  SDK abstraction — pure Dart interfaces                        │
│                                                                 │
│  MatrixService, SyncService, CryptoService                     │
│  MediaService, NotificationService, SearchService              │
│  RoomService, SpaceService, UserService, CallService           │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 4 — SDK Layer                                           │
│  matrix_dart_sdk, flutter_vodozemac, WebRTC                    │
│                                                                 │
│  Client (matrix_dart_sdk), Room, Timeline, Event               │
│  OlmMachine (vodozemac), KeyBackup, CrossSigning               │
│  Sliding Sync extensions, Send Queue                           │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 5 — Storage Layer                                       │
│  Local persistence, caching, indexing                          │
│                                                                 │
│  GloamDatabase (drift), EventsTable, RoomsTable, UsersTable   │
│  SearchIndex (FTS5), MediaCache (LRU disk), KeyStore           │
│  SyncStateCache, DraftStore, OfflineQueueTable                 │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 6 — Platform Layer                                      │
│  Platform channels, native integrations                        │
│                                                                 │
│  PushService (APNs/FCM/UnifiedPush), DeepLinkHandler           │
│  ShareExtension, PlatformKeychain, SystemTray                  │
│  NotificationExtension (iOS), FilePickerBridge                 │
│  PlatformMenuBar, WindowManager, BiometricAuth                 │
└─────────────────────────────────────────────────────────────────┘
```

**Dependency rule:** Each layer depends only on the layer directly below it. The UI layer never touches the SDK or Storage layers directly. The Service layer is the boundary — everything above it speaks Gloam domain types, everything below speaks SDK/platform types.

---

## 3. Project Structure

```
lib/
├── app/                           # App bootstrap, routing, theme
│   ├── app.dart                   # GloamApp widget, ProviderScope root
│   ├── router.dart                # go_router configuration
│   ├── router.g.dart              # Generated route helpers
│   └── theme/
│       ├── gloam_theme.dart       # ThemeData factory
│       ├── color_tokens.dart      # Color system (18 tokens)
│       ├── typography.dart        # Type scale (Spectral, Inter, JetBrains Mono)
│       ├── spacing.dart           # Spacing constants (base unit, padding, gaps)
│       └── component_theme.dart   # Component-level theme overrides
│
├── core/                          # Shared utilities, non-feature code
│   ├── extensions/
│   │   ├── build_context_ext.dart
│   │   ├── datetime_ext.dart
│   │   └── string_ext.dart
│   ├── utils/
│   │   ├── debouncer.dart
│   │   ├── formatters.dart
│   │   └── platform_utils.dart
│   ├── error/
│   │   ├── gloam_error.dart       # Sealed error types
│   │   ├── error_handler.dart     # Global error handling
│   │   └── error_reporter.dart    # Sentry integration
│   ├── network/
│   │   ├── connectivity.dart
│   │   └── retry_policy.dart
│   └── constants.dart
│
├── features/                      # Feature modules (clean architecture)
│   ├── auth/
│   │   ├── data/
│   │   │   ├── auth_repository_impl.dart
│   │   │   └── oidc_config.dart
│   │   ├── domain/
│   │   │   ├── auth_repository.dart       # Interface
│   │   │   ├── auth_state.dart            # Sealed: authenticated | unauthenticated | loading
│   │   │   └── user_credentials.dart
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── login_screen.dart
│   │       │   ├── register_screen.dart
│   │       │   └── verification_screen.dart
│   │       ├── widgets/
│   │       │   ├── server_field.dart
│   │       │   └── sso_buttons.dart
│   │       └── providers/
│   │           ├── auth_provider.dart
│   │           └── auth_provider.g.dart
│   │
│   ├── chat/
│   │   ├── data/
│   │   │   ├── timeline_repository_impl.dart
│   │   │   └── message_mapper.dart        # SDK Event → domain Message
│   │   ├── domain/
│   │   │   ├── message.dart               # Immutable message model
│   │   │   ├── timeline_repository.dart
│   │   │   └── send_state.dart            # sending | sent | delivered | read | failed
│   │   └── presentation/
│   │       ├── screens/
│   │       │   └── chat_screen.dart
│   │       ├── widgets/
│   │       │   ├── message_bubble.dart
│   │       │   ├── message_composer.dart
│   │       │   ├── reaction_picker.dart
│   │       │   ├── thread_panel.dart
│   │       │   ├── typing_indicator.dart
│   │       │   ├── reply_preview.dart
│   │       │   ├── link_preview.dart
│   │       │   └── delivery_indicator.dart
│   │       └── providers/
│   │           ├── timeline_provider.dart
│   │           ├── composer_provider.dart
│   │           └── typing_provider.dart
│   │
│   ├── rooms/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── room_list_screen.dart
│   │       │   └── room_details_screen.dart
│   │       ├── widgets/
│   │       │   ├── room_list_tile.dart
│   │       │   ├── room_category.dart
│   │       │   └── unread_badge.dart
│   │       └── providers/
│   │           └── room_list_provider.dart
│   │
│   ├── spaces/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │       ├── widgets/
│   │       │   ├── space_rail.dart
│   │       │   ├── space_icon.dart
│   │       │   └── space_settings.dart
│   │       └── providers/
│   │           └── space_provider.dart
│   │
│   ├── search/
│   │   ├── data/
│   │   │   ├── search_repository_impl.dart
│   │   │   └── fts_index.dart
│   │   ├── domain/
│   │   │   ├── search_result.dart
│   │   │   └── search_repository.dart
│   │   └── presentation/
│   │       ├── screens/
│   │       │   └── search_screen.dart
│   │       ├── widgets/
│   │       │   ├── quick_switcher.dart
│   │       │   └── search_filter_bar.dart
│   │       └── providers/
│   │           └── search_provider.dart
│   │
│   ├── calls/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── settings/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── settings_screen.dart
│   │       │   ├── appearance_screen.dart
│   │       │   ├── notifications_screen.dart
│   │       │   └── security_screen.dart
│   │       └── providers/
│   │           └── settings_provider.dart
│   │
│   └── onboarding/
│       ├── data/
│       ├── domain/
│       └── presentation/
│           ├── screens/
│           │   ├── welcome_screen.dart
│           │   └── server_setup_screen.dart
│           └── providers/
│
├── services/                      # SDK abstraction layer (interfaces + impls)
│   ├── matrix_service.dart        # Core client lifecycle
│   ├── matrix_service_impl.dart
│   ├── sync_service.dart          # Sliding Sync management
│   ├── sync_service_impl.dart
│   ├── crypto_service.dart        # E2EE, key management, verification
│   ├── crypto_service_impl.dart
│   ├── media_service.dart         # Upload, download, cache, thumbnails
│   ├── media_service_impl.dart
│   ├── notification_service.dart  # Push registration, local notifications
│   ├── notification_service_impl.dart
│   ├── search_service.dart        # FTS indexing and querying
│   └── search_service_impl.dart
│
├── storage/                       # Database, cache, persistence
│   ├── database/
│   │   ├── gloam_database.dart    # drift database definition
│   │   ├── gloam_database.g.dart
│   │   ├── tables/
│   │   │   ├── events_table.dart
│   │   │   ├── rooms_table.dart
│   │   │   ├── users_table.dart
│   │   │   ├── search_index_table.dart
│   │   │   ├── offline_queue_table.dart
│   │   │   └── drafts_table.dart
│   │   └── migrations/
│   │       └── migration_strategy.dart
│   ├── cache/
│   │   ├── media_cache.dart       # LRU disk cache
│   │   └── sync_state_cache.dart
│   └── secure/
│       └── key_store.dart         # flutter_secure_storage wrapper
│
├── widgets/                       # Shared, reusable UI components
│   ├── avatar.dart
│   ├── badge.dart
│   ├── emoji_picker.dart
│   ├── modal_sheet.dart
│   ├── context_menu.dart
│   ├── toggle.dart
│   ├── input_field.dart
│   ├── button.dart
│   ├── section_header.dart        # "// MONOSPACE" pattern
│   ├── profile_card.dart
│   └── adaptive_scaffold.dart
│
└── platform/                      # Platform-specific bridges
    ├── push/
    │   ├── push_provider.dart     # Abstract
    │   ├── apns_provider.dart
    │   ├── fcm_provider.dart
    │   └── unified_push_provider.dart
    ├── deep_links.dart
    ├── share_extension.dart
    ├── system_tray.dart
    └── window_manager.dart
```

### File Naming Conventions

| Convention | Pattern | Example |
|-----------|---------|---------|
| Files | `snake_case.dart` | `message_bubble.dart` |
| Classes | `PascalCase` | `MessageBubble` |
| Providers | `camelCaseProvider` | `roomListProvider` |
| Generated | `*.g.dart` (code gen), `*.freezed.dart` (freezed) | `auth_provider.g.dart` |
| Tests | `*_test.dart` in parallel `test/` tree | `test/features/chat/message_bubble_test.dart` |
| Feature modules | `data/` `domain/` `presentation/` triad | Each feature is self-contained |

---

## 4. State Management Patterns

### Riverpod Provider Taxonomy

```dart
// 1. Simple providers — computed values, no state
@riverpod
bool isEncryptedRoom(Ref ref, String roomId) {
  final room = ref.watch(roomProvider(roomId));
  return room?.encrypted ?? false;
}

// 2. FutureProviders — async initialization
@riverpod
Future<List<Room>> roomList(Ref ref) async {
  final matrixService = ref.watch(matrixServiceProvider);
  return matrixService.getRooms();
}

// 3. StreamProviders — reactive data
@riverpod
Stream<SyncStatus> syncStatus(Ref ref) {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.statusStream;
}

// 4. Notifier providers — mutable state with logic
@riverpod
class TimelineNotifier extends _$TimelineNotifier {
  @override
  AsyncValue<TimelineState> build(String roomId) {
    // Load initial timeline, set up sync listener
    _loadTimeline(roomId);
    return const AsyncValue.loading();
  }

  Future<void> sendMessage(String body) async { ... }
  Future<void> loadMore() async { ... }
  void handleLocalEcho(Event event) { ... }
}

// 5. Family providers — parameterized (per room, per user)
@riverpod
Stream<TypingUsers> typingUsers(Ref ref, String roomId) { ... }

// 6. keepAlive providers — services that outlive widget disposal
@Riverpod(keepAlive: true)
MatrixService matrixService(Ref ref) {
  return MatrixServiceImpl(ref.watch(clientProvider));
}
```

### Code Generation

All providers use `riverpod_generator` + `build_runner`:

```yaml
# pubspec.yaml
dependencies:
  flutter_riverpod: ^2.x
  riverpod_annotation: ^2.x

dev_dependencies:
  riverpod_generator: ^2.x
  build_runner: ^2.x
```

Run: `dart run build_runner watch --delete-conflicting-outputs`

### Scoping Per Feature

Each feature module has its own `providers/` directory. Providers are organized by concern:

```
features/chat/presentation/providers/
├── timeline_provider.dart       # TimelineNotifier — message list state
├── composer_provider.dart       # ComposerNotifier — draft, attachments, reply target
├── typing_provider.dart         # Typing indicator stream
└── read_receipt_provider.dart   # Read receipt tracking
```

**Cross-feature dependencies** go through the service layer, not through direct provider references between features. Example: `chat` doesn't import from `rooms` — both depend on `MatrixService`.

### State Scoping Rules

| Scope | keepAlive | Example | Lifecycle |
|-------|-----------|---------|-----------|
| App-global | `true` | `matrixServiceProvider`, `syncServiceProvider`, `authProvider` | App lifetime |
| Session-scoped | `true` | `roomListProvider`, `notificationProvider` | Login to logout |
| Screen-scoped | `false` | `timelineProvider(roomId)`, `searchProvider` | Widget mounted to disposed |
| Ephemeral | `false` | `composerProvider(roomId)`, `typingProvider(roomId)` | Widget lifetime, no persistence |

---

## 5. SDK Abstraction Layer

Every service is defined as an abstract class (interface). Implementations wrap `matrix_dart_sdk` types. This boundary enables:
- Swapping to `matrix-rust-sdk` Dart bindings if they mature
- Mocking for tests without touching SDK internals
- Domain-type isolation (app never handles raw SDK `Event` objects in UI)

### MatrixService

```dart
abstract class MatrixService {
  /// Initialize the client, restore session from storage
  Future<void> init();

  /// Login with password or SSO token
  Future<void> login(LoginCredentials credentials);

  /// Logout, clear session, wipe local data
  Future<void> logout();

  /// Current authentication state stream
  Stream<AuthState> get authState;

  /// Get the logged-in user's profile
  Future<UserProfile> getProfile();

  /// Update display name or avatar
  Future<void> updateProfile({String? displayName, Uri? avatarUri});

  /// Get a room by ID
  Room? getRoom(String roomId);

  /// Get all joined rooms (from local cache)
  List<Room> getRooms();

  /// Create a new room
  Future<String> createRoom(CreateRoomParams params);

  /// Join a room by ID or alias
  Future<void> joinRoom(String roomIdOrAlias);

  /// Leave a room
  Future<void> leaveRoom(String roomId);

  /// Dispose and clean up
  Future<void> dispose();
}
```

### SyncService

```dart
abstract class SyncService {
  /// Start Sliding Sync with initial room list window
  Future<void> startSync({int windowSize = 20});

  /// Stop syncing
  Future<void> stopSync();

  /// Sync status stream (syncing, error, stopped)
  Stream<SyncStatus> get statusStream;

  /// Request additional rooms in the sliding window
  Future<void> requestRange(int start, int end);

  /// Force a one-time full sync (for background refresh)
  Future<void> forceSync();

  /// Whether Sliding Sync is supported by the homeserver
  Future<bool> get isSlidingSyncSupported;

  /// Fallback to sync v2 if Sliding Sync unavailable
  Future<void> startLegacySync();
}
```

### CryptoService

```dart
abstract class CryptoService {
  /// Initialize cross-signing keys (on first login)
  Future<void> bootstrapCrossSigning();

  /// Set up or restore key backup
  Future<void> setupKeyBackup(String? recoveryPhrase);

  /// Verify another device via QR code
  Future<void> verifyDeviceQR(String otherDeviceId);

  /// Verify another device via emoji comparison
  Future<void> verifyDeviceEmoji(String otherDeviceId);

  /// Request missing message keys from other devices
  Future<void> requestKeys(String roomId, String sessionId);

  /// Export keys (for manual backup)
  Future<String> exportKeys(String passphrase);

  /// Import keys from backup
  Future<int> importKeys(String data, String passphrase);

  /// Stream of verification requests from other devices
  Stream<VerificationRequest> get verificationRequests;

  /// Current cross-signing status
  Future<CrossSigningStatus> get crossSigningStatus;

  /// Check if a user's devices are verified
  Future<DeviceTrustLevel> getUserTrust(String userId);
}
```

### MediaService

```dart
abstract class MediaService {
  /// Upload a file, returns MXC URI
  Future<Uri> upload(File file, {String? fileName, String? mimeType});

  /// Download media by MXC URI (uses cache, handles auth + decryption)
  Future<File> download(Uri mxcUri, {EncryptedFile? encryptedFile});

  /// Get thumbnail (generates if needed, respects size constraints)
  Future<File> getThumbnail(Uri mxcUri, {int width = 256, int height = 256});

  /// Generate blurhash for an image
  Future<String> generateBlurhash(File imageFile);

  /// Resolve an MXC URI to an authenticated HTTPS URL
  Uri resolveUrl(Uri mxcUri, {int? width, int? height});

  /// Clear media cache
  Future<void> clearCache();

  /// Current cache size in bytes
  Future<int> get cacheSize;

  /// Set max cache size
  Future<void> setMaxCacheSize(int bytes);
}
```

### NotificationService

```dart
abstract class NotificationService {
  /// Register for push notifications (APNs/FCM/UnifiedPush)
  Future<void> register();

  /// Unregister from push
  Future<void> unregister();

  /// Handle incoming push payload (decrypt + display)
  Future<void> handlePush(Map<String, dynamic> payload);

  /// Show a local notification
  Future<void> showLocal(LocalNotification notification);

  /// Get per-room notification setting
  Future<NotificationLevel> getRoomLevel(String roomId);

  /// Set per-room notification setting
  Future<void> setRoomLevel(String roomId, NotificationLevel level);

  /// Global DND state
  Stream<bool> get dndStream;

  /// Set DND with optional schedule
  Future<void> setDnd(bool enabled, {DndSchedule? schedule});
}
```

### SearchService

```dart
abstract class SearchService {
  /// Index a decrypted message (called during sync)
  Future<void> indexEvent(IndexableEvent event);

  /// Full-text search with filters
  Future<SearchResults> search(
    String query, {
    String? roomId,
    String? senderId,
    DateTime? after,
    DateTime? before,
    Set<ContentFilter> filters, // hasFile, hasLink, hasImage
    int limit = 50,
    int offset = 0,
  });

  /// Quick switcher search (rooms + people)
  Future<List<SwitcherResult>> quickSearch(String query);

  /// Rebuild the search index (after key import, etc.)
  Future<void> rebuildIndex();

  /// Index statistics
  Future<IndexStats> get stats;
}
```

### Rationale

The service layer exists for three reasons:

1. **SDK replaceability.** If `matrix-rust-sdk` Dart bindings mature, only the `*_impl.dart` files change. The entire app above the service layer is untouched.
2. **Testability.** Every provider and widget test uses mock services, never the real SDK. Tests run in milliseconds without network access.
3. **Domain isolation.** The app speaks `Message`, `Room`, `UserProfile`. The SDK speaks `Event`, `MatrixRoom`, `Profile`. The mapping happens in `data/` layers and service impls, not in widgets.

---

## 6. Data Flow Patterns

### Optimistic UI Flow (Message Send)

```
User taps Send
    │
    ▼
ComposerNotifier.sendMessage(body)
    │
    ├──▶ Create local Message with SendState.sending
    │    id: "~local-${uuid}"
    │    timestamp: DateTime.now()
    │
    ├──▶ Insert into TimelineNotifier.state (top of list)
    │    UI renders message immediately with sending indicator
    │
    ├──▶ Persist to OfflineQueueTable (for crash recovery)
    │
    ▼
MatrixService.sendMessage(roomId, body)  [async, non-blocking]
    │
    ├── SUCCESS ─▶ SDK returns server event_id
    │   │
    │   ├──▶ TimelineNotifier: replace local message
    │   │    id: "~local-..." → "$server-event-id"
    │   │    SendState.sending → SendState.sent
    │   │
    │   ├──▶ Remove from OfflineQueueTable
    │   │
    │   └──▶ Later: read receipt arrives
    │        SendState.sent → SendState.delivered → SendState.read
    │
    └── FAILURE ─▶ Network error or server rejection
        │
        ├──▶ TimelineNotifier: update message
        │    SendState.sending → SendState.failed
        │    Show retry button on message bubble
        │
        └──▶ Message stays in OfflineQueueTable
             Retry on next connectivity change
```

### Sync Data Flow

```
SyncService.startSync()
    │
    ▼
Sliding Sync connection established (WebSocket or long-poll)
    │
    ▼
Server pushes sync response (room list window)
    │
    ├──▶ SyncService parses response
    │
    ├──▶ For each room update:
    │    │
    │    ├──▶ New events → decrypt if needed (CryptoService, background isolate)
    │    │
    │    ├──▶ Decrypted events → persist to EventsTable (drift)
    │    │
    │    ├──▶ Decrypted events → index in SearchService.indexEvent()
    │    │
    │    ├──▶ Room metadata → update RoomsTable (name, avatar, unread count)
    │    │
    │    └──▶ Emit to reactive streams:
    │         • RoomListNotifier rebuilds room list
    │         • TimelineNotifier (if room is open) appends new messages
    │         • PresenceNotifier updates online/offline states
    │         • NotificationNotifier shows local notification if app backgrounded
    │
    ├──▶ For typing events:
    │    └──▶ TypingProvider(roomId) emits updated typing user list
    │
    └──▶ For receipt events:
         └──▶ TimelineNotifier updates SendState for affected messages
```

### Offline Queue Pattern

```
App loses network connectivity
    │
    ├──▶ ConnectivityProvider.state → ConnectionState.offline
    │
    ├──▶ UI shows subtle "offline" indicator (top bar tint change)
    │
    ▼
User sends message while offline
    │
    ├──▶ Message rendered with SendState.queued (not .sending)
    │
    ├──▶ Persisted to OfflineQueueTable:
    │    { id, roomId, type, body, attachments, replyTo, createdAt, retryCount }
    │
    ▼
Network reconnects
    │
    ├──▶ ConnectivityProvider.state → ConnectionState.online
    │
    ├──▶ SyncService resumes (catches up from last sync token)
    │
    ├──▶ OfflineQueueProcessor drains the queue:
    │    │
    │    │  For each queued message (FIFO order per room):
    │    │
    │    ├──▶ Update SendState.queued → SendState.sending
    │    │
    │    ├──▶ MatrixService.sendMessage(...)
    │    │    │
    │    │    ├── SUCCESS → Remove from queue, update to SendState.sent
    │    │    │
    │    │    └── FAILURE → Increment retryCount
    │    │         │
    │    │         ├── retryCount < 5 → Exponential backoff, retry
    │    │         │
    │    │         └── retryCount >= 5 → SendState.failed, notify user
    │    │
    │    └──▶ Process next message (serial per room, parallel across rooms)
    │
    └──▶ UI updates reactively as each message resolves
```

---

## 7. Storage Architecture

### drift Schema

```dart
// Core tables
class EventsTable extends Table {
  TextColumn get eventId => text()();           // "$event_id" or "~local-uuid"
  TextColumn get roomId => text()();
  TextColumn get senderId => text()();
  TextColumn get type => text()();              // "m.room.message", "m.reaction", etc.
  TextColumn get content => text()();           // JSON blob
  IntColumn get originServerTs => integer()();  // Milliseconds since epoch
  TextColumn get stateKey => text().nullable()();
  BoolColumn get isEncrypted => boolean().withDefault(const Constant(false))();
  TextColumn get relatesTo => text().nullable()(); // reply/thread/edit target
  TextColumn get sendState => text().nullable()(); // sending|sent|delivered|read|failed|queued

  @override
  Set<Column> get primaryKey => {eventId};

  @override
  List<Set<Column>> get uniqueKeys => [];

  @override
  List<String> get customConstraints => [];
}

class RoomsTable extends Table {
  TextColumn get roomId => text()();
  TextColumn get name => text().nullable()();
  TextColumn get topic => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  BoolColumn get isEncrypted => boolean().withDefault(const Constant(false))();
  BoolColumn get isDirect => boolean().withDefault(const Constant(false))();
  TextColumn get lastEventId => text().nullable()();
  IntColumn get lastEventTs => integer().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get mentionCount => integer().withDefault(const Constant(0))();
  TextColumn get notificationLevel => text().withDefault(const Constant('default'))();
  TextColumn get spaceId => text().nullable()();  // Parent space
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {roomId};
}

class UsersTable extends Table {
  TextColumn get userId => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get presence => text().withDefault(const Constant('offline'))();
  IntColumn get lastActiveTs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {userId};
}

class OfflineQueueTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get roomId => text()();
  TextColumn get type => text()();             // "message", "reaction", "redaction"
  TextColumn get payload => text()();          // JSON
  IntColumn get createdAt => integer()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
}

class DraftsTable extends Table {
  TextColumn get roomId => text()();
  TextColumn get body => text()();
  TextColumn get replyToEventId => text().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {roomId};
}

// FTS5 virtual table for search (defined via drift custom statement)
// CREATE VIRTUAL TABLE search_index USING fts5(
//   event_id UNINDEXED,
//   room_id UNINDEXED,
//   sender_id UNINDEXED,
//   timestamp UNINDEXED,
//   content,
//   tokenize='unicode61'
// );
```

### Encrypted Key Storage

Platform keychain stores secrets that must never touch SQLite:

| Key | Storage | Platform API |
|-----|---------|-------------|
| Session access token | flutter_secure_storage | Keychain (iOS/macOS), KeyStore (Android), libsecret (Linux), Credential Manager (Windows) |
| Recovery passphrase | flutter_secure_storage | Same |
| Cross-signing private keys | flutter_secure_storage | Same |
| Megolm session keys | matrix_dart_sdk internal DB | Encrypted at rest by SDK |
| Olm account pickle | matrix_dart_sdk internal DB | Encrypted at rest by SDK |

flutter_secure_storage uses:
- **iOS/macOS:** Keychain Services with `kSecAttrAccessibleAfterFirstUnlock`
- **Android:** EncryptedSharedPreferences backed by Android KeyStore
- **Linux:** libsecret (GNOME Keyring / KWallet)
- **Windows:** Windows Credential Manager (DPAPI)

### Media Cache (LRU)

```
media_cache/
├── thumbnails/          # 256x256 thumbnails, ~50KB each
│   └── {hash}.jpg
├── images/              # Full-resolution images
│   └── {hash}.{ext}
├── files/               # Documents, audio, video
│   └── {hash}.{ext}
└── blurhash/            # Precomputed blurhash strings (tiny)
    └── {mxc_hash}.txt
```

- **Default max size:** 500MB (configurable in settings)
- **Eviction:** LRU based on last access timestamp
- **Encrypted media:** Decrypted on download, stored decrypted in cache (cache is app-private storage)
- **Cache key:** SHA-256 of MXC URI (avoids filesystem-unsafe characters)
- **Thumbnails:** Generated locally on upload, fetched from server on download (server-side thumbnail API)

### FTS5 Search Index

```sql
-- Index populated during sync (after decryption)
INSERT INTO search_index(event_id, room_id, sender_id, timestamp, content)
VALUES ($eventId, $roomId, $senderId, $timestamp, $plaintext);

-- Query with ranking
SELECT event_id, room_id, sender_id, timestamp,
       snippet(search_index, 4, '<mark>', '</mark>', '...', 32) as snippet,
       rank
FROM search_index
WHERE search_index MATCH $query
  AND room_id = $roomFilter       -- optional
  AND sender_id = $senderFilter   -- optional
  AND timestamp > $afterFilter    -- optional
  AND timestamp < $beforeFilter   -- optional
ORDER BY rank
LIMIT $limit OFFSET $offset;
```

- **Tokenizer:** `unicode61` (handles accented characters, CJK)
- **Encryption at rest:** SQLCipher wraps the entire database file (AES-256-CBC)
- **Index rebuild:** Triggered after key import (new keys decrypt previously unreadable messages)

### Migration Strategy

```dart
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) async {
    await m.createAll(); // Create all tables from current schema
  },
  onUpgrade: (m, from, to) async {
    // Stepwise migration — each version bump has an explicit handler
    if (from < 2) {
      await m.addColumn(roomsTable, roomsTable.spaceId);
    }
    if (from < 3) {
      await m.createTable(offlineQueueTable);
    }
    // ... each migration is additive and tested
  },
  beforeOpen: (details) async {
    // Enable WAL mode for better concurrent read/write
    await customStatement('PRAGMA journal_mode=WAL');
    await customStatement('PRAGMA foreign_keys=ON');
  },
);
```

- **Schema version** tracked in drift's built-in versioning
- **Destructive migrations** (table drops, column type changes) are avoided; use new columns + deprecate old ones
- **Migration tests:** Each migration step has a dedicated test that creates a DB at version N and upgrades to N+1
- **Backup before major migration:** Export DB to temp file before running multi-step upgrades

---

## 8. Navigation Architecture

### go_router Configuration

```dart
final router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final isLoggedIn = ref.read(authProvider).isAuthenticated;
    final isOnboarding = state.matchedLocation.startsWith('/onboarding');

    if (!isLoggedIn && !isOnboarding) return '/onboarding';
    if (isLoggedIn && isOnboarding) return '/';
    return null;
  },
  routes: [
    // Onboarding (no shell)
    GoRoute(path: '/onboarding', builder: (_, __) => WelcomeScreen()),
    GoRoute(path: '/login', builder: (_, __) => LoginScreen()),

    // Main app shell — persistent space rail + room list
    ShellRoute(
      builder: (_, __, child) => PlatformShell(child: child),
      routes: [
        // Room list (default)
        GoRoute(
          path: '/',
          builder: (_, __) => RoomListScreen(),
          routes: [
            // Chat timeline
            GoRoute(
              path: 'room/:roomId',
              builder: (_, state) => ChatScreen(
                roomId: state.pathParameters['roomId']!,
              ),
              routes: [
                // Thread panel
                GoRoute(
                  path: 'thread/:eventId',
                  builder: (_, state) => ThreadPanel(
                    roomId: state.pathParameters['roomId']!,
                    rootEventId: state.pathParameters['eventId']!,
                  ),
                ),
                // Room details
                GoRoute(
                  path: 'details',
                  builder: (_, state) => RoomDetailsScreen(
                    roomId: state.pathParameters['roomId']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        // Settings
        GoRoute(path: '/settings', builder: (_, __) => SettingsScreen(),
          routes: [
            GoRoute(path: 'appearance', builder: (_, __) => AppearanceScreen()),
            GoRoute(path: 'notifications', builder: (_, __) => NotificationsScreen()),
            GoRoute(path: 'security', builder: (_, __) => SecurityScreen()),
          ],
        ),
        // Search
        GoRoute(path: '/search', builder: (_, __) => SearchScreen()),
      ],
    ),
  ],
);
```

### Deep Links

| Platform | Scheme | Example |
|----------|--------|---------|
| All | `gloam://` | `gloam://room/!abc123:matrix.org` |
| All | `https://gloam.chat` | `https://gloam.chat/room/!abc123:matrix.org` |
| All | `matrix:` | `matrix:r/room:server.com` (Matrix URI scheme, MSC2312) |

Deep link handling:
1. Parse incoming URI
2. Map to go_router path: `gloam://room/!id:server` → `/room/!id:server`
3. If not logged in, store target and redirect after auth
4. `matrix:` URIs are resolved via the SDK (room alias lookup, etc.)

### Platform-Adaptive Shell

```dart
class PlatformShell extends ConsumerWidget {
  // Desktop (>1024px): Three-column layout
  //   [SpaceRail 56px] [RoomList 280px] [Content flex]
  //
  // Tablet (600-1024px): Two-column layout
  //   [RoomList 280px] [Content flex]
  //   SpaceRail collapses into a top bar or hamburger
  //
  // Phone (<600px): Single column with navigation stack
  //   RoomList → push ChatScreen
  //   SpaceRail → bottom tab or drawer
  //   Back gesture to return

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth > 1024) return DesktopShell(...);
      if (constraints.maxWidth > 600) return TabletShell(...);
      return PhoneShell(...);
    });
  }
}
```

### URL Scheme (Desktop)

On desktop, the URL bar (if exposed) or window title reflects the current location:

```
/                           → "Gloam"
/room/!abc:matrix.org       → "Gloam — #general"
/room/!abc:matrix.org/thread/... → "Gloam — #general — Thread"
/settings                   → "Gloam — Settings"
```

---

## 9. E2EE Architecture

### Cross-Signing Key Hierarchy

```
Master Key (MSK)
├── Self-Signing Key (SSK) — signs this user's device keys
│   ├── Device Key A (this phone)
│   ├── Device Key B (this laptop)
│   └── Device Key C (this desktop)
└── User-Signing Key (USK) — signs other users' master keys
    ├── Verified: Alice's MSK
    ├── Verified: Bob's MSK
    └── Verified: Carol's MSK
```

**Bootstrap flow (first login):**
1. Generate MSK, SSK, USK
2. Upload public keys to homeserver
3. Sign this device's key with SSK
4. Upload signatures
5. Encrypt private keys with recovery passphrase → store in SSSS (Secret Storage)
6. Prompt user to save recovery phrase (12-word mnemonic) — one time only
7. Store recovery phrase in platform keychain as fallback

All of this happens silently during account creation. The user sees a brief "Securing your account..." state, then a single prompt to save their recovery phrase.

### Key Backup

```
New message arrives (encrypted, Megolm)
    │
    ├──▶ Attempt decrypt with existing session key
    │    │
    │    ├── SUCCESS → render message
    │    │
    │    └── MISSING KEY → start key recovery cascade:
    │         │
    │         ├── 1. Check local session store
    │         │
    │         ├── 2. Request key from other devices (m.room_key_request)
    │         │    Wait up to 10 seconds for response
    │         │
    │         ├── 3. Attempt restore from server-side key backup
    │         │    Decrypt with recovery key from platform keychain
    │         │
    │         ├── 4. Prompt user for recovery phrase (last resort)
    │         │
    │         └── 5. All failed → show graceful placeholder:
    │              "Message from [sender] — content unavailable"
    │              (NOT "Unable to Decrypt" with a scary error icon)
```

**Key backup runs continuously:**
- Every new Megolm session key is backed up to the server within 30 seconds
- Backup is encrypted with the recovery key (AES-256)
- On new device login, all keys are restored from backup automatically
- Backup version is tracked; client handles version mismatch gracefully

### Session Verification

```
New unverified device detected
    │
    ├──▶ If it's the current user's new device:
    │    Show non-blocking banner: "Verify your new device for full access"
    │    │
    │    ├── User taps banner → QR code scan (MSC4108 ECIES)
    │    │   Phone shows QR → Desktop scans (or vice versa)
    │    │   Verification completes in ~5 seconds
    │    │
    │    └── User ignores banner → banner persists subtly
    │         Messages still send/receive (degraded trust indicator only)
    │
    └──▶ If it's another user's new device:
         Do NOT prompt. Silently verify if their MSK signature is valid.
         Only show a trust change if their MSK has rotated (rare, suspicious).
```

### "Unable to Decrypt" Mitigation

This is the single most important UX goal of the crypto system. Strategy layers:

| Layer | Approach | When |
|-------|----------|------|
| **Prevention** | Pre-fetch Megolm sessions for rooms on the room list (background, during sync) | Always |
| **Prevention** | Share keys with all verified devices immediately when a new session is created | Always |
| **Recovery** | Automatic key request to other online devices | On missing key |
| **Recovery** | Automatic key backup restore (no user interaction) | On missing key, no device response |
| **Recovery** | Re-request keys periodically (every 60s) for up to 5 minutes | On persistent failure |
| **Graceful degradation** | Show sender name + timestamp with "content unavailable" placeholder | All recovery failed |
| **Background repair** | When keys arrive later (from backup restore, device comes online), retroactively decrypt and update timeline | Ongoing |

### Background Crypto Isolate

All E2EE operations run on a separate Dart isolate to prevent UI jank:

```dart
// Main isolate (UI)
final decryptedEvent = await _cryptoIsolate.decrypt(encryptedEvent);

// Crypto isolate (background)
class CryptoIsolate {
  late final OlmMachine _olmMachine;

  Future<DecryptedEvent> decrypt(EncryptedEvent event) async {
    // Heavy crypto operations happen here, off the UI thread
    return _olmMachine.decryptRoomEvent(event);
  }

  Future<void> processToDeviceEvents(List<ToDeviceEvent> events) async {
    // Key sharing, verification, etc.
    for (final event in events) {
      await _olmMachine.receiveToDeviceEvent(event);
    }
  }
}
```

This isolate handles: decryption, key sharing, verification, backup operations, cross-signing updates. The UI thread never blocks on crypto.

---

## 10. Error Handling

### Error Types (Sealed)

```dart
sealed class GloamError {
  String get userMessage;
  String get technicalDetail;
  bool get isRetryable;
}

class NetworkError extends GloamError {
  final int? statusCode;
  final String? serverMessage;
  // "Connection lost. Retrying..."
}

class AuthError extends GloamError {
  final AuthErrorKind kind; // sessionExpired, invalidCredentials, rateLimited
  // "Your session has expired. Please sign in again."
}

class CryptoError extends GloamError {
  final CryptoErrorKind kind; // keyMissing, verificationFailed, backupCorrupted
  // "Message content unavailable" (NEVER expose crypto details to user)
}

class SyncError extends GloamError {
  final SyncErrorKind kind; // connectionLost, serverError, invalidToken
  // "Reconnecting..." (shown as subtle status indicator)
}

class StorageError extends GloamError {
  final StorageErrorKind kind; // diskFull, migrationFailed, corrupted
  // "Storage error. Please restart Gloam."
}

class MediaError extends GloamError {
  final MediaErrorKind kind; // uploadFailed, downloadFailed, tooLarge, unsupportedFormat
  // "File couldn't be uploaded. Tap to retry."
}

class RoomError extends GloamError {
  final RoomErrorKind kind; // notFound, forbidden, alreadyJoined
  // "You don't have permission to join this room."
}
```

### Error Propagation

```
SDK throws exception
    │
    ▼
Service layer catches → maps to GloamError
    │
    ▼
Provider/Notifier receives GloamError
    │
    ├──▶ isRetryable? → set AsyncValue.error with retry callback
    │
    ├──▶ AuthError.sessionExpired? → trigger re-auth flow
    │
    └──▶ All others → emit error state for UI consumption
         │
         ▼
UI layer reads error state
    │
    ├──▶ Inline errors (message send fail) → retry button on the widget
    ├──▶ Screen-level errors (room load fail) → error state with retry
    ├──▶ Global errors (sync failure) → subtle top banner
    └──▶ Fatal errors (storage corruption) → full-screen error + report
```

### User-Facing Presentation Rules

| Error Type | Presentation | User Action |
|-----------|-------------|-------------|
| Network (transient) | Subtle top bar indicator: "Reconnecting..." | None — auto-retries |
| Network (sustained) | Top bar indicator + "Offline — messages will send when you reconnect" | None |
| Message send failure | Red indicator on message bubble + "Tap to retry" | Tap to retry |
| Media upload failure | Error icon on attachment + "Tap to retry" | Tap to retry or cancel |
| Crypto (key missing) | Grey placeholder: "Message from [sender] — content unavailable" | None (auto-recovers when keys arrive) |
| Auth expired | Modal: "Your session has expired" + login button | Re-authenticate |
| Room permission denied | Inline: "You don't have permission to do this" | None |
| Rate limited | Toast: "Slow down — try again in X seconds" | Wait |

### Crash Reporting (Sentry)

```dart
// Initialized in main.dart
await SentryFlutter.init((options) {
  options.dsn = kSentryDsn;
  options.environment = kIsRelease ? 'production' : 'debug';
  options.tracesSampleRate = 0.1; // 10% of transactions for performance
  options.beforeSend = (event, hint) {
    // NEVER send message content, room names, or user IDs
    return _scrubSensitiveData(event);
  };
});

// Breadcrumbs for debugging (no PII)
Sentry.addBreadcrumb(Breadcrumb(
  message: 'Room opened',
  category: 'navigation',
  data: {'encrypted': true, 'memberCount': 42},
));
```

**Privacy rules:**
- No message content, room names, user IDs, or Matrix event IDs in reports
- Room IDs are hashed before sending
- Breadcrumbs track actions (e.g., "opened room," "sent message") without content
- User opt-in for crash reporting (enabled by default, toggle in settings)

---

## 11. Testing Strategy

### Test Pyramid

```
                    ╱╲
                   ╱  ╲
                  ╱ E2E ╲         5 tests — Full app on real homeserver
                 ╱────────╲
                ╱Integration╲     30 tests — Multi-widget flows
               ╱──────────────╲
              ╱  Widget Tests   ╲  150 tests — Individual widget rendering
             ╱────────────────────╲
            ╱     Unit Tests       ╲  500+ tests — Services, providers, utils
           ╱────────────────────────╲
```

### Unit Tests

- **Services:** Mock `matrix_dart_sdk` Client. Test every service method for success, failure, and edge cases.
- **Providers/Notifiers:** Test state transitions. Use `ProviderContainer` for isolated testing.
- **Mappers:** Test SDK type → domain type mapping (null handling, malformed data).
- **Utilities:** Date formatting, markdown parsing, URL detection, etc.

```dart
// Example: Testing optimistic send
test('sendMessage adds local echo immediately', () async {
  final container = ProviderContainer(overrides: [
    matrixServiceProvider.overrideWithValue(MockMatrixService()),
  ]);
  final notifier = container.read(timelineProvider('!room:test').notifier);

  await notifier.sendMessage('Hello');

  final state = container.read(timelineProvider('!room:test'));
  expect(state.value!.messages.first.body, 'Hello');
  expect(state.value!.messages.first.sendState, SendState.sending);
});
```

### Widget Tests

- **Every shared widget** in `widgets/` has a widget test
- **Message bubble** variants: text, image, file, reply, thread, edited, deleted, failed
- **Room list tile** states: unread, mention, muted, encrypted, typing
- **Composer** states: empty, draft, replying, editing, uploading attachment

### Integration Tests

- **Auth flow:** Login → room list → open room → send message → verify in timeline
- **Offline flow:** Go offline → queue message → reconnect → message sends
- **Search flow:** Send messages → search → verify results with filters
- **Navigation flow:** Space switching → room list updates → deep link resolution

### Golden Tests

Golden (screenshot) tests for visual regression:

- Message bubble (all variants, dark + light mode)
- Room list (empty, populated, loading)
- Space rail (selected, unread indicators)
- Settings screens

### Mocking matrix_dart_sdk

```dart
// Mock the SDK Client
class MockClient extends Mock implements Client {}
class MockRoom extends Mock implements MatrixRoom {}
class MockTimeline extends Mock implements Timeline {}

// Mock service layer (for provider/widget tests)
class MockMatrixService extends Mock implements MatrixService {}
class MockCryptoService extends Mock implements CryptoService {}

// Fake sync responses (for integration tests)
final fakeSyncResponse = SyncResponse(
  rooms: RoomsResponse(
    join: {
      '!test:matrix.org': JoinedRoom(
        timeline: TimelineResponse(events: [
          MatrixEvent(type: 'm.room.message', content: {'body': 'Hello'}),
        ]),
      ),
    },
  ),
);
```

### CI Test Matrix

| Platform | Runner | Tests Run | Trigger |
|----------|--------|-----------|---------|
| Linux | `ubuntu-latest` | Unit + Widget + Golden + Integration | Every PR, every push to main |
| macOS | `macos-14` (ARM) | Unit + Widget + Integration + macOS desktop build | Every PR |
| Windows | `windows-latest` | Unit + Widget + Windows desktop build | Every PR |
| iOS | `macos-14` + Simulator | Integration tests on iOS Simulator | Nightly + release |
| Android | `ubuntu-latest` + Emulator | Integration tests on Android Emulator | Nightly + release |

**Coverage target:** 80% line coverage for `services/`, `features/*/domain/`, `features/*/data/`. No coverage requirement for generated code or UI-only widgets.

---

## 12. Performance Architecture

### Timeline Virtualization

```dart
// SliverList with estimated item extents for smooth scrolling
CustomScrollView(
  reverse: true, // Messages scroll up from bottom
  slivers: [
    SliverList.builder(
      itemCount: messages.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) return LoadMoreTrigger();
        return MessageBubble(message: messages[index]);
      },
    ),
  ],
)

// Key optimizations:
// 1. RepaintBoundary around each MessageBubble
// 2. const constructors for immutable message parts
// 3. AutomaticKeepAliveClientMixin for messages with loaded media
// 4. itemExtent estimation via message type (text ~60px, image ~280px)
// 5. Buffer: render ±2 screens of messages beyond the viewport
```

**Memory management for long timelines:**
- Keep only the visible window + buffer in memory (Riverpod `autoDispose`)
- Messages older than the buffer are dropped from the notifier's state
- Scrolling up triggers `loadMore()` which fetches from local DB (not server)
- DB is the single source of truth; in-memory state is a view window

### Image Pipeline

```
Image message in timeline
    │
    ├──▶ 1. Render blurhash placeholder immediately (from event content)
    │       (4x3 pixel blurhash decoded to gradient — sub-1ms)
    │
    ├──▶ 2. Check media cache for thumbnail
    │    │
    │    ├── HIT → render thumbnail, done (until user taps to expand)
    │    │
    │    └── MISS → fetch thumbnail from server
    │         │
    │         ├──▶ Resolve MXC URI → authenticated HTTPS URL
    │         │    (server-side thumbnail: ?width=256&height=256&method=scale)
    │         │
    │         ├──▶ If encrypted: download → decrypt (crypto isolate) → cache
    │         │    If cleartext: download → cache
    │         │
    │         └──▶ Render thumbnail (crossfade from blurhash, 200ms)
    │
    └──▶ 3. User taps image → full-screen viewer
         │
         ├──▶ Show thumbnail scaled up immediately
         │
         ├──▶ Fetch full resolution in background
         │
         └──▶ Crossfade to full-res when loaded
```

### Sliding Sync

```
App launch
    │
    ├──▶ Load cached room list from RoomsTable (instant, <50ms)
    │    UI renders cached state immediately
    │
    ├──▶ SyncService.startSync(windowSize: 20)
    │    Request first 20 rooms sorted by recency
    │
    ├──▶ Server responds with room list window (~200ms)
    │    Update room list with fresh data (unread counts, last message)
    │
    ├──▶ User scrolls down → SyncService.requestRange(20, 40)
    │    Server sends next 20 rooms
    │
    ├──▶ Background: incrementally expand window to cover all rooms
    │    (for notification matching and search index)
    │
    └──▶ Ongoing: server pushes incremental updates via persistent connection
         Room reordering, new messages, typing indicators — all via Sliding Sync
```

**Fallback behavior:** If the homeserver lacks Sliding Sync support, fall back to sync v2:
- Show a settings banner: "Your homeserver doesn't support Sliding Sync. Performance may be degraded."
- Cache sync responses aggressively for fast restart
- Limit initial sync to rooms with recent activity (client-side filtering)

### Background Isolates

| Isolate | Responsibility | Communication |
|---------|---------------|---------------|
| **Main** | UI rendering, state management, navigation | — |
| **Crypto** | Megolm decrypt/encrypt, key sharing, verification, backup | `SendPort`/`ReceivePort` message passing |
| **Search Indexer** | FTS5 inserts after message decryption | Batch writes via `SendPort` |
| **Media Processor** | Image resize, blurhash generation, thumbnail extraction | Futures via `Isolate.run()` |

The crypto isolate is long-lived (app lifetime). The search indexer and media processor use short-lived isolates spawned per batch/task.

### Memory Management

| Strategy | Target | Implementation |
|----------|--------|---------------|
| Timeline windowing | < 200 messages in memory per open room | autoDispose provider drops state when leaving room. DB is source of truth. |
| Media cache LRU | 500MB default disk, ~50MB decoded images in memory | `ImageCache` size limited to 100 entries. Evict on memory pressure callback. |
| Room list virtualization | Only visible rooms have full state in memory | Sliding Sync windows. Room metadata cached in DB, loaded on demand. |
| Aggressive widget recycling | Minimize widget allocations during scroll | `const` constructors, `RepaintBoundary`, avoid `setState` in scroll callbacks. |
| Memory pressure response | Release non-visible resources on low memory | Listen to `WidgetsBindingObserver.didHaveMemoryPressure`. Drop image caches, trim timeline buffers. |

---

## 13. Risk Register

### Risk 1: E2EE "Unable to Decrypt" Elimination

| Attribute | Detail |
|-----------|--------|
| **Severity** | Critical |
| **Probability** | High — this is the hardest UX problem in Matrix |
| **Impact** | Users abandon the app if messages can't be read. Trust is destroyed on first occurrence. |
| **Mitigation** | 5-layer key recovery cascade (local → device request → backup restore → user prompt → graceful degradation). Pre-fetch keys for all visible rooms during sync. Background key backup within 30 seconds of new session creation. Budget 2x estimated time for crypto work. |
| **Contingency** | If zero-UTD is unachievable, implement "request keys" button on affected messages + automatic background retry. Track UTD rate as a metric — target <0.1% of encrypted messages. |

### Risk 2: Single-Developer Velocity

| Attribute | Detail |
|-----------|--------|
| **Severity** | High |
| **Probability** | High — 32-week timeline with one person is ambitious |
| **Impact** | Scope creep, burnout, missed milestones. Quality suffers under time pressure. |
| **Mitigation** | Phase ruthlessly. Each phase has a "done" milestone that delivers user value independently. Cut scope from later phases (P1/P2 features) before slipping earlier ones. Ship Phases 0-2 as a focused text chat client before expanding. |
| **Contingency** | If Phase 0-1 takes >14 weeks (4 weeks over), reassess Phase 5 (voice/video) scope. Voice channels can launch as P1 post-beta. |

### Risk 3: matrix_dart_sdk Feature Gaps

| Attribute | Detail |
|-----------|--------|
| **Severity** | Medium |
| **Probability** | Medium — SDK is v1.0 but smaller team/community than Rust SDK |
| **Impact** | Missing SDK features block planned app features. Workarounds are fragile. |
| **Mitigation** | Service layer abstraction allows SDK swap. Monitor matrix-rust-sdk Dart bindings maturity (currently experimental). Contribute upstream fixes to matrix_dart_sdk. Maintain a running gap list with workarounds. |
| **Contingency** | For critical gaps, implement at the service layer (direct Matrix CS API calls via dio). If gaps accumulate, evaluate Rust SDK Dart bindings as a Phase 5+ migration. |

### Risk 4: Flutter Desktop UX Ceiling

| Attribute | Detail |
|-----------|--------|
| **Severity** | Medium |
| **Probability** | Medium — Flutter desktop is stable but not as mature as mobile |
| **Impact** | Desktop app feels like a stretched mobile app. Power users (the primary audience) reject it. |
| **Mitigation** | Invest in platform-adaptive layer from Phase 0. Use `PlatformMenuBar` (macOS), native scroll physics, keyboard shortcut system, right-click context menus, window management. Test on real desktop hardware weekly. Density modes from day one. |
| **Contingency** | If desktop UX hits a ceiling, evaluate Tauri for desktop targets with shared Dart/Rust service layer. This is a Phase 5+ decision — don't split the codebase prematurely. |

### Risk 5: Push Notification Reliability

| Attribute | Detail |
|-----------|--------|
| **Severity** | Medium |
| **Probability** | Medium — well-understood problem but many failure modes |
| **Impact** | Users miss messages, lose trust, abandon the app. Notification reliability is a baseline expectation. |
| **Mitigation** | Implement sygnal integration in Phase 2. Test on real devices across iOS versions and Android OEMs (Samsung, Xiaomi battery optimization). Encrypted notification content decrypted in notification extension. UnifiedPush for de-Googled Android. |
| **Contingency** | If push reliability is <95%, implement local foreground polling as supplement. Track push delivery rates with server-side logging. |

### Risk 6: vodozemac Security Vulnerabilities

| Attribute | Detail |
|-----------|--------|
| **Severity** | High (if exploited) |
| **Probability** | Low-Medium — CVE-2025-48937 already demonstrated the risk; Soatok's Feb 2026 audit found additional issues |
| **Impact** | Compromised E2EE undermines the core value proposition. Press coverage of crypto bugs damages trust. |
| **Mitigation** | Pin vodozemac versions. Monitor CVE advisories and the matrix-org security mailing list. Security audit budgeted in Phase 6. Keep flutter_vodozemac updated within 48 hours of any security release. |
| **Contingency** | If a critical unpatched vulnerability is discovered, disable E2EE for new rooms and display a prominent security notice until patched. This is a nuclear option — the Matrix security team has historically patched within days. |

### Risk 7: Sliding Sync Homeserver Adoption

| Attribute | Detail |
|-----------|--------|
| **Severity** | Low |
| **Probability** | Low — Synapse has native support, enabled by default |
| **Impact** | Users on older homeservers get degraded performance (sync v2 fallback). First impressions may suffer. |
| **Mitigation** | Implement sync v2 fallback path with aggressive caching. Show a non-blocking banner suggesting the user ask their admin to upgrade. Target Synapse (dominant) and Conduit (has support). |
| **Contingency** | If a significant user segment is on non-Sliding-Sync servers, invest in sync v2 optimization: incremental sync caching, lazy room loading, background sync with local-first room list. This is ~2 weeks of additional work. |

---

*This document is the technical foundation for Gloam's implementation. It should be updated as architectural decisions are made or revised during development.*
