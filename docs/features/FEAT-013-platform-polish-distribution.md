# FEAT-013: Platform Polish & Distribution Readiness

**Requested:** 2026-03-27
**Status:** Proposed
**Priority:** High
**Effort:** Large (2-3 weeks across all platforms)

---

## Current State

| Aspect | macOS | iOS | Android | Windows | Linux |
|--------|-------|-----|---------|---------|-------|
| Code Signing | Dev cert (ad-hoc) | Dev cert (auto) | **Not configured** | None | N/A |
| Entitlements | ✓ (sandbox, mic, cam, net) | **Missing entirely** | **Permissions missing** | N/A | N/A |
| Privacy Manifest | **Missing** | **Missing (rejection risk)** | N/A | N/A | N/A |
| App Icons | ✓ Gloam branded | ✓ Gloam branded | **Not verified** | **Not verified** | **Missing** |
| Menu Bar | ✓ XIB + Flutter PlatformMenuBar | N/A | N/A | **Not implemented** | **Not implemented** |
| Keyboard Shortcuts | 9 shortcuts (macOS-centric) | System only | None | **Missing Ctrl equivalents** | **Missing Ctrl equivalents** |
| Notifications | ✓ Local (flutter_local_notifications) | **No push (APNs)** | **No push (FCM)** | ✓ Local | ✓ Local |
| Installer/Package | ZIP (manual) | N/A (Store) | N/A (Store) | **None** | **None** |
| Notarization | **Not configured** | N/A | N/A | N/A | N/A |
| Auto-Update | **None** | Store-managed | Store-managed | **None** | **None** |
| CI/CD | **None** | **None** | **None** | **None** | **None** |
| Release-Ready | Beta | No | No | No | No |

---

## Existing Keyboard Shortcuts

| Action | macOS | Windows/Linux | Intent |
|--------|-------|---------------|--------|
| Quick Switcher | Cmd+K | Ctrl+K | `QuickSwitcherIntent` |
| New Room | Cmd+N | Ctrl+N | `NewRoomIntent` |
| Search in Room | Cmd+F | Ctrl+F | `SearchIntent` |
| Global Search | Cmd+Shift+F | Ctrl+Shift+F | `GlobalSearchIntent` |
| Preferences | Cmd+, | **None** | `PreferencesIntent` |
| Close Panel | Cmd+W / Esc | Ctrl+W / Esc | `ClosePanelIntent` |
| Navigate Back | Cmd+[ | **None** | `NavigateBackIntent` |
| Navigate Forward | Cmd+] | **None** | `NavigateForwardIntent` |
| Shortcut Help | Cmd+/ | Ctrl+/ | `ShortcutHelpIntent` |

**Gaps:** Preferences, Navigate Back/Forward have no Windows/Linux bindings. No voice shortcuts (mute/deafen toggle). No message shortcuts (Cmd+E for emoji, Cmd+Shift+M for mark read).

---

## Implementation Plan

### Phase A: Keyboard Shortcuts & Menu Polish (3-4 days)

#### Task A1: Complete Cross-Platform Shortcuts

**File:** `lib/app/shortcuts.dart`

Add missing Windows/Linux bindings and new shortcuts:

```
NEW SHORTCUTS:
| Action | macOS | Win/Linux | Intent |
|--------|-------|-----------|--------|
| Preferences | Cmd+, | Ctrl+, | PreferencesIntent (add Ctrl) |
| Nav Back | Cmd+[ | Alt+Left | NavigateBackIntent |
| Nav Forward | Cmd+] | Alt+Right | NavigateForwardIntent |
| Toggle Mute | Cmd+Shift+M | Ctrl+Shift+M | ToggleMuteIntent |
| Toggle Deafen | Cmd+Shift+D | Ctrl+Shift+D | ToggleDeafenIntent |
| Disconnect Voice | Cmd+Shift+E | Ctrl+Shift+E | DisconnectVoiceIntent |
| Mark Room Read | Cmd+Shift+R | Ctrl+Shift+R | MarkReadIntent |
| Emoji Picker | Cmd+E | Ctrl+E | EmojiPickerIntent |
| Reply to Last | Cmd+Shift+Up | Ctrl+Shift+Up | ReplyLastIntent |
```

**File:** `lib/app/shell/shortcut_help_overlay.dart`

Update the help overlay to show all shortcuts with platform-appropriate labels (⌘ on macOS, Ctrl on Win/Linux). Detect platform and render accordingly.

#### Task A2: macOS Menu Bar Enhancement

**File:** `lib/app/app.dart` (PlatformMenuBar)

Add missing menu items to match standard macOS app behavior:

```
Gloam menu: About | Preferences (Cmd+,) | --- | Quit
File menu: New Room (Cmd+N) | Close Panel (Cmd+W) | --- | Quit (Cmd+Q)
Edit menu: Undo | Redo | Cut | Copy | Paste | Select All | --- | Find (Cmd+F)
View menu: Toggle Full Screen | --- | Toggle Sidebar (Cmd+Shift+S)
Window menu: Minimize | Zoom | --- | Bring All to Front
Help menu: Keyboard Shortcuts (Cmd+/)
```

#### Task A3: Wire New Shortcut Actions

**File:** `lib/features/rooms/presentation/home_screen.dart`

Add action handlers for new intents:

```dart
ToggleMuteIntent: CallbackAction<ToggleMuteIntent>(
  onInvoke: (_) => ref.read(voiceServiceProvider.notifier).toggleMute(),
),
MarkReadIntent: CallbackAction<MarkReadIntent>(
  onInvoke: (_) {
    final roomId = ref.read(selectedRoomProvider);
    if (roomId != null) {
      final client = ref.read(matrixServiceProvider).client;
      client?.getRoomById(roomId)?.setReadMarker(
        client.getRoomById(roomId)!.lastEvent!.eventId);
    }
    return null;
  },
),
```

---

### Phase B: macOS Distribution (3-4 days)

#### Task B1: Notarization Pipeline

Create `scripts/release_macos.sh`:

```bash
#!/bin/bash
set -e

# Build release
fvm flutter build macos --release

APP="build/macos/Build/Products/Release/gloam.app"
SIGN_ID="Developer ID Application: Simon Abizmil (TEAM_ID)"
ENTITLEMENTS="macos/Runner/Release.entitlements"

# Bundle native libs
# ... (existing libolm/libcrypto bundling)

# Codesign with Developer ID (not ad-hoc)
codesign --force --deep --options runtime \
  --sign "$SIGN_ID" --entitlements "$ENTITLEMENTS" "$APP"

# Create DMG
hdiutil create -volname "Gloam" -srcfolder "$APP" \
  -ov -format UDZO "build/Gloam.dmg"
codesign --sign "$SIGN_ID" "build/Gloam.dmg"

# Notarize
xcrun notarytool submit "build/Gloam.dmg" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --wait

# Staple
xcrun stapler staple "build/Gloam.dmg"

echo "✓ Gloam.dmg ready for distribution"
```

#### Task B2: Fix Release Entitlements

**File:** `macos/Runner/Release.entitlements`

Add missing entitlements:
- `com.apple.security.network.server` — needed for WebRTC peer connections
- `com.apple.security.files.downloads.read-write` — for saving attachments

#### Task B3: Privacy Manifest

**New file:** `macos/Runner/PrivacyInfo.xcprivacy`

Declare required-reason API usage:
- `NSPrivacyAccessedAPICategoryUserDefaults` — flutter_secure_storage, shared_preferences
- `NSPrivacyAccessedAPICategoryFileTimestamp` — path_provider, file operations

#### Task B4: Universal Binary Verification

Verify bundled dylibs (libolm, libcrypto) are universal or arm64-only with Rosetta fallback documented.

---

### Phase C: iOS Distribution (3-4 days)

#### Task C1: Create iOS Entitlements

**New file:** `ios/Runner/Runner.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0">
<dict>
  <key>aps-environment</key>
  <string>development</string>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.chat.gloam</string>
  </array>
</dict>
</plist>
```

#### Task C2: iOS Info.plist Permissions

Add usage descriptions:
- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription`
- `UIBackgroundModes`: voip, remote-notification, audio
- `ITSAppUsesNonExemptEncryption`: YES (E2EE)

#### Task C3: iOS Privacy Manifest

**New file:** `ios/Runner/PrivacyInfo.xcprivacy`

Declare API usage and data collection. **Without this, App Store submission will be rejected.**

#### Task C4: Push Notifications (APNs)

- Create APNs auth key (.p8) in Apple Developer portal
- Set up Sygnal (Matrix push gateway) or Firebase as relay
- Register for remote notifications in AppDelegate
- Handle incoming push → show local notification

---

### Phase D: Android Distribution (2-3 days)

#### Task D1: Release Signing

**New file:** `android/key.properties` (gitignored)

```properties
storePassword=...
keyPassword=...
keyAlias=gloam
storeFile=../gloam-release.keystore
```

Update `android/app/build.gradle.kts` to use release signing config.

#### Task D2: Android Permissions

**File:** `android/app/src/main/AndroidManifest.xml`

Add all required permissions:
- INTERNET, CAMERA, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS
- READ_MEDIA_IMAGES, READ_MEDIA_VIDEO (API 33+)
- POST_NOTIFICATIONS (API 33+)
- FOREGROUND_SERVICE, FOREGROUND_SERVICE_PHONE_CALL
- VIBRATE, WAKE_LOCK, BLUETOOTH_CONNECT

#### Task D3: Adaptive Icons

Use `flutter_launcher_icons` to generate from 1024x1024 Gloam source:

```yaml
# pubspec.yaml
flutter_launcher_icons:
  android: true
  ios: false  # already done
  image_path: "assets/icon/gloam-icon-1024.png"
  adaptive_icon_background: "#080F0A"
  adaptive_icon_foreground: "assets/icon/gloam-icon-foreground.png"
```

#### Task D4: Play Store Metadata

Create `fastlane/` directory with screenshots, descriptions, changelogs for automated deployment.

---

### Phase E: Windows & Linux (2-3 days)

#### Task E1: Windows Installer

Add `msix` to dev_dependencies and configure:

```yaml
msix_config:
  display_name: Gloam
  publisher_display_name: Simon Abizmil
  identity_name: chat.gloam.gloam
  logo_path: windows/runner/resources/app_icon.ico
  capabilities: internetClient, microphone, webcam
```

Or use Inno Setup for traditional .exe installer.

#### Task E2: Windows Icon

Verify `windows/runner/resources/app_icon.ico` has Gloam branding with all required sizes (16, 32, 48, 256).

#### Task E3: Linux Packaging

Create Flatpak manifest or AppImage builder config. Create `.desktop` file:

```ini
[Desktop Entry]
Version=1.1
Type=Application
Name=Gloam
Comment=A Matrix chat client built for the twilight
Exec=gloam %u
Icon=gloam
Categories=Network;InstantMessaging;Chat;
MimeType=x-scheme-handler/matrix;
StartupWMClass=gloam
```

#### Task E4: Linux Icons

Provide PNG icons at 16, 32, 48, 64, 128, 256, 512px + SVG scalable.

---

### Phase F: CI/CD & Auto-Update (3-4 days)

#### Task F1: GitHub Actions Workflow

**New file:** `.github/workflows/release.yml`

Matrix strategy:
- `macos-14` (Apple Silicon) → macOS .dmg + iOS .ipa
- `ubuntu-latest` → Linux AppImage/Flatpak + Android .aab
- `windows-latest` → Windows .msix

Triggers: push to `main` (debug artifacts), tag `v*` (release builds).

Secrets: Apple certs, Android keystore, Windows cert, Sentry DSN.

#### Task F2: macOS Auto-Update

Add `auto_updater` package (wraps Sparkle):
- Host `appcast.xml` on GitHub Releases or gloam.chat
- Sign updates with ed25519 key
- Check for updates on launch + periodically

#### Task F3: Crash Reporting

Add `sentry_flutter` package:
- Configure DSN, environment, release version
- Upload debug symbols per release
- Opt-in consent dialog on first launch

---

## Priority Order

| Phase | What | Platform | Days | Prerequisite |
|-------|------|----------|------|-------------|
| **A** | Shortcuts + menus | All | 3-4 | None |
| **B** | macOS notarization + distribution | macOS | 3-4 | Apple Developer ID cert |
| **C** | iOS entitlements + push + privacy | iOS | 3-4 | Apple Developer account |
| **D** | Android signing + permissions + icons | Android | 2-3 | Google Play account + keystore |
| **E** | Windows installer + Linux packaging | Win/Linux | 2-3 | None |
| **F** | CI/CD + auto-update + crash reporting | All | 3-4 | All platforms configured |

**Recommended order:** A → B → D → C → E → F

Start with shortcuts (immediate UX win, no external dependencies), then macOS (your primary platform), then Android (widest reach), then iOS (App Store review takes time), then Win/Linux (smaller audience), then CI/CD (automates everything).

---

## Change History

- 2026-03-27: Initial comprehensive plan based on codebase audit and distribution research across all 5 platforms.
