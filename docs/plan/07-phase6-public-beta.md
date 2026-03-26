# Phase 6: Public Beta

**Weeks 29-32 | 4 weeks**

*Last updated: 2026-03-25*

---

## Objectives

Transition Gloam from a feature-complete development build to a public-facing beta that can withstand real-world usage, security scrutiny, and app store review. This phase is about hardening, not building — every task here exists to ensure the previous 28 weeks of work ships reliably to real users on all 5 platforms.

## Success Criteria

| Metric | Target |
|--------|--------|
| Timeline scroll | 60 fps on all platforms (P95) |
| Memory usage (idle, 50 rooms) | < 200MB |
| Memory usage (active, 500 rooms) | < 400MB |
| App binary size (iOS/Android) | < 50MB |
| Cold start to room list visible | < 1.5 seconds |
| Crash-free session rate | > 99.5% |
| Security audit critical findings | 0 unresolved at launch |
| Security audit high findings | 0 unresolved at launch |
| App store approval | All 5 platforms |
| Beta tester signup target | 500+ users in first 2 weeks |

---

## Task Breakdown

### 1. Performance Optimization Pass (High Priority)

**Weeks 29-30 | ~8 days**

Systematic profiling and optimization across all platforms. Not guesswork — measure, identify bottlenecks, fix, verify.

#### 1.1 Profiling All Platforms

- Set up profiling infrastructure per platform
  - **iOS:** Xcode Instruments (Time Profiler, Allocations, Metal System Trace for Impeller)
  - **Android:** Android Studio Profiler (CPU, Memory, Energy), systrace for frame analysis
  - **macOS:** Instruments (same as iOS) + Activity Monitor for system resource usage
  - **Windows:** Visual Studio Diagnostic Tools, ETW traces for frame timing
  - **Linux:** `perf` for CPU profiling, Valgrind/Massif for memory, `flutter run --profile` with DevTools
- Flutter DevTools profiling on all platforms
  - Widget rebuild tracking (identify unnecessary rebuilds)
  - Timeline view for frame analysis (identify jank > 16ms frames)
  - Memory snapshot comparison (before/after navigation flows)
  - Network profiling (request count, payload sizes, timing)
- Establish baseline metrics for each platform before optimization
  - Cold start time
  - Room switch time
  - Scroll FPS during fast scroll in a 10,000-message room
  - Memory usage at rest, after 30 minutes of use, after 2 hours
  - Battery drain rate (mobile) during idle with sync active

#### 1.2 Timeline 60 FPS

- Target: zero dropped frames during normal scroll, < 1% dropped during fast fling scroll
- Optimization areas
  - **Message widget complexity:** Profile render time per message type (text, image, reply, reaction cluster). Identify expensive widgets and optimize.
  - **SliverList optimization:** Ensure `itemExtent` or `prototypeItem` is used where possible for O(1) layout. Use `RepaintBoundary` on message widgets to isolate repaints.
  - **Image decoding:** Move image decode off the UI thread. Use `ResizeImage` to decode at display size, not full resolution. Ensure thumbnail-to-full-resolution transition doesn't cause frame drops.
  - **Reaction rendering:** Reaction rows with many unique emoji can be expensive. Cache rendered reaction chip layouts. Limit visible reactions with "+N more" overflow.
  - **Rich text rendering:** Markdown/HTML rendering can be expensive for long messages with complex formatting. Pre-compute rendered spans and cache them.
  - **Avatar rendering:** Cache resolved avatar images. Avoid re-fetching on every rebuild.
- Impeller-specific optimizations
  - Verify Impeller is enabled on all platforms (default on iOS/Android, rolling out on desktop)
  - Profile shader compilation (Impeller pre-compiles, but verify no runtime shader compilation jank)
  - Test with `--trace-skia` or `--trace-impeller` for GPU frame timing
- Scroll physics tuning
  - Ensure platform-adaptive scroll physics (iOS bounce, Android overscroll glow)
  - Test scroll behavior with keyboard, trackpad, mouse wheel, touch
  - Verify momentum scrolling feels natural on each platform

#### 1.3 Memory Audit

- Target: < 200MB idle (50 rooms loaded), < 400MB active (500 rooms, multiple open timelines)
- Memory audit process
  - Take heap snapshots at key states: cold start, after initial sync, after opening 10 rooms, after 30 minutes of use, after navigating to all major screens
  - Identify retained objects that should have been collected
  - Check for listener/subscription leaks (especially Riverpod providers, stream subscriptions, matrix_dart_sdk callbacks)
- Key areas to audit
  - **Timeline cache:** Ensure messages outside the visible window are evicted. Set max cached messages per room (e.g., 500). LRU eviction for room timeline caches.
  - **Image cache:** Verify `PaintingBinding.instance.imageCache` size limits. Set `maximumSize` (1000 images) and `maximumSizeBytes` (100MB). Ensure MXC image cache on disk, not just in memory.
  - **SDK state:** matrix_dart_sdk `Room` objects hold room state. Ensure rooms not currently visible are in a lightweight state (state loaded on demand).
  - **E2EE state:** Megolm session cache can grow large in rooms with many participants. Verify sessions are evicted when no longer needed.
  - **Multi-account:** If multiple accounts are logged in, only foreground account should have full state in memory. Background accounts should be minimal.
- Implement memory pressure handling
  - iOS: respond to `didReceiveMemoryWarning` — evict caches, reduce timeline buffers
  - Android: respond to `onTrimMemory` levels — progressive cache eviction
  - Desktop: monitor process RSS, log warnings above thresholds

#### 1.4 Binary Size

- Target: < 50MB per platform (download size, not installed size)
- Size audit process
  - Use `flutter build --analyze-size` to generate size breakdown
  - Identify largest assets, packages, and native code contributions
  - Review Dart compiled code size (tree-shaking effectiveness)
- Optimization strategies
  - **Asset optimization:** Compress all bundled images. Use WebP instead of PNG where supported. Ensure no accidentally bundled development assets.
  - **Icon fonts:** Use a custom icon font with only used icons (not full Material Icons set). Or use SVG icons with `flutter_svg`.
  - **Package audit:** Review all pub dependencies. Remove unused packages. Check for packages that bundle large native libraries.
  - **Code splitting:** Ensure tree-shaking is effective. Remove dead code paths. Use `dart:mirrors` avoidance (already default in Flutter).
  - **Native library stripping:** Ensure release builds strip debug symbols. Verify `flutter_vodozemac` and `flutter_webrtc` native libraries are optimized.
  - **Deferred loading:** For large features (e.g., GIF picker, sticker browser), consider deferred component loading on mobile.
- Per-platform size targets
  - iOS: < 50MB IPA (App Thinning will reduce per-device download)
  - Android: < 30MB AAB (per-ABI split, per-density split)
  - macOS: < 60MB DMG (larger acceptable for desktop)
  - Windows: < 50MB MSIX
  - Linux: < 50MB AppImage/Flatpak

#### 1.5 Cold Start Optimization

- Target: < 1.5 seconds from tap to room list visible
- Measurement: instrument from `main()` to first frame with room list rendered
- Optimization areas
  - **Dart initialization:** Minimize work before `runApp()`. Defer non-critical initialization.
  - **SQLite warm-up:** Pre-open database connection during splash screen. Cache prepared statements.
  - **Sliding Sync initial response:** Optimize request to fetch minimal data for room list (name, last message, unread count). No full room state on cold start.
  - **SDK initialization:** Profile matrix_dart_sdk `Client` initialization. Identify slow steps (crypto store load, session restore).
  - **Theme/asset loading:** Pre-cache theme data. Minimize asset bundle access during startup.
- Splash screen strategy
  - Native splash screen (matching Gloam branding) displayed by OS while Flutter engine initializes
  - Flutter renders room list skeleton (shimmer loading state) within 500ms
  - Room list populates from local cache first, then updates from sync

#### 1.6 Network Optimization

- Reduce unnecessary network requests
  - Audit all API calls during common flows (app start, room switch, scroll)
  - Batch requests where possible
  - Ensure Sliding Sync window requests are debounced during fast scroll
  - Media requests: use `If-None-Match` / ETags for cache validation
- Connection management
  - Single persistent connection for sync (SSE or long-poll)
  - Connection pooling for media requests (limit concurrent downloads)
  - Exponential backoff on failures (not aggressive retry loops)
- Payload optimization
  - Request only needed fields in sync responses
  - Compress request/response bodies (gzip)
  - Minimize state event re-fetching (cache room state locally)

#### 1.7 SQLite Optimization

- Query performance audit
  - Enable SQLite query logging in debug builds
  - Identify slow queries (> 10ms)
  - Add indexes for common query patterns (messages by room+timestamp, FTS queries, room list sorting)
  - Use `EXPLAIN QUERY PLAN` to verify index usage
- Write performance
  - Batch inserts during sync processing (use transactions, not individual inserts)
  - WAL mode enabled (already default in drift, verify)
  - Avoid `VACUUM` during normal operation (schedule during app backgrounding)
- FTS5 search index
  - Verify FTS5 index update doesn't block UI (run in background isolate)
  - Test search performance with 100K+ indexed messages
  - Optimize tokenizer for chat content (handle emoji, URLs, code blocks)

---

### 2. Security Audit (High Priority)

**Weeks 29-30 | ~5 days (Gloam team effort, audit itself is external)**

#### 2.1 Engage External Security Firm

- Select a firm with experience in
  - End-to-end encryption implementations
  - Mobile application security (iOS and Android)
  - Matrix protocol (ideal but not required — E2EE expertise is more important)
- Firms to evaluate: Cure53, Trail of Bits, NCC Group, Include Security
  - Cure53 has audited Matrix/vodozemac before — strong context advantage
- Budget: plan for 2-4 week engagement depending on scope
- Timeline: engage firm by Week 27 so they can start during Week 29

#### 2.2 Audit Scope

**E2EE Implementation (Critical)**
- Review Gloam's integration with `flutter_vodozemac`
  - Correct usage of Olm/Megolm session management
  - Key request/share logic (no over-sharing of Megolm sessions)
  - Cross-signing key generation and verification flows
  - Key backup encryption and recovery
  - Session management (device list, device trust)
- Verify no plaintext leaks
  - Decrypted message content never written to disk unencrypted (except FTS5 index — verify SQLCipher is applied)
  - No plaintext in logs (redact message content from all log output)
  - No plaintext in crash reports
  - Memory handling: decrypted content cleared from memory when no longer displayed

**Authentication (High)**
- OIDC/OAuth 2.0 flow security
  - PKCE implementation correctness
  - Token storage (platform keychain, not shared preferences)
  - Token refresh logic (no token exposure during refresh)
  - Redirect URI validation (prevent authorization code interception)
- Legacy password auth (if supported)
  - Password never stored (only access token)
  - Secure password field (no autocomplete, no clipboard on sensitive fields)
- Session management
  - Session token rotation
  - Session revocation (logout invalidates all tokens)
  - Multi-device session handling

**Local Data Security (High)**
- SQLite database encryption
  - Verify SQLCipher (or equivalent) is applied to all databases containing message content
  - Key derivation for database encryption (from platform keychain, not hardcoded)
  - FTS5 index encryption verification
- Platform keychain usage
  - iOS Keychain: correct access group, `kSecAttrAccessibleAfterFirstUnlock`
  - Android KeyStore: hardware-backed where available
  - macOS Keychain: app-specific keychain access
  - Linux: `libsecret` / GNOME Keyring / KWallet
  - Windows: DPAPI / Credential Manager
- File system
  - Media cache: encrypted media stored encrypted at rest or in app sandbox
  - Temp files: cleaned up after use (no decrypted media in temp dirs)
  - App data directory permissions (no world-readable files)

**Network Security (Medium)**
- TLS configuration
  - Certificate pinning for known homeservers (optional, configurable)
  - No TLS downgrade (minimum TLS 1.2)
  - Certificate validation on all platforms
- API request security
  - No sensitive data in URL query parameters (use headers/body)
  - CSRF protection where applicable
  - Rate limiting awareness (don't leak timing information)
- WebRTC security
  - SRTP for media streams (default in WebRTC, verify not disabled)
  - DTLS for data channels
  - ICE candidate filtering (no private IP leak in candidates if configured)

**Push Notification Content (Medium)**
- Verify push notification payload does not contain plaintext message content
  - Notification content decrypted locally in notification extension
  - Push payload contains only: room ID, event ID, sender (for display name lookup)
- iOS Notification Service Extension
  - Runs in separate process with limited memory (24MB)
  - Must decrypt content within ~30 seconds
  - Verify extension doesn't cache decrypted content to disk
- Android notification handling
  - FirebaseMessagingService decrypts in-process
  - Verify no plaintext in notification channel data

#### 2.3 Remediation

- Triage findings by severity
  - **Critical:** Fix before any beta distribution. Zero tolerance.
  - **High:** Fix before public beta launch. Block release.
  - **Medium:** Fix within 2 weeks of beta launch. Track publicly.
  - **Low/Informational:** Backlog, fix in subsequent releases.
- Remediation process
  - Fix → internal review → auditor verification (for critical/high)
  - Document each finding and its resolution
  - Publish security audit summary post-launch (after fixes are deployed)
- Consider: publish the full audit report (redacted if needed) — transparency builds trust in the Matrix community

---

### 3. Beta Testing Program (Medium Priority)

**Weeks 30-31 | ~5 days**

#### 3.1 Distribution Channels

**iOS: TestFlight**
- Set up TestFlight in App Store Connect
- Internal testing group (team, up to 100)
- External testing group (public link, up to 10,000)
- TestFlight build configuration
  - Include debug symbols for crash symbolication
  - Enable TestFlight crash reports
  - Beta App Description and What to Test text
- Auto-distribute new builds from CI pipeline

**Android: Play Console Internal/Closed Testing**
- Internal testing track (immediate distribution, up to 100)
- Closed testing track (invite-only, up to 2,000 per track)
- Consider: open testing track for broader beta (opted-in from Play Store listing)
- AAB upload from CI pipeline
- Enable Play Console crash/ANR reporting

**macOS: Direct Distribution + TestFlight**
- TestFlight for macOS (same App Store Connect setup)
- Additionally: notarized DMG for direct download (for users who don't want TestFlight)
- Notarization via `xcrun notarytool` in CI

**Windows: Direct Distribution**
- Signed MSIX package for sideloading
- Host on GitHub Releases or gloam.chat/downloads
- Consider: Windows Insider / Microsoft Store beta track (if store submission timeline allows)
- Code signing certificate required (Extended Validation recommended)

**Linux: Direct Distribution**
- AppImage (universal, no install required)
- Flatpak (Flathub beta channel)
- `.deb` package for Debian/Ubuntu
- Host all on GitHub Releases + gloam.chat/downloads
- Consider: Snap package (less preferred in Matrix community, but wide reach)

#### 3.2 In-App Feedback

- Feedback button accessible from settings and via shake gesture (mobile) / keyboard shortcut (desktop)
- Feedback form
  - Category: Bug, Feature Request, Performance Issue, Other
  - Description (freeform text)
  - Optional screenshot attachment (auto-captured or from gallery)
  - Optional screen recording clip (mobile)
  - Automatically attached: app version, OS version, device model, current screen
  - Explicitly NOT attached: message content, room names, user IDs (privacy)
- Feedback destination
  - Dedicated Matrix room (e.g., `#gloam-beta-feedback:gloam.chat`) — meta (using Gloam to report Gloam issues)
  - Fallback: GitHub Issues via API (for users not in the feedback room)
  - Internal dashboard aggregating feedback by category and frequency

#### 3.3 Crash Reporting (Sentry)

- Integrate Sentry Flutter SDK (`sentry_flutter`)
- Configuration
  - DSN stored in build config (not hardcoded in source)
  - Environment tags: `beta`, `release`
  - Release tracking: map to app version + build number
  - Breadcrumbs: navigation events, network requests (URLs only, no payloads), user actions
  - **Scrub PII:** strip user IDs, room IDs, message content, IP addresses from all events
  - Sample rate: 100% for crashes, 10% for performance transactions during beta
- Crash grouping and alerting
  - Sentry alerts for new crash types and regressions
  - Weekly crash-free rate monitoring
  - Priority: crash-free rate > 99.5% before public launch
- Platform-specific setup
  - iOS: dSYM upload from CI for crash symbolication
  - Android: ProGuard/R8 mapping upload
  - Desktop: debug symbol upload

#### 3.4 Analytics (Opt-In, Privacy-Respecting)

- **Analytics are strictly opt-in**
  - First-run prompt: "Help improve Gloam by sharing anonymous usage data" with clear Yes/No
  - Default: No (opt-in, not opt-out)
  - Changeable anytime in Settings > Privacy
  - No analytics collected until explicit consent
- Analytics platform: **PostHog** (self-hosted instance)
  - Self-hosted on Gloam infrastructure (no data sent to third parties)
  - Open source, auditable
  - Feature flags capability (useful for gradual rollout)
- What we track (when opted in)
  - **Events:** app open, room switch, message sent (count only, no content), call started, call duration, feature used (search, reactions, threads, etc.)
  - **Performance:** cold start time, room switch time, scroll FPS percentiles
  - **Retention:** DAU/WAU/MAU (anonymized)
  - **Platform:** OS, OS version, app version, device category (phone/tablet/desktop)
- What we NEVER track
  - Message content, room names, user IDs, IP addresses
  - Matrix homeserver URLs
  - Contact lists or social graph
  - Keystroke timing or input patterns
  - Location data
- Privacy documentation: publish exactly what is tracked at gloam.chat/privacy

#### 3.5 Beta Matrix Space

- Create `#gloam:gloam.chat` Matrix space as the community hub
  - `#gloam-general:gloam.chat` — General discussion
  - `#gloam-beta-feedback:gloam.chat` — Bug reports and feedback from in-app
  - `#gloam-feature-requests:gloam.chat` — Feature discussion
  - `#gloam-announcements:gloam.chat` — Release notes, important updates (read-only for non-admins)
  - `#gloam-dev:gloam.chat` — Development discussion (open to contributors)
- Run the beta community on Gloam itself (dogfooding)
  - This stress-tests voice channels, moderation tools, custom emoji, etc.
  - Real community management validates the moderation features built in Phase 5
- Beta tester onboarding
  - Welcome message with links to feedback channels, known issues, and how to report bugs
  - Pinned message with current beta version and changelog

---

### 4. App Store Submissions (Medium Priority)

**Weeks 31-32 | ~5 days**

#### 4.1 iOS App Store

- App Store Connect setup
  - App name: "Gloam" (verify trademark availability)
  - Bundle ID: `chat.gloam.app`
  - Category: Social Networking
  - Age rating: 17+ (due to user-generated content in unmoderated rooms — App Store policy)
  - Content rights: confirm all assets are original or properly licensed
- Required assets
  - App icon: 1024x1024 (App Store), plus all required sizes for device
  - Screenshots: 6.7" (iPhone 15 Pro Max), 6.5" (iPhone 14 Plus), 5.5" (iPhone 8 Plus), 12.9" iPad Pro, 6.7" iPad mini — at least 3 screenshots per device class
  - App preview video (optional, strongly recommended): 15-30 second walkthrough
  - Description: 4000 char max, focus on user value not protocol details
  - Promotional text: 170 char, updatable without review
  - Keywords: matrix, chat, encrypted, messaging, communities, voice, video, private
- Privacy labels (App Privacy)
  - Data Used to Track You: None
  - Data Linked to You: Contact Info (email, if used for Matrix account), User ID
  - Data Not Linked to You: Crash data, Performance data (if analytics opted in)
  - Carefully audit against actual data collection — Apple rejects for inaccuracy
- Review preparation
  - Demo account credentials for Apple reviewers
  - Notes to reviewer explaining Matrix federation, E2EE, and how to test
  - Anticipate questions about user-generated content moderation (reference reporting and content filtering features)
- Entitlements
  - Push notifications
  - Background modes: voip, remote-notification, audio
  - Keychain sharing (for multi-account)
  - Network extensions (if VPN-like features in future)

#### 4.2 Google Play Store

- Play Console setup
  - Package name: `chat.gloam.app`
  - Category: Communication
  - Content rating: IARC questionnaire (will likely be Teen/16+ due to UGC)
  - Target API level: latest stable (API 35+)
- Required assets
  - Hi-res icon: 512x512
  - Feature graphic: 1024x500
  - Screenshots: phone (16:9 or 9:16), tablet (16:9), Chromebook (16:9) — 2-8 per device type
  - Short description: 80 char
  - Full description: 4000 char
- Data safety section
  - Data shared: None
  - Data collected: Account info (email, user ID), App activity (app interactions — only if analytics opted in), Crash logs
  - Security practices: Data encrypted in transit (TLS), Data encrypted at rest (SQLCipher), Data can be deleted (account deletion)
  - Carefully match actual behavior — Google audits these
- AAB requirements
  - App Bundle format (not APK)
  - Play App Signing enabled
  - 64-bit requirement (Flutter default)
  - Target SDK compliance

#### 4.3 macOS App Store

- Same App Store Connect as iOS
- Additional macOS requirements
  - App Sandbox entitlement (required for Mac App Store)
  - Hardened Runtime
  - Network: outgoing connections (client), incoming connections (server — for call reception if needed)
  - File access: user-selected files (for file sharing), downloads folder
  - Camera and microphone entitlements
- macOS-specific screenshots: at least 1 screenshot for each display size
- Consider: distribute outside Mac App Store as well (notarized DMG), since Mac App Store has lower adoption for chat apps

#### 4.4 Microsoft Store (Windows)

- MSIX package with Microsoft store-signed certificate
- Store listing
  - Category: Communication
  - Screenshots: at least 1 (1366x768 minimum)
  - Description, features, privacy policy URL
- Requirements
  - MSIX packaging (from `flutter build windows` output)
  - Code signing
  - Windows 10 1809+ minimum
- Alternative: distribute signed MSIX directly from gloam.chat (sideload) if Store process is slow

#### 4.5 Linux Distribution

- **Flathub** (primary)
  - Create Flatpak manifest
  - Submit to Flathub repository
  - Sandboxed with portal access for files, notifications, camera, microphone
  - Auto-updates via Flatpak infrastructure
- **Snap Store** (secondary)
  - Create snapcraft.yaml
  - Submit to Snap Store
  - Classic confinement may be needed for full system integration
- **AppImage** (universal fallback)
  - Self-contained, no installation
  - Host on GitHub Releases and gloam.chat
  - Include AppStream metadata for software center integration
- **AUR** (Arch Linux)
  - Community-maintained PKGBUILD
  - Can be official or community-contributed
- **.deb / .rpm** (direct packages)
  - For Debian/Ubuntu and Fedora/RHEL users who prefer native packages
  - Host in a Gloam APT/DNF repository or on GitHub Releases

---

### 5. Landing Page (Medium Priority)

**Week 31 | ~4 days**

#### 5.1 Domain and Hosting Setup

- Domain: `gloam.chat` (register if not already)
- Hosting: static site on Cloudflare Pages, Vercel, or Netlify
- SSL: automatic via hosting provider
- DNS: configure A/CNAME records

#### 5.2 Hero Section

- Tagline: communicates value without mentioning "Matrix" or "federation" in the first line
  - Lead with what it IS, not what it's built on
  - Example direction: "Chat that respects you." / "Your conversations. Your server. Your rules."
  - Subtitle introduces the value props: encrypted, fast, cross-platform, self-hostable
- Hero visual: high-quality app screenshot or rendered mockup showing Gloam's UI
  - Dark mode screenshot (matches dark-first design philosophy)
  - Show a populated space with rooms, messages, reactions — make it look alive
  - Consider: subtle animation (parallax scroll, typing indicator in screenshot)
- Primary CTA: "Download" (platform-detected, shows relevant platform)
- Secondary CTA: "Learn More" (scrolls to features)

#### 5.3 Features Section

- 3-5 feature blocks, each with
  - Headline, 1-2 sentence description, supporting screenshot or illustration
  - Focus on user outcomes, not technical implementation
- Feature highlights
  - **Fast everywhere:** "Room list loads in under a second. Messages appear instantly. No spinners."
  - **Encryption that disappears:** "End-to-end encrypted by default. No key management. No 'unable to decrypt.' Just private conversations."
  - **Voice channels:** "Always-on voice rooms. Drop in, hang out, leave when you're done. No calling required."
  - **Your data, your server:** "Works with any Matrix homeserver. Self-host for total control, or use a hosted server to get started."
  - **Every platform:** "iOS, Android, macOS, Windows, Linux. One account, everywhere."

#### 5.4 Downloads Section

- Platform detection: auto-highlight the detected platform's download button
- All platforms listed with icons
  - iOS: "App Store" badge → App Store link
  - Android: "Google Play" badge → Play Store link, "F-Droid" badge (if applicable)
  - macOS: "Mac App Store" badge + "Direct Download" link
  - Windows: "Microsoft Store" badge + "Direct Download" link
  - Linux: Flathub badge + AppImage/deb/rpm links
- Version number and release date displayed
- System requirements listed per platform

#### 5.5 "What is Matrix?" Explainer

- Positioned after downloads, for curious users (not blocking the primary flow)
- Brief, non-technical explanation
  - "Matrix is an open protocol for secure, decentralized communication"
  - Analogy: "Like email — you can choose your provider, but talk to anyone on any server"
  - Why it matters: data ownership, no vendor lock-in, interoperable
  - Visual: simple diagram showing federation concept (Server A ↔ Server B, users on each can chat)
- "Get started with matrix.org" — default homeserver recommendation
- "Self-host your own" — link to documentation

#### 5.6 Documentation Link

- "Docs" link in nav bar → docs.gloam.chat or gloam.chat/docs
- Links to user guide, developer docs, admin guide (content created in task 6)

#### 5.7 Footer

- Links: GitHub, Matrix space (`#gloam:gloam.chat`), Privacy Policy, Terms (if applicable)
- License badge: AGPL-3.0
- "Built on Matrix" with Matrix.org logo/link

#### 5.8 Technical Implementation

- Static site generator: Astro, Next.js (static export), or Hugo
  - Preference: Astro (fast, minimal JS, good for marketing sites)
  - Or: hand-crafted HTML/CSS if we want zero dependencies
- Dark theme (consistent with app aesthetic)
- Responsive: mobile-first, looks good on all screen sizes
- Performance: < 1 second load time, < 500KB total page weight
- SEO: meta tags, Open Graph, Twitter cards, structured data
- Analytics: same PostHog instance (self-hosted), opt-in cookie consent

---

### 6. Documentation (Low Priority)

**Weeks 31-32 | ~4 days**

#### 6.1 User-Facing Documentation

**Getting Started Guide**
- "Download and Install" — platform-specific instructions (mostly just "get from store")
- "Create an Account" — walkthrough of onboarding flow
  - Explain homeserver choice simply: "Use the default (matrix.org) or enter your organization's server"
  - SSO vs email/password
- "Your First Conversation" — send a DM, join a space, navigate the UI
- "Understanding Spaces and Rooms" — explain the hierarchy
- Screenshots for every step (auto-generated from app where possible)

**FAQ**
- "What is Matrix?" — concise, user-friendly
- "Is my data encrypted?" — explain E2EE, what it means practically
- "Can I talk to people on Element/other clients?" — explain federation interop
- "How do I move from Discord/Slack?" — practical migration guidance
- "What happens if I lose my phone?" — key backup and recovery
- "How do I set up voice channels?" — space admin guide
- "Why is Gloam different from Element?" — honest comparison

**Feature-Specific Guides**
- Custom emoji: creating, uploading, using
- Voice/video calls: troubleshooting audio/video
- Moderation: setting up roles, banning, content filtering
- Multi-account: adding accounts, switching, notification management
- Keyboard shortcuts reference (full list for desktop)

#### 6.2 Developer-Facing Documentation

**Architecture Overview**
- Project structure walkthrough (`lib/` directory layout)
- Feature module pattern (data/domain/presentation layers)
- State management approach (Riverpod providers, when to use what)
- SDK abstraction layer (services wrapping matrix_dart_sdk)
- How E2EE integrates (flutter_vodozemac, crypto service)

**Build Instructions**
- Prerequisites: Flutter SDK version, Dart version, platform toolchains
- Per-platform build instructions
  - iOS: Xcode version, signing setup, `flutter build ios`
  - Android: Android Studio, SDK version, `flutter build appbundle`
  - macOS: Xcode, entitlements, `flutter build macos`
  - Windows: Visual Studio, `flutter build windows`
  - Linux: build dependencies, `flutter build linux`
- CI/CD pipeline documentation (GitHub Actions workflow explanations)
- How to run tests: unit, widget, integration

**Contributing Guide**
- Code style (Dart analysis options, formatting with `dart format`)
- PR process, branch naming, commit message conventions
- How to add a new feature module
- How to add a new platform-specific integration
- Testing expectations (what needs unit tests, what needs widget tests)

#### 6.3 Admin-Facing Documentation

**Push Notification Setup**
- Sygnal deployment guide
  - Docker deployment (recommended)
  - Configuration: APNs credentials, FCM server key
  - Homeserver configuration to point to sygnal instance
- APNs setup
  - Apple Developer account requirements
  - Certificate vs key-based authentication
  - Production vs sandbox environment
- FCM setup
  - Firebase project creation
  - Server key generation
  - `google-services.json` configuration
- UnifiedPush
  - What it is and why it matters (de-Googled Android)
  - Compatible distributors (ntfy, NextPush)
  - Homeserver configuration for UnifiedPush

**Homeserver Recommendations**
- Minimum requirements for a good Gloam experience
  - Sliding Sync support (Synapse 1.100+, Conduit with SS support)
  - Authenticated media endpoints
  - TURN server for voice/video (coturn recommended)
  - LiveKit SFU for group calls and voice channels
- Recommended homeserver software: Synapse (most tested with Gloam)
- `.well-known` configuration for
  - Sliding Sync endpoint
  - TURN server
  - LiveKit SFU
  - Push gateway (sygnal)

**Self-Hosting Gloam Infrastructure**
- What Gloam itself needs hosted (for community features)
  - PostHog instance (optional, for analytics)
  - sygnal push gateway
  - LiveKit SFU
- Docker Compose example for full stack deployment
- Reverse proxy configuration (nginx/Caddy)

---

## Dependencies

### External Dependencies

| Dependency | Status | Risk | Mitigation |
|-----------|--------|------|------------|
| **Security audit firm availability** | Need to engage by Week 27 | Medium | Start outreach in Week 25. Have backup firms identified. Audit can overlap with other Phase 6 work. |
| **App Store review timelines** | iOS: 1-3 days typical, can be longer | Medium | Submit by Week 31 to have buffer. Prepare demo account and reviewer notes. |
| **Apple Developer Program** | Annual $99 membership | Low | Ensure enrollment is active before Week 30. |
| **Google Play Console** | $25 one-time fee | Low | Set up early. |
| **Code signing certificates** | Windows (EV cert ~$300-500/yr), macOS (Apple dev program) | Low | Procure by Week 28. |
| **Sentry account** | Free tier sufficient for beta | Low | Self-hosted Sentry is an option if preferred. |
| **PostHog instance** | Self-hosted, needs infrastructure | Medium | Set up by Week 28. Can use PostHog Cloud temporarily if self-hosted isn't ready. |
| **Domain (gloam.chat)** | Must be registered | Low | Register immediately if not already owned. |

### Internal Dependencies (Prior Phases)

| Dependency | Phase | Required For |
|-----------|-------|-------------|
| All features complete and functional | Phases 1-5 | Performance optimization targets, security audit scope |
| CI/CD pipeline for all platforms | Phase 0 | Automated beta distribution, store submissions |
| E2EE implementation | Phase 1 | Security audit E2EE scope |
| Push notification system | Phase 2 | Push notification security audit, store submission |
| Platform-specific integrations | Phase 4 | Platform-specific performance profiling, store requirements |
| Voice/video features | Phase 5 | Security audit WebRTC scope, performance profiling |

---

## Key Decisions

### 1. License: AGPL-3.0

**Decision: AGPL-3.0**

- Strong copyleft ensures all derivative works remain open source
- Network clause (AGPL vs GPL): if someone modifies Gloam and runs it as a service, they must release source
- Consistent with Matrix ecosystem norms (Synapse is AGPL, Element is Apache 2.0)
- AGPL is more protective than Apache 2.0 — prevents proprietary forks
- Doesn't restrict end users in any way
- Compatible with most dependencies (check: flutter_vodozemac license, flutter_webrtc license, matrix_dart_sdk is BSD-2-Clause — compatible)
- Include `COPYING` file and license headers in all source files

### 2. Analytics: PostHog (Self-Hosted)

**Decision: Self-hosted PostHog**

- Open source, self-hostable — no data leaves Gloam infrastructure
- Avoids sending ANY user data to third parties
- Feature flags built in (useful for gradual feature rollout in beta)
- Session replay available but NOT enabled (too privacy-invasive for a chat app)
- Alternative considered: Plausible (simpler, but lacks feature flags and event tracking depth)
- Alternative considered: no analytics at all — rejected because we need basic usage data to prioritize development
- The self-hosted requirement is non-negotiable for a privacy-focused chat app

### 3. Distribution Strategy

**Decision: App stores as primary, direct downloads as secondary**

- iOS: App Store only (no realistic alternative for mainstream distribution)
- Android: Google Play primary, direct APK/F-Droid for de-Googled users
  - F-Droid inclusion requires no proprietary dependencies (FCM is optional via UnifiedPush, so this is achievable)
- macOS: Mac App Store + notarized DMG direct download
- Windows: Microsoft Store + signed MSIX direct download
- Linux: Flathub primary + AppImage/deb/rpm
- Rationale: app stores provide discovery, auto-updates, and user trust. Direct downloads provide freedom and reach users who avoid stores.

### 4. Crash Reporting: Sentry

**Decision: Sentry (cloud, with strict PII scrubbing)**

- Industry standard for Flutter crash reporting
- Rich crash context without PII
- Alternative considered: self-hosted Sentry — operationally complex, deferred to post-beta
- Alternative considered: Firebase Crashlytics — rejected, sends data to Google, inconsistent with privacy stance
- PII scrubbing rules are non-negotiable:
  - Strip all Matrix user IDs (`@user:server`)
  - Strip all room IDs (`!roomid:server`)
  - Strip all message content
  - Strip IP addresses
  - Strip homeserver URLs
  - Only retain: stack traces, device info, OS version, app version, breadcrumb navigation events

### 5. Landing Page Technology

**Decision: Astro (static site)**

- Fast, minimal JavaScript, excellent for a marketing/landing page
- Ships near-zero JS by default (add interactivity only where needed)
- Good DX with component islands (can use React for interactive bits)
- Static output: deploy to any CDN
- Alternative considered: Next.js — overkill for a single-page landing site
- Alternative considered: plain HTML/CSS — viable but harder to maintain, no component reuse

---

## What "Done" Looks Like

### Performance
- Timeline scrolls at 60 fps on all platforms (verified with profiling tools, not just eyeballing)
- Memory stays under budget on 2-hour usage sessions across all platforms
- Cold start < 1.5 seconds on mid-range devices (iPhone 12-era, Pixel 6-era, 4-year-old laptop)
- Binary size within budget on all platforms
- No visible jank during common flows: room switch, scroll, send message, open emoji picker, join call
- Performance regression tests in CI (basic benchmarks that fail the build if metrics degrade)

### Security
- External audit complete with report delivered
- All critical and high findings resolved and verified by auditors
- No plaintext message content in logs, crash reports, or unencrypted storage
- E2EE implementation verified correct by auditors
- Security audit summary published (with responsible disclosure timeline for any findings)

### Beta Program
- TestFlight, Play Console, and direct downloads all functioning
- In-app feedback mechanism works and delivers reports to the beta feedback room
- Sentry capturing crashes with correct symbolication on all platforms
- PostHog collecting opted-in analytics events
- Beta Matrix space active with at least the core channels
- 500+ beta testers within 2 weeks of opening beta

### App Store Presence
- iOS App Store: approved and listed (beta or full release)
- Google Play: approved and listed
- Mac App Store: approved and listed
- Microsoft Store: submitted (approval timeline may vary)
- Flathub: listed
- All store listings have screenshots, descriptions, and privacy labels accurate

### Landing Page
- gloam.chat live and loading in < 1 second
- Clear value proposition in hero section
- Downloads section with platform detection
- "What is Matrix?" explainer for newcomers
- Links to documentation and community
- Mobile responsive, dark theme, polished

### Documentation
- Getting started guide that a non-technical user can follow
- FAQ covering the 10 most common questions
- Developer build instructions that work on a fresh machine
- Admin guide for push notification and homeserver setup
- All hosted at docs.gloam.chat or gloam.chat/docs

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Security audit finds critical E2EE flaw | Low | Critical | Budget 1 week of remediation time. flutter_vodozemac is battle-tested (used by FluffyChat), reducing likelihood. |
| App Store rejection (iOS) | Medium | High | Submit early (Week 31). Most common rejection reasons: metadata inaccuracy, missing privacy labels, UGC moderation concerns. Address proactively. |
| Performance targets not met on older devices | Medium | Medium | Profile on target devices early (Week 29). Have a "minimum supported device" list. Acceptable to miss 60fps on very old hardware if 50fps+ is achieved. |
| Beta tester volume insufficient | Medium | Low | Promote in Matrix community channels, Hacker News, Reddit r/selfhosted, r/privacy. The Matrix community is hungry for good clients — awareness shouldn't be hard. |
| PostHog self-hosting operational burden | Medium | Low | Use PostHog Cloud for beta period with data minimization. Migrate to self-hosted before general availability. |
| Landing page design doesn't match app quality | Low | Medium | Apply same design rigor to the site as the app. Dark theme, intentional typography, no generic template energy. |

---

## Estimated Effort

| Task | Estimated Days | Weeks |
|------|---------------|-------|
| Performance Optimization Pass | 8 | 29-30 |
| Security Audit (internal prep + remediation) | 5 | 29-30 |
| Beta Testing Program Setup | 5 | 30-31 |
| App Store Submissions | 5 | 31-32 |
| Landing Page (gloam.chat) | 4 | 31 |
| Documentation | 4 | 31-32 |
| Buffer / Overflow | 3 | 32 |
| **Total** | **34 days** | **4 weeks** |

Note: The external security audit runs in parallel (performed by the auditing firm while the team works on other tasks). The 5 days allocated are for internal preparation, providing access/context to auditors, and remediating findings.

---

## Change History

- 2026-03-25: Initial specification created
