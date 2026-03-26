# Matrix Client Landscape Research

*Last updated: 2026-03-25*

---

## Table of Contents

1. [Element (Web, Desktop, Mobile)](#1-element-web-desktop-mobile)
2. [Cinny](#2-cinny)
3. [FluffyChat](#3-fluffychat)
4. [Nheko](#4-nheko)
5. [Fractal](#5-fractal)
6. [Hydrogen](#6-hydrogen)
7. [SchildiChat](#7-schildichat)
8. [Thunderbird](#8-thunderbird-matrix-support)
9. [Other Notable Clients](#9-other-notable-clients)
10. [Cross-Client UX Pain Points](#10-cross-client-ux-pain-points)

---

## 1. Element (Web, Desktop, Mobile)

### Overview

The flagship/reference Matrix client, developed by Element (formerly New Vector), the primary commercial entity behind Matrix. Element exists in two generations: **Element Web/Desktop** (legacy, still maintained) and **Element X** (next-gen mobile, now the default).

### Element Web/Desktop

| Attribute | Detail |
|---|---|
| **Language** | TypeScript (93.2%) |
| **Framework** | React 19+, Webpack 5, PostCSS |
| **Matrix SDK** | matrix-js-sdk + @matrix-org/crypto-wasm (Rust-based E2EE) |
| **Desktop wrapper** | Electron |
| **Design system** | Compound (@vector-im/compound-web) |
| **State management** | Flux-inspired pattern with central MatrixDispatcher |
| **GitHub stars** | ~12.9k |
| **Contributors** | ~599 |
| **License** | AGPL-3.0 / GPL-3.0 / Commercial (tri-licensed) |
| **Latest release** | v1.12.13 (March 2026) |

**Architecture notes:**
- `MatrixChat` root component implements a state machine (LOADING, LOGIN, REGISTER, LOGGED_IN)
- `MatrixClientPeg` singleton for SDK client access
- Component hierarchy: MatrixChat -> LoggedInView -> RoomView -> TimelinePanel -> MessagePanel -> EventTile
- matrix-react-sdk has been **deprecated and folded into element-web** as a monorepo (pnpm workspaces + Nx)
- Token storage uses AES-GCM encryption in IndexedDB (web) or filesystem (Electron)
- By default, matrix-js-sdk uses `MemoryStore` to store events, a key contributor to memory issues

**UX strengths:**
- Most feature-complete Matrix client (threads, spaces, VoIP, widgets, integrations)
- Strong E2EE with cross-signing, key backup, device verification
- Voice/video calling with screenshare, multi-person calls
- URL previews, polls, rich replies, reactions
- Active development with frequent releases

**UX weaknesses:**
- Bloated and resource-intensive: 300-900 MB RAM, with reports of memory leaks climbing to 2.5 GB+
- Electron desktop app compounds the resource problem (bundled Chromium)
- Initial sync can take 1-20+ minutes for accounts in many rooms
- matrix-js-sdk bundle grew from 1.37 MB to 5.67 MB, slowing startup especially on mobile networks
- Spaces/subspaces navigation is clunky: no unified chat list, subspaces require entering the space to view rooms
- No "mark all rooms in space as read" function
- No multi-account support
- Custom emoji/sticker support is limited (requires integration manager for stickers)
- The interface is cluttered for new users: too many buttons, widgets, and settings

**Key user complaints (GitHub, HN, forums):**
- "Client is bloated and resource intensive" -- consistent across all feedback channels
- Chrome/Firefox OOM crashes or "slowing down your browser" warnings in large rooms
- "Unable to decrypt" messages remain a persistent cross-client issue
- Verification UX is confusing: monthly issues with devices not being correctly verified
- Startup times beyond 1 minute, webapp crashes after >1 hour open
- Spaces UX is confusing: subspace creation avoids the term "subspace," inconsistent display of children

### Element X (Mobile)

| Attribute | Detail |
|---|---|
| **iOS language** | Swift (99.9%) with SwiftUI |
| **Android language** | Kotlin (98.8%) with Jetpack Compose |
| **Matrix SDK** | matrix-rust-sdk (shared Rust core via UniFFI bindings) |
| **iOS GitHub stars** | ~776 |
| **Android GitHub stars** | ~2,000 |
| **License** | AGPL-3.0 / Commercial (dual-licensed) |

**Architecture notes:**
- Rust core handles all heavy lifting (sync, E2EE, protocol logic) via matrix-rust-sdk
- Native UI layers (SwiftUI / Jetpack Compose) for platform-optimal rendering
- Uses Sliding Sync (Matrix 2.0) for instant login and sync: claimed 6,000x faster than classic Element
- Native OIDC for modern auth (2FA, MFA, passkeys, token refresh)
- MatrixRTC / Element Call for voice/video

**UX strengths:**
- Dramatically faster than legacy Element on login, launch, and sync
- Native UI frameworks give better performance and accessibility
- Rust core means bug fixes on one platform benefit both
- Recently achieved feature parity: threads and spaces now supported

**UX weaknesses:**
- Performance reports are mixed; some users say clicking a conversation takes 0.5-1.0s vs. instant on classic
- Newly implemented features (threads, spaces) have stability questions
- Different calling infrastructure (MatrixRTC) from classic Element
- Classic mobile app sunset announced for end of 2025, forcing migration
- Feature parity is recent; organizational/complex use cases still being validated

---

## 2. Cinny

### Overview

A web-first Matrix client focusing on simplicity, elegance, and a Discord-like layout. Widely recommended as the best UX alternative to Element.

| Attribute | Detail |
|---|---|
| **Language** | TypeScript (98.9%) |
| **Framework** | React, Vite 5 |
| **Desktop wrapper** | Tauri (not Electron -- lighter) |
| **Matrix SDK** | matrix-js-sdk + @matrix-org/matrix-sdk-crypto-wasm |
| **GitHub stars** | ~3,500 |
| **Contributors** | ~80 |
| **License** | AGPL-3.0 |
| **Latest release** | v4.11.1 (March 2026) |
| **Platforms** | Web, Desktop (Windows, macOS, Linux) |

**Architecture notes:**
- Built on matrix-js-sdk (same as Element Web) but with a completely independent UI layer
- Tauri for desktop (Rust backend instead of Chromium, significantly lighter than Electron)
- Vite for fast HMR and development
- Core utilities organized into `matrix.ts` and `room.ts` modules
- Uses browser-encrypt-attachment for E2EE file handling

**UX strengths:**
- Clean, Discord-like server/channel layout with sidebar navigation
- Subspaces mimic Discord's category structure (widely praised)
- Significantly lighter than Element while using the same SDK
- Full custom emoji and sticker support
- Markdown and LaTeX support out of the box
- Encrypted room search works
- Custom roles with colors and icons
- Carefully crafted themes
- Excellent keyboard navigation
- Custom CSS theme support

**UX weaknesses:**
- No mobile app (web only + desktop)
- No voice/video calling
- Device verification shows as "Unsupported message" in some cases
- Threads support is present but spaces support was "in progress" (recently improved)
- Smaller contributor base than Element

**Community and maintenance:**
- Actively maintained; regular security patches and feature releases through 2026
- Growing community interest, especially from Discord refugees
- Maintained by Ajay Bura (@ajbura) and community contributors

---

## 3. FluffyChat

### Overview

A Flutter-based Matrix client targeting simplicity and accessibility across all platforms, with a friendly/cute brand identity.

| Attribute | Detail |
|---|---|
| **Language** | Dart (93.8%) |
| **Framework** | Flutter (Material You theming) |
| **Matrix SDK** | Matrix Dart SDK (formerly matrix_dart_sdk, by Famedly) |
| **GitHub stars** | ~2,600 |
| **License** | AGPL-3.0 |
| **Latest release** | v2.5.0 (March 2026) |
| **Platforms** | Android, iOS, Web, Linux (Flatpak, Snap), macOS |
| **Maintainer** | Christian (Krille) Kussowski; initiated at Famedly GmbH, now community-driven nonprofit |

**Architecture notes:**
- Pure Flutter app with Matrix Dart SDK handling all protocol logic
- Matrix Dart SDK supports UIA, SSSS, calls, and uses "fancy mechanisms" for snappy performance
- Material You design language on Android
- Backed by SQLite for local storage

**UX strengths:**
- True cross-platform from a single codebase (mobile, desktop, web)
- Simple, approachable UI targeted at WhatsApp/Telegram users
- Voice messages, location sharing, emoji verification, push notifications
- Stories feature (similar to WhatsApp Status)
- Polls and threads support (added v2.3.0)
- Encrypted chat backup, cross-signing
- Spaces support
- Lightweight compared to Element

**UX weaknesses:**
- Flutter rendering can feel non-native on desktop platforms
- Missing video calls and group call functionality in some contexts
- Historically had database corruption bugs on Android (fixed in v2.3.0)
- "Half working Flutter client" perception from earlier years still lingers
- Smaller feature set than Element overall
- UI, while clean, is basic compared to Cinny's polish

**Key user complaints:**
- Occasional HTTP errors related to room events and timeline requests
- Performance leaks have been addressed but created trust issues
- Some users report it feeling more like a mobile app stretched to desktop rather than a native desktop experience

---

## 4. Nheko

### Overview

A native desktop Matrix client built with Qt and C++20, prioritizing native performance and a mainstream chat feel.

| Attribute | Detail |
|---|---|
| **Language** | C++20 |
| **Framework** | Qt 6 (QML for UI) |
| **Matrix SDK** | Custom: mtxclient (built on libcurl) |
| **Encryption** | libolm |
| **Storage** | LMDB (Lightning Memory-Mapped Database) |
| **GitHub stars** | ~2,400 |
| **License** | GPL-3.0 |
| **Platforms** | Linux, macOS, Windows |
| **Build system** | CMake |

**Architecture notes:**
- mtxclient is Nheko's own C++ Matrix client library built on libcurl
- Uses LMDB for fast persistent storage (memory-mapped, zero-copy)
- GStreamer for multimedia (VoIP, video playback)
- nlohmann-json for JSON, libcmark for Markdown, libre2 for regex
- Native rendering via Qt -- no Electron or web overhead

**Tech stack dependencies:**
- Qt6 (base, tools, SVG, multimedia, declarative)
- libevent, libspdlog, OpenSSL
- GStreamer plugins for VoIP

**UX strengths:**
- Extremely lightweight: 30-200 MB RAM with minimal CPU
- Fast startup and room switching (native compiled)
- VoIP calls (voice and video)
- Custom stickers and emoji, inline media widgets
- Typing notifications, read receipts, presence
- Message & mention notifications
- Username auto-completion

**UX weaknesses:**
- Desktop only (no mobile)
- Spaces support incomplete/in progress
- Threads not supported
- Smaller community means slower feature development
- Qt/QML can feel different from mainstream desktop apps on non-KDE desktops
- Occasional html escaping bugs and file permission issues (recently patched)

**Maintenance:** Actively maintained with small security and compatibility releases in 2025. Niche but dedicated community.

---

## 5. Fractal

### Overview

The official GNOME Matrix client, rewritten in Rust with GTK4 and the matrix-rust-sdk.

| Attribute | Detail |
|---|---|
| **Language** | Rust |
| **Framework** | GTK 4 + libadwaita |
| **Matrix SDK** | matrix-rust-sdk |
| **Build system** | Meson + Ninja (+ Cargo) |
| **License** | GPL-3.0 |
| **Platforms** | Linux (Flatpak primary), could run on other GTK-supported platforms |
| **Repository** | gitlab.gnome.org/World/fractal (primary); mirrors on GitHub |

**Architecture notes:**
- Complete rewrite (Fractal 5+) from scratch using GTK4 and matrix-rust-sdk (previously used RUMA + direct REST calls)
- libadwaita for adaptive layouts (phone and desktop)
- Meson build system with Rust/Cargo integration
- Benefits from matrix-rust-sdk improvements automatically (same SDK as Element X)

**UX strengths:**
- Deep GNOME integration, follows GNOME HIG
- Adaptive UI works on phones and desktops
- Native performance, no Electron overhead
- Cross-signing encryption support
- Room version 12 support, knocking
- OAuth 2.0 login support (Fractal 11)
- Clean, minimal interface

**UX weaknesses:**
- No VoIP/voice calls
- No threads support (open issue)
- Spaces not fully supported
- Linux-only in practice (GNOME ecosystem)
- Missing features compared to Element make it unsuitable as a primary client for many users
- Smaller user base

**Maintenance:** Actively developed within the GNOME project. Regular releases (Fractal 11.1 in 2025). Benefits from being part of a major desktop environment ecosystem.

---

## 6. Hydrogen

### Overview

A minimal, performance-focused Matrix web client built by the Element team, designed for offline functionality and broad browser support.

| Attribute | Detail |
|---|---|
| **Language** | TypeScript (48.5%) + JavaScript |
| **Framework** | Custom MVVM, Vite build |
| **Matrix SDK** | Custom (built-in, not matrix-js-sdk) |
| **GitHub stars** | ~709 |
| **License** | AGPL-3.0 / Commercial (dual-licensed) |
| **Latest release** | v0.5.1 (October 2024) |
| **Platforms** | Web (any browser, including legacy), installable as PWA |

**Architecture notes:**
- MVVM (Model-View-ViewModel) pattern throughout
- Standalone webapp or embeddable widget for existing sites
- Lazy loading of unused application parts after initial page load
- Designed as an SDK itself -- meant to be reusable
- Custom lightweight sync and storage implementation
- No dependency on matrix-js-sdk

**UX strengths:**
- Extremely lightweight and fast
- Works offline
- Broad browser support (legacy browsers, mobile browsers)
- PWA installable
- Embeddable into other apps
- Minimal resource usage

**UX weaknesses:**
- Very limited feature set (basic messaging only)
- No threads, no spaces, no VoIP
- No rich media features
- Feels bare-bones compared to any other client
- Not designed for daily driver use

**Maintenance status:** In maintenance mode -- accepting bug reports but discouraging feature requests. Last release was October 2024. The Element team's focus has shifted to Element X. Not deprecated, but effectively in life-support.

---

## 7. SchildiChat

### Overview

A fork of Element (both Web/Desktop and Android) that prioritizes a more traditional instant messenger UX. Hobby project, not commercially driven.

| Attribute | Detail |
|---|---|
| **Language** | Same as Element (TypeScript for web, Kotlin for Android) |
| **Framework** | Same as Element (React for web, Jetpack Compose for Android) |
| **Matrix SDK** | Same as Element (matrix-js-sdk for web, matrix-rust-sdk for Android) |
| **Web/Desktop GitHub stars** | ~461 |
| **License** | Same as Element |
| **Latest release** | v1.11.36-sc.3 (2026) |
| **Platforms** | Web, Desktop (Electron), Android |

**Key improvements over Element:**
- **Unified chat list**: Direct and group chats in a single combined list (like WhatsApp/Telegram) instead of Element's separated tabs
- **Message bubbles**: Optional bubble styles with selectable corner radius and optional tail
- **Customizable room list**: Compact single-line, intermediate, and roomy two-line preview modes
- **Improved theming**: More theming customization options
- **Community features**: Additional community-oriented features that Element deprioritizes

**Architecture approach:**
- Minimal architectural divergence from upstream to reduce merge conflicts
- UI tweaks layered on top of Element's codebase
- Tracks upstream Element releases closely
- SchildiChat Android Next is now a fork of Element X Android

**UX strengths:**
- Familiar IM feel vs. Element's Slack-like approach
- Unified chat list is the single most requested UX improvement users want in Element
- Message bubbles make conversations easier to scan
- Same feature set as Element plus UX polish

**UX weaknesses:**
- Dependent on upstream Element for core features and bug fixes
- Fork maintenance creates lag between Element releases
- Hobby project -- no guarantees on longevity
- Smaller community support than Element

---

## 8. Thunderbird (Matrix Support)

### Overview

Mozilla Thunderbird added Matrix as a chat protocol alongside its existing email, calendar, and task management features, starting with version 102 (2022).

| Attribute | Detail |
|---|---|
| **Language** | JavaScript (Thunderbird chat core) |
| **Framework** | Thunderbird platform (XUL/web technologies) |
| **Matrix SDK** | Custom JavaScript implementation (depends on external Matrix SDK) |
| **Platforms** | Windows, macOS, Linux |

**Architecture approach:**
- Matrix is implemented as one of several chat protocols (alongside IRC, XMPP)
- Protocols implemented in "chat core" using JavaScript, implementing prplI* interfaces
- Matrix appears as a chat tab alongside inbox, address book, calendar
- Spaces toolbar on left provides tab-switching between Thunderbird modules

**Features:**
- Text messaging in Matrix rooms
- E2EE support
- File sharing
- Group chats

**Limitations:**
- **Text messages only** (no media-rich features)
- No dynamic back-scroll: most old messages from previous sessions not shown
- Only unread messages shown on initial connection
- No voice/video calls
- No threads, no reactions, no stickers
- Minimal Matrix feature coverage compared to dedicated clients
- Best thought of as a "basic presence" in Matrix rather than a full client

**Maintenance:** Maintained as part of Thunderbird, but Matrix support is not a primary focus. Feature development is slow.

---

## 9. Other Notable Clients

### Gomuks

| Attribute | Detail |
|---|---|
| **Language** | Go (49.2%) + TypeScript/JavaScript for web frontend |
| **Matrix SDK** | mautrix-go (by tulir, author of many Matrix bridges) |
| **GitHub stars** | ~1,600 |
| **License** | AGPL-3.0 |
| **Latest release** | v26.03 (March 2026) |

- **Architecture:** Separate backend + frontend model. Web frontend is production-ready, terminal frontend is experimental. Future plans to combine into single binary.
- **Features:** Space viewer, URL previews, media upload dialog with resize/re-encode, reactions, mass-redacting
- **Strengths:** Extremely lightweight; developer/power-user oriented; maintained by tulir (prolific Matrix bridges developer); dual terminal+web frontends
- **Weaknesses:** Terminal frontend lacks Matrix login support (needs web); not designed for mainstream users; limited UI polish

### NeoChat

| Attribute | Detail |
|---|---|
| **Language** | C++ / QML |
| **Framework** | KDE Frameworks (Qt) |
| **Matrix SDK** | libQuotient (Qt-based Matrix SDK) |
| **Platforms** | Linux, Windows, macOS, Plasma Mobile, Android |
| **License** | GPL-3.0 |

- **Strengths:** Native KDE integration, Spaces support, SSO login, Matrix URI handling, adaptive UI for mobile
- **Weaknesses:**
  - **No VoIP**
  - **No threads**
  - **E2EE is experimental and unreliable**: stops sending encryption keys after a few days; first message in a megolm session sometimes undecryptable; explicitly warns against relying on it as sole client
  - libQuotient development pace is slow compared to matrix-rust-sdk or matrix-js-sdk

### Commet

| Attribute | Detail |
|---|---|
| **Language** | Dart (90.1%) |
| **Framework** | Flutter + custom Tiamat UI wrapper around Material |
| **Matrix SDK** | Matrix Dart SDK (same family as FluffyChat) |
| **GitHub stars** | ~907 |
| **License** | AGPL-3.0 |
| **Platforms** | Windows, Linux, Android (macOS, iOS planned) |
| **Latest release** | v0.4.1 (March 2026) |

- **Strengths:** Discord-like UI, multi-account support from the ground up, custom emoji/stickers, GIF search, threads, encrypted room search, URL previews
- **Weaknesses:** No macOS/iOS yet, no custom theming, no account registration flow, GIF button uploads files rather than links, text formatting issues reported, relatively small community

### Syphon (Honorable Mention)

- Flutter/Dart Matrix client focused on privacy
- Uses Matrix Dart SDK
- Development has slowed significantly
- Interesting for its privacy-centric design choices but not recommended as a daily driver

---

## 10. Cross-Client UX Pain Points

These are the issues that consistently appear across forums (Reddit, HN, GitHub issues, Linux Mint forums, GrapheneOS forums, etc.) regardless of which client is being discussed.

### Tier 1: Universal, Severe

**1. "Unable to Decrypt" Messages**
The single most complained-about issue across the entire Matrix ecosystem. Causes include missing encryption keys, unverified sessions, federation key-sharing failures, and key backup configuration errors. Users report entire conversations being unreadable. This problem alone has driven more people away from Matrix than any other single issue.

**2. Device Verification / Cross-Signing Confusion**
Users experience monthly issues with devices not being correctly verified. The shield icon system is confusing (messages should either be visible and secure, or hidden). Element X repeatedly prompts for verification even after completing it. The process requires "encryption literacy" that mainstream users don't have.

**3. Slow Initial Sync**
The original /sync API sends far too much data. Users report 1-20+ minute initial syncs. For accounts in 2,200+ rooms, sync can take 400+ seconds pulling 100k+ events. Sliding Sync (Matrix 2.0) dramatically improves this, but requires server support and is not yet universal.

**4. Performance / Resource Usage**
Element Web: 300-900 MB RAM baseline, memory leaks to 2.5 GB+, Chrome OOM crashes. The Electron wrapper adds insult to injury. Even Element X has mixed performance reports. Native clients (Nheko, Fractal) are dramatically better but lack features.

### Tier 2: Widespread, Significant

**5. Onboarding / Server Selection Confusion**
Picking a homeserver is overwhelming for new users. The matrix.org "Try Matrix" page is confusing. The client selection matrix is incomprehensible. Element's UI is cluttered for first-time users. Most new users bounce.

**6. Spaces UX is Broken**
Subspace navigation is clunky across clients. Element requires entering a space to see rooms (vs. Discord's always-visible sidebar). Subspace creation avoids the term "subspace" confusingly. Children of subspaces randomly missing over federation. No "mark all in space as read."

**7. Feature Fragmentation**
No single client has everything. Want Discord-like UX? Cinny, but no mobile or calls. Want mobile? Element X, but it just reached feature parity. Want native performance? Nheko, but no threads or spaces. Users constantly compromise.

**8. Multi-Account Support**
Element Web/Desktop doesn't support multiple accounts. Cinny doesn't. Only Commet and gomuks have proper multi-account. This is table stakes for users bridging between servers.

### Tier 3: Common Annoyances

**9. No Unified Chat List (Element)**
Element separates DMs and groups into tabs. Every other major messenger (WhatsApp, Telegram, Signal) uses a unified list. SchildiChat exists primarily to fix this one issue.

**10. Sticker/Custom Emoji Ecosystem**
Element requires an integration manager for stickers. Custom emoji support varies wildly across clients. No standardized approach.

**11. Search**
Encrypted message search doesn't work in Element Web. Cinny handles it better. Server-side search is inconsistent.

**12. Voice/Text-to-Speech**
Voice-to-text "always gets cut off" in Element X. Voice messages have inconsistent support across clients.

---

## SDK Landscape Summary

| SDK | Language | Used By | Maturity | Notes |
|---|---|---|---|---|
| **matrix-rust-sdk** | Rust (with Swift/Kotlin/WASM bindings) | Element X, Fractal | High, rapidly evolving | The future of the ecosystem; Sliding Sync, native OIDC |
| **matrix-js-sdk** | TypeScript/JavaScript | Element Web, Cinny, SchildiChat Web | Mature but heavy | Bundle size issues (5.67 MB); MemoryStore causes RAM problems |
| **Matrix Dart SDK** | Dart | FluffyChat, Commet | Mature | Good feature coverage; maintained by Famedly |
| **libQuotient** | C++ (Qt) | NeoChat | Moderate | E2EE experimental and unreliable; slow development |
| **mtxclient** | C++ (libcurl) | Nheko | Moderate | Nheko-specific; solid but niche |
| **mautrix-go** | Go | gomuks | Moderate | Maintained by tulir (bridge ecosystem author) |

---

## Client Quick-Reference Matrix

| Client | Language | SDK | Platforms | Stars | Threads | Spaces | VoIP | E2EE | Active |
|---|---|---|---|---|---|---|---|---|---|
| Element Web | TypeScript/React | matrix-js-sdk | Web, Desktop | 12.9k | Yes | Yes | Yes | Yes | Yes |
| Element X iOS | Swift/SwiftUI | matrix-rust-sdk | iOS | 776 | Yes | Yes | Yes | Yes | Yes |
| Element X Android | Kotlin/Compose | matrix-rust-sdk | Android | 2k | Yes | Yes | Yes | Yes | Yes |
| Cinny | TypeScript/React | matrix-js-sdk | Web, Desktop | 3.5k | Yes | Partial | No | Yes | Yes |
| FluffyChat | Dart/Flutter | Matrix Dart SDK | All | 2.6k | Yes | Yes | Partial | Yes | Yes |
| SchildiChat | Same as Element | Same as Element | Web, Desktop, Android | 461 | Yes | Yes | Yes | Yes | Yes |
| Nheko | C++20/Qt | mtxclient | Desktop | 2.4k | No | Partial | Yes | Yes | Yes |
| Fractal | Rust/GTK4 | matrix-rust-sdk | Linux | -- | No | No | No | Yes | Yes |
| Hydrogen | TypeScript | Custom | Web (PWA) | 709 | No | No | No | Yes | Maintenance |
| NeoChat | C++/QML | libQuotient | Linux, Win, macOS, Android | -- | No | Yes | No | Experimental | Yes |
| Gomuks | Go | mautrix-go | Web, Terminal | 1.6k | No | Yes | No | Yes | Yes |
| Commet | Dart/Flutter | Matrix Dart SDK | Win, Linux, Android | 907 | Yes | Yes | Yes | Yes | Yes |
| Thunderbird | JavaScript | Custom | Win, macOS, Linux | -- | No | No | No | Yes | Low |

---

## Key Takeaways for Building a New Client

1. **matrix-rust-sdk is the clear SDK choice** for any new client. It's where Element is investing, has Sliding Sync, native OIDC, and Rust's performance/safety guarantees. It has bindings for Swift, Kotlin, WASM, and Go.

2. **The UX bar is simultaneously low and high.** Low because every existing client has serious UX gaps. High because users compare against Discord, Telegram, and iMessage -- not against other Matrix clients.

3. **Encryption UX is the #1 unsolved problem.** No client has made verification and key management invisible to users. This is where Signal excels and Matrix falls flat.

4. **Spaces need a Discord-like treatment.** Cinny's approach (categories/channels sidebar) is the most praised. Element's tab-based approach is universally disliked.

5. **Performance is non-negotiable.** Sliding Sync + Rust SDK eliminates the historical sync problem. A new client should never support the legacy sync API.

6. **Multi-account is table stakes** but almost no one does it well.

7. **The mobile gap is real.** Element X is the only serious option. FluffyChat is decent. There's room for a polished native mobile client.

Sources:
- [Element Web GitHub](https://github.com/element-hq/element-web)
- [Element X iOS GitHub](https://github.com/element-hq/element-x-ios)
- [Element X Android GitHub](https://github.com/element-hq/element-x-android)
- [Cinny GitHub](https://github.com/cinnyapp/cinny)
- [FluffyChat GitHub](https://github.com/krille-chan/fluffychat)
- [Nheko GitHub](https://github.com/Nheko-Reborn/nheko)
- [Fractal on Matrix.org](https://matrix.org/ecosystem/clients/fractal/)
- [Hydrogen GitHub](https://github.com/element-hq/hydrogen-web)
- [SchildiChat Desktop GitHub](https://github.com/SchildiChat/schildichat-desktop)
- [Gomuks GitHub](https://github.com/gomuks/gomuks)
- [Commet GitHub](https://github.com/commetchat/commet)
- [NeoChat on KDE](https://apps.kde.org/neochat/)
- [Matrix 2.0 Announcement](https://matrix.org/blog/2023/09/matrix-2-0/)
- [Sliding Sync Native Support](https://matrix.org/blog/2024/11/14/moving-to-native-sliding-sync/)
- [Element X Ignition Blog](https://element.io/blog/element-x-ignition/)
- [Matrix Client Comparison - Matrix Docs](https://matrixdocs.github.io/docs/clients/comparison)
- [Matrix Clients Pros and Cons Gist](https://gist.github.com/FireMario211/1bdbee07a5d56dc27891ae0c362d1e3d)
- [Element Web DeepWiki](https://deepwiki.com/element-hq/element-web)
- [Cinny DeepWiki](https://deepwiki.com/cinnyapp/cinny)
- [Thunderbird Matrix Chat FAQ](https://support.mozilla.org/en-US/kb/thunderbird-matrix-chat-faq)
- [HN: Matrix UX Discussion](https://news.ycombinator.com/item?id=44617830)
- [HN: Why Not Matrix](https://news.ycombinator.com/item?id=44714994)
- [Element X Feature Parity Discussion](https://biggo.com/news/202510211954_Element-X-Feature-Parity-Performance-Debate)
- [Unable to Decrypt Guide](https://joinmatrix.org/guide/fix-decryption-error/)
- [NeoChat E2EE Blog](https://tobiasfella.de/blog/neochat-e2ee/)
- [Matrix Conference 2024: UTD Talk](https://cfp.matrix.org/matrixconf2024/talk/8BVVT3/)
- [Commet DeepWiki](https://deepwiki.com/commetchat/commet)
