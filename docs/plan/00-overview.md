# Gloam — Implementation Plan Overview

**Project:** Gloam — A Matrix chat client
**Domain:** gloam.chat
**Tagline:** *tune in to the conversation*
**Date:** 2026-03-25

---

## Vision

A Matrix chat client that people choose because it's the best chat app they've ever used — not because it's federated or encrypted. Federation and encryption are implementation details that should be invisible to users. Gloam exists in the twilight between the polished UX of Slack/Discord and the sovereignty of Matrix — a liminal space where you don't have to compromise.

---

## Design Principles

| # | Principle | What It Means in Practice |
|---|-----------|--------------------------|
| 1 | **Speed is a feature** | Every interaction feels instant. Optimistic UI everywhere. Pre-fetch aggressively. Never show a loading spinner for navigation. |
| 2 | **Encryption is invisible** | Users never see "Unable to Decrypt," manage keys manually, or understand cross-signing. It just works, like Signal. |
| 3 | **Opinionated defaults, power-user depth** | Sensible defaults for 95% of users. Advanced options exist but don't clutter the primary experience. |
| 4 | **Platform-adaptive, not platform-imitative** | One distinctive design language that adapts to platform conventions (scroll physics, menu bars, shortcuts) without cloning the native OS. |
| 5 | **Information density matters** | Chat is high-throughput. Don't waste space with excessive padding or oversized elements. Dense but readable. |

---

## Target Users

**Primary:** Teams and communities currently using Discord or Slack who want ownership of their data, self-hosting capability, or freedom from vendor lock-in — but won't sacrifice UX quality to get it.

**Secondary:** Privacy-conscious users currently on Signal or Telegram who want richer community features (spaces, channels, bots) without giving up E2EE.

---

## Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI Framework | **Flutter 3.x** | Single codebase for all 5 platforms with total pixel control — chat apps are mostly custom UI anyway |
| Language | **Dart** | Flutter's language; strong async support, sound null safety |
| Matrix SDK | **matrix_dart_sdk v1.0.0** | Native Dart API with no FFI bridging complexity; production-proven by FluffyChat |
| E2EE | **vodozemac (via flutter_vodozemac)** | Rust-based Signal-grade crypto exposed through Dart FFI — the crypto layer is Rust even if the app is Dart |
| State Management | **Riverpod** | Compile-safe, testable, code-generated providers; cleaner dependency injection than Bloc |
| Local Database | **drift (SQLite)** | Type-safe reactive queries with migrations; consistent across all platforms including web (sql.js/WASM) |
| Navigation | **go_router** | Declarative routing with deep-link support and platform-adaptive transitions |
| Networking | **dio** | Connection management, retries, interceptors — supplements matrix_dart_sdk's built-in HTTP |
| Key Storage | **flutter_secure_storage** | Platform keychain abstraction (Keychain on Apple, KeyStore on Android, libsecret on Linux) |
| Search Index | **SQLite FTS5** | Client-side full-text search for encrypted rooms; encrypted at rest via SQLCipher |
| Push (iOS) | **APNs via sygnal** | Matrix standard push gateway model |
| Push (Android) | **FCM + UnifiedPush** | FCM primary; UnifiedPush for de-Googled devices |
| Media | **cached_network_image + custom MXC resolver** | LRU disk cache with encrypted media support |
| CI/CD | **GitHub Actions + Fastlane** | Automated builds, tests, and store submissions for all 5 platforms |
| Testing | **flutter_test + integration_test + mockito** | Unit, widget, and integration test layers |

---

## Phase Overview

| Phase | Name | Weeks | Duration | Milestone | Plan File |
|-------|------|-------|----------|-----------|-----------|
| 0 | Foundation | 1–4 | 4 weeks | Log into a Matrix account and see a room list | [01-phase0-foundation.md](./01-phase0-foundation.md) |
| 1 | Core Messaging | 5–10 | 6 weeks | Full encrypted conversation with all basic messaging features | [02-phase1-core-messaging.md](./02-phase1-core-messaging.md) |
| 2 | Navigation & Organization | 11–14 | 4 weeks | Full navigation model; usable as daily driver for text chat | [03-phase2-navigation.md](./03-phase2-navigation.md) |
| 3 | Search & Media | 15–18 | 4 weeks | Reliable encrypted search; rich media experience | [04-phase3-search-media.md](./04-phase3-search-media.md) |
| 4 | Platform Polish | 19–22 | 4 weeks | Feels like a thoughtful native app on each platform | [05-phase4-platform-polish.md](./05-phase4-platform-polish.md) |
| 5 | Voice/Video & Advanced | 23–28 | 6 weeks | Feature parity with Element X plus voice channels and moderation | [06-phase5-voice-advanced.md](./06-phase5-voice-advanced.md) |
| 6 | Public Beta | 29–32 | 4 weeks | Public beta launch on all 5 platforms | [07-phase6-beta.md](./07-phase6-beta.md) |

**Total timeline:** 32 weeks (~8 months)

---

## Performance Targets

| Metric | Target | Rationale |
|--------|--------|-----------|
| App cold start to room list visible | < 1.5s | Sliding Sync + cached SQLite state makes this achievable |
| Room switch to messages visible | < 200ms | Local event cache + pre-fetching adjacent rooms |
| Message send to visible in timeline | < 100ms | Optimistic UI — local echo renders before server confirmation |
| Search results appear | < 500ms | FTS5 local index; no server round-trip for encrypted rooms |
| Push notification to message visible | < 2s | Notification extension decrypts inline; app loads directly to event |
| Memory usage (idle, 50 rooms) | < 200MB | Aggressive widget recycling, timeline virtualization |
| Memory usage (active, 500 rooms) | < 400MB | Sliding Sync windows + LRU media cache eviction |
| App binary size | < 50MB | Tree-shaking, deferred loading, asset compression |

---

## Document Map

### Planning Documents

| # | File | Contents |
|---|------|----------|
| 00 | [00-overview.md](./00-overview.md) | This file — project overview, stack, phases, decisions |
| 01 | [01-phase0-foundation.md](./01-phase0-foundation.md) | Phase 0: Foundation (Weeks 1–4) |
| 02 | [02-phase1-core-messaging.md](./02-phase1-core-messaging.md) | Phase 1: Core Messaging (Weeks 5–10) |
| 03 | [03-phase2-navigation.md](./03-phase2-navigation.md) | Phase 2: Navigation & Organization (Weeks 11–14) |
| 04 | [04-phase3-search-media.md](./04-phase3-search-media.md) | Phase 3: Search & Media (Weeks 15–18) |
| 05 | [05-phase4-platform-polish.md](./05-phase4-platform-polish.md) | Phase 4: Platform Polish (Weeks 19–22) |
| 06 | [06-phase5-voice-advanced.md](./06-phase5-voice-advanced.md) | Phase 5: Voice/Video & Advanced (Weeks 23–28) |
| 07 | [07-phase6-beta.md](./07-phase6-beta.md) | Phase 6: Public Beta (Weeks 29–32) |

### Reference Documents

| # | File | Contents |
|---|------|----------|
| 08 | [08-architecture.md](./08-architecture.md) | Technical architecture, layer diagram, service interfaces, data flow, E2EE, performance |
| 09 | [09-design-system.md](./09-design-system.md) | Brand identity, color tokens, typography, spacing, component specs, responsive breakpoints |
| 10 | [10-infrastructure.md](./10-infrastructure.md) | CI/CD pipeline, push notifications, hosting, app stores, code signing, monitoring |

### Project-Level Reference

| File | Contents |
|------|----------|
| [COMPETITIVE_ANALYSIS.md](../../COMPETITIVE_ANALYSIS.md) | Full competitive analysis, product spec, and technical proposal |
| [BRANDING.md](../../BRANDING.md) | Name research, availability, aesthetic direction |

---

## Decision Log

| Decision | Chosen | Over | Rationale |
|----------|--------|------|-----------|
| **UI Framework** | Flutter | React Native, Tauri + Web, KMP + Compose, Native per-platform | Single codebase covering all 5 platforms with stable support. Total pixel control aligns with distinctive design goal. Highest small-team feasibility. Chat apps are mostly custom UI — native widgets are a small fraction. |
| **Matrix SDK** | matrix_dart_sdk | matrix-rust-sdk via FFI | Native Dart API eliminates FFI bridging complexity and debugging. v1.0.0 with vodozemac means the crypto layer IS Rust. FluffyChat validates production viability. If Rust SDK Dart bindings mature, the service layer abstraction allows migration. |
| **State Management** | Riverpod | Bloc, Provider, GetX | Compile-safe with code generation. Better dependency injection model. More testable — providers are pure functions. Bloc adds boilerplate (events + states + bloc classes) that Riverpod avoids while maintaining the same separation of concerns. |
| **Sync Strategy** | Sliding Sync (mandatory) | Sync v2 with optimization | Sliding Sync is O(1) regardless of room count vs. O(N) for sync v2. Native in Synapse, enabled by default. This is the single biggest performance lever — the difference between a 1-second and a 10-minute first load. Sync v2 fallback exists but with a server upgrade warning. |
| **Visual Design** | Dark-mode-first | Light-mode-first, system-follows | Aligns with Gloam's brand identity (twilight, liminal, atmospheric). The target audience (Discord/Slack power users, privacy-conscious) skews heavily toward dark mode. Light mode is available but not the default experience. |

---

## Risk Register

| # | Risk | Severity | Likelihood | Impact | Mitigation |
|---|------|----------|------------|--------|------------|
| 1 | **E2EE "Unable to Decrypt" elimination** | **Critical** | High | Users abandon the app if messages can't be read | Aggressive key backup + request strategies. Pre-fetch keys for rooms before opening. Automatic backup restore on missing keys. Graceful degradation message instead of error. Budget 2x estimated time for crypto work. |
| 2 | **Single-developer velocity** | **High** | High | Scope creep, burnout, missed milestones | Phase ruthlessly. Ship a great messaging core (Phases 0–1) before expanding. Each phase has a concrete "done" definition. Cut scope from later phases before slipping earlier ones. |
| 3 | **matrix_dart_sdk feature gaps vs. Rust SDK** | **Medium** | Medium | Missing SDK features block planned app features | Service layer abstraction allows SDK swap. Monitor Rust SDK Dart bindings maturity (currently experimental). Contribute upstream fixes. Maintain a running list of SDK gaps and workarounds. |
| 4 | **Flutter desktop UX ceiling** | **Medium** | Medium | Desktop app feels like a mobile app on a big screen | Invest early in platform-adaptive layer (Phase 0). Use PlatformMenuBar, native scroll physics, keyboard shortcut system. Test on real desktop hardware weekly. Density modes from day one. |
| 5 | **Push notification reliability** | **Medium** | Medium | Users miss messages, lose trust in the app | Implement sygnal integration early (Phase 2). Test on real devices across carriers. Encrypted notification content decrypted in notification extension. UnifiedPush for de-Googled Android. |

### Secondary Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Sliding Sync homeserver adoption gaps | Low | Most active homeservers (Synapse) support it natively. Fallback to sync v2 with warning. |
| Flutter web performance for desktop | Low | Target native desktop builds. Web is a bonus deployment, not the primary desktop experience. |
| vodozemac security vulnerabilities | Medium | Pin versions, monitor CVE advisories (CVE-2025-48937 already patched). Security audit budgeted in Phase 6. |
| App store review rejection | Low | No novel policy issues — encrypted messaging apps are established category. Budget time for review cycles. |
| Matrix spec changes during development | Low | Build against stable spec (v1.17). MSC features (MatrixRTC, OIDC) are production-proven in Element X. |
