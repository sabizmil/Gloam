# Voice Support — Implementation Plan Overview

*Created: 2026-03-26*

This is the master plan for implementing voice support in Gloam, broken into four focused phases. Each phase ships a usable increment. The primary protocol is MatrixRTC + LiveKit; the abstraction layer ensures future protocols (Mumble, Jitsi) can plug in without UI rework.

---

## Document Map

| Doc | Phase | Duration | Milestone |
|-----|-------|----------|-----------|
| [Phase 5A](phase-5a-voice-foundation.md) | Abstraction Layer + MatrixRTC Foundation | Weeks 1–3 | Join a voice channel and hear other people talk |
| [Phase 5B](phase-5b-voice-channels.md) | Voice Channels + Persistent Bar | Weeks 4–6 | Full Discord-like voice channel UX with ambient join/leave |
| [Phase 5C](phase-5c-dm-calls.md) | DM Calls + Mobile Integration | Weeks 7–9 | Ring-to-answer calls from DMs with CallKit/Android integration |
| [Phase 5D](phase-5d-video-screenshare-polish.md) | Video, Screen Share + Polish | Weeks 10–12 | Video calls, screen sharing, voice settings, production-ready |

## Companion Documents

| Doc | Purpose |
|-----|---------|
| [PRD](PRD.md) | Feature specification, UX wireframes, success criteria |
| [Discord Voice Research](discord-voice-research.md) | Competitive feature reference |
| [Element Call / MatrixRTC Research](element-call-research.md) | Primary protocol technical details |
| [Mumble/TeamSpeak Research](mumble-teamspeak-research.md) | Future protocol research |
| [Multi-Protocol Architecture](multi-protocol-architecture.md) | Abstraction layer design, future-proofing guidance |

## Relationship to Existing Phase 5

The existing `docs/plan/06-phase5-voice-video-advanced.md` covers voice alongside custom emoji, sticker packs, GIF picker, space-wide moderation, and multi-account. These focused plans **replace the voice sections** of that document with deeper, implementation-ready detail. The non-voice features (emoji, moderation, multi-account) remain as planned in 06.

## New Dependencies (All Phases)

| Package | Version | Purpose | Phase Introduced |
|---------|---------|---------|-----------------|
| `livekit_client` | latest | LiveKit Flutter SDK — SFU connection, media tracks | 5A |
| `flutter_webrtc` | latest | WebRTC for Flutter — peer connections, screen capture | 5A |
| `permission_handler` | latest | Camera/mic permissions (cross-platform) | 5A |
| `wakelock_plus` | latest | Prevent screen dimming during calls | 5C |
| `flutter_callkit_incoming` | latest | iOS CallKit + Android full-screen call notification | 5C |

## Architecture Summary

```
┌──────────────────────────────────────────────────────────────┐
│                     PROTOCOL-AGNOSTIC                        │
│                                                              │
│  lib/features/calls/presentation/    Voice UI (all screens)  │
│  lib/features/calls/domain/          Entities & interfaces   │
│  lib/services/voice_service.dart     Global Riverpod state   │
│  lib/services/audio_device_service.dart  Device management   │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                     ADAPTER LAYER                            │
│                                                              │
│  lib/features/calls/data/adapters/   Protocol implementations│
│    matrix_rtc_adapter.dart           MatrixRTC + LiveKit     │
│    (mumble_adapter.dart)             Future: Mumble          │
│    (jitsi_adapter.dart)              Future: Jitsi           │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                     PLATFORM LAYER                           │
│                                                              │
│  ios/    CallKit, AVAudioSession, PiP, permissions           │
│  android/  ConnectionService, foreground service, permissions│
│  macos/  Audio device management, entitlements               │
└──────────────────────────────────────────────────────────────┘
```

## Key File Layout (Final State)

```
lib/
├── features/calls/
│   ├── domain/
│   │   ├── voice_protocol_adapter.dart      # Abstract adapter interface
│   │   ├── voice_channel.dart               # Channel entity
│   │   ├── voice_participant.dart           # Participant entity
│   │   ├── voice_permissions.dart           # Normalized permissions
│   │   ├── voice_capabilities.dart          # Protocol feature flags
│   │   ├── voice_server_config.dart         # Sealed server config
│   │   └── voice_connection_state.dart      # Connection state machine
│   ├── data/
│   │   ├── adapters/
│   │   │   └── matrix_rtc_adapter.dart      # MatrixRTC + LiveKit impl
│   │   ├── matrix_rtc_signaling.dart        # m.rtc.member event handling
│   │   ├── livekit_media_manager.dart       # LiveKit room + tracks
│   │   └── sfu_discovery_service.dart       # .well-known + JWT exchange
│   └── presentation/
│       ├── providers/
│       │   ├── voice_provider.dart          # Global voice state (Riverpod)
│       │   └── call_provider.dart           # DM call state (ringing/active)
│       ├── screens/
│       │   ├── voice_channel_screen.dart    # Participant grid + text-in-voice
│       │   ├── active_call_screen.dart      # DM active call (voice + video)
│       │   └── incoming_call_screen.dart    # Incoming call overlay
│       └── widgets/
│           ├── persistent_voice_bar.dart    # Bottom bar (all routes)
│           ├── participant_tile.dart        # Single participant card
│           ├── participant_grid.dart        # Grid layout for tiles
│           ├── call_controls.dart           # Mute/deafen/end/video buttons
│           ├── voice_channel_sidebar.dart   # Voice channels in room list
│           └── connection_quality.dart      # Green/yellow/red indicator
├── services/
│   ├── voice_service.dart                   # Global voice state provider
│   └── audio_device_service.dart            # Shared audio device management
└── ...
```
