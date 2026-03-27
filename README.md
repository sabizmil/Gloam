# gloam

*tune in to the conversation*

A Matrix chat client that refuses to compromise. Slack-grade experience. Signal-grade encryption. Your server. Your data. No asterisks.

---

Gloam is a cross-platform Matrix chat client designed for teams and communities who expect more from their tools. It delivers the speed, density, and interaction quality of Slack or Discord — threaded conversations, persistent voice channels, rich media, instant search — while running on infrastructure you own. End-to-end encryption is invisible. Federation is seamless. Nothing is phoned home.

## Features

- **Spaces & channels** with familiar room organization
- **Persistent voice channels** — drop in, drop out, no ringing
- **End-to-end encryption** that never asks you to think about it
- **Full-text search** across encrypted rooms
- **Rich composer** with reactions, markdown, link previews, media
- **Per-room notification control** with mentions-only and mute
- **User profiles** with DM initiation and mutual room discovery
- **Explore browser** for discovering public rooms across the federation
- **Cross-platform** — macOS, Windows, iOS, Android, Linux

## Download

Grab the latest release from [GitHub Releases](https://github.com/sabizmil/Gloam/releases).

**macOS:** Download the `.zip`, extract, move to Applications.
**Windows:** Download the `.zip`, extract, run `gloam.exe`.

Updates are delivered automatically after first install.

## Building from Source

Requires [Flutter](https://flutter.dev) 3.41+ and [FVM](https://fvm.app).

```bash
git clone https://github.com/sabizmil/Gloam.git
cd Gloam
fvm flutter pub get
fvm flutter build macos --release   # or: windows, linux, ios, android
```

macOS builds require [libolm](https://gitlab.matrix.org/matrix-org/olm) — install via `brew install libolm`.

## Stack

- **Framework:** Flutter / Dart
- **Matrix SDK:** [matrix](https://pub.dev/packages/matrix) (Dart native)
- **Encryption:** flutter_olm (Olm/Megolm)
- **Voice:** LiveKit via MatrixRTC
- **State:** Riverpod
- **Database:** drift (SQLite)
- **Typography:** Spectral · Inter · JetBrains Mono

## Connect

Gloam works with any Matrix homeserver — [matrix.org](https://matrix.org), your own [Synapse](https://github.com/element-hq/synapse) instance, [Conduit](https://conduit.rs), or anything else that speaks the protocol.

---

Gloam is a [Liminal Studio](https://liminal.studio) product.
