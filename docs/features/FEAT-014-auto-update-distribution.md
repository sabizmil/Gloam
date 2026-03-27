# FEAT-014: Auto-Updating Distribution for macOS & Windows

**Requested:** 2026-03-27
**Status:** Proposed
**Priority:** P0
**Effort:** Medium (4-5 days)

---

## Goal

Ship Gloam as a self-updating desktop app on macOS and Windows. Friends install it once, and every subsequent release propagates automatically without reinstallation.

---

## Architecture: GitHub Releases + Sparkle/WinSparkle

The simplest approach that doesn't require infrastructure:

1. **You push a tag** (`v0.2.0`) to GitHub
2. **GitHub Actions** builds macOS .dmg + Windows .exe installer
3. **Artifacts are uploaded** to a GitHub Release
4. **The app checks for updates** on launch + every 4 hours by querying an appcast feed (XML for macOS, JSON for Windows) hosted on GitHub Pages or the release itself
5. **User sees a prompt**: "Gloam v0.2.0 is available — Update now?"
6. **App downloads and applies** the update (Sparkle on macOS, WinSparkle on Windows)

No server infrastructure. No App Store review. No manual reinstallation.

---

## macOS: Sparkle Framework

### How It Works

[Sparkle](https://sparkle-project.org/) is the standard auto-update framework for macOS apps distributed outside the App Store. Flutter integration via the `auto_updater` package (wraps Sparkle 2.x).

**Update flow:**
1. App launches → checks `appcast.xml` URL for new versions
2. Compares current version with feed entries
3. If newer version exists → shows native macOS update dialog
4. User clicks "Install Update" → downloads .dmg/.zip in background
5. Sparkle extracts, verifies ed25519 signature, replaces app bundle
6. App relaunches with new version

### Requirements

- **Developer ID Application certificate** — for signing (you have Apple Developer account, team 9PBKL722LG)
- **ed25519 key pair** — for signing updates (Sparkle verifies these, separate from Apple codesign)
- **Notarization** — required for Gatekeeper on recipients' machines
- **appcast.xml** — hosted on GitHub Pages or raw in the repo

### Implementation

#### 1. Add `auto_updater` dependency

```yaml
# pubspec.yaml
dependencies:
  auto_updater: ^0.2.0
```

#### 2. Generate Sparkle ed25519 key pair

```bash
# One-time setup — generates private + public key
# Store private key SECURELY (GitHub secret, never commit)
./Pods/Sparkle/bin/generate_keys
```

This outputs:
- Private key → store as `SPARKLE_PRIVATE_KEY` GitHub secret
- Public key → embed in `Info.plist` as `SUPublicEDKey`

#### 3. Configure Info.plist

```xml
<!-- macOS Info.plist additions -->
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>YOUR_ED25519_PUBLIC_KEY</string>
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUAutomaticallyUpdate</key>
<false/>  <!-- Show dialog, don't silently update -->
<key>SUScheduledCheckInterval</key>
<integer>14400</integer>  <!-- Check every 4 hours (seconds) -->
```

#### 4. Initialize in app

```dart
// In _AuthenticatedHomeState.initState()
if (Platform.isMacOS) {
  final autoUpdater = AutoUpdater.instance;
  await autoUpdater.setFeedURL(
    'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast.xml');
  await autoUpdater.checkForUpdates(inBackground: true);
}
```

#### 5. appcast.xml format

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Gloam Updates</title>
    <item>
      <title>Version 0.2.0</title>
      <sparkle:version>2</sparkle:version>
      <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>What's new in Gloam 0.2.0</h2>
        <ul>
          <li>Voice channels with LiveKit integration</li>
          <li>User profile modals</li>
          <li>Explore room browser</li>
        </ul>
      ]]></description>
      <pubDate>Thu, 27 Mar 2026 12:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/sabizmil/Gloam/releases/download/v0.2.0/Gloam-0.2.0-macos.dmg"
        sparkle:edSignature="SIGNATURE_HERE"
        length="45000000"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

The signature is generated during the CI build:
```bash
./Pods/Sparkle/bin/sign_update Gloam.dmg --ed-key-file sparkle_private_key
```

---

## Windows: WinSparkle

### How It Works

[WinSparkle](https://winsparkle.org/) is the Windows equivalent of Sparkle. Same concept — checks an appcast, downloads updates, applies them. The `auto_updater` Flutter package wraps both Sparkle and WinSparkle.

**Update flow:**
1. App launches → checks appcast URL
2. If newer version → shows Windows-native update dialog
3. User clicks "Install" → downloads .exe installer
4. WinSparkle runs the installer silently, app relaunches

### Requirements

- **Code signing certificate** — optional but strongly recommended (prevents SmartScreen warnings)
  - Cheapest option: Azure Trusted Signing ($9.99/month, cloud HSM)
  - Alternative: Standard OV cert (~$200-400/year from Sectigo/DigiCert)
  - Without signing: first-time users see "Windows protected your PC" SmartScreen warning — they can click through but it's not great
- **Inno Setup** — for creating the .exe installer that WinSparkle downloads
- **appcast_windows.xml** — separate feed (different download URLs and signatures)

### Implementation

#### 1. Same `auto_updater` package (cross-platform)

#### 2. Configure in app

```dart
if (Platform.isWindows) {
  final autoUpdater = AutoUpdater.instance;
  await autoUpdater.setFeedURL(
    'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast_windows.xml');
  await autoUpdater.checkForUpdates(inBackground: true);
}
```

#### 3. Windows appcast

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Gloam Updates</title>
    <item>
      <title>Version 0.2.0</title>
      <sparkle:version>0.2.0</sparkle:version>
      <enclosure
        url="https://github.com/sabizmil/Gloam/releases/download/v0.2.0/Gloam-0.2.0-windows-setup.exe"
        length="50000000"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

#### 4. Inno Setup installer script

**New file:** `scripts/windows_installer.iss`

```iss
[Setup]
AppName=Gloam
AppVersion={#AppVersion}
DefaultDirName={autopf}\Gloam
DefaultGroupName=Gloam
OutputBaseFilename=Gloam-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\gloam.exe
PrivilegesRequired=lowest

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{group}\Gloam"; Filename: "{app}\gloam.exe"
Name: "{autodesktop}\Gloam"; Filename: "{app}\gloam.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\gloam.exe"; Description: "Launch Gloam"; Flags: nowait postinstall skipifsilent
```

---

## CI/CD: GitHub Actions

### Workflow

**New file:** `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  build-macos:
    runs-on: macos-14  # Apple Silicon
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Install CocoaPods
        run: cd macos && pod install

      - name: Build macOS release
        run: flutter build macos --release

      - name: Bundle native libs + sign
        env:
          APPLE_CERT_P12: ${{ secrets.APPLE_CERT_P12 }}
          APPLE_CERT_PASSWORD: ${{ secrets.APPLE_CERT_PASSWORD }}
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
        run: bash scripts/release_macos.sh

      - name: Sign Sparkle update
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          echo "$SPARKLE_PRIVATE_KEY" > /tmp/sparkle_key
          SIGNATURE=$(./Pods/Sparkle/bin/sign_update build/Gloam.dmg --ed-key-file /tmp/sparkle_key)
          echo "SPARKLE_SIG=$SIGNATURE" >> $GITHUB_ENV
          rm /tmp/sparkle_key

      - name: Upload macOS DMG
        uses: softprops/action-gh-release@v2
        with:
          files: build/Gloam-*-macos.dmg

  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Build Windows release
        run: flutter build windows --release

      - name: Create installer
        run: |
          choco install innosetup -y
          iscc /DAppVersion=${{ github.ref_name }} scripts/windows_installer.iss

      - name: Upload Windows installer
        uses: softprops/action-gh-release@v2
        with:
          files: Output/Gloam-*-windows-setup.exe

  update-appcast:
    needs: [build-macos, build-windows]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Update appcast files
        run: |
          # Script to update appcast.xml and appcast_windows.xml
          # with new version, download URLs, signatures, and dates
          python3 scripts/update_appcast.py \
            --version "${{ github.ref_name }}" \
            --mac-sig "${{ needs.build-macos.outputs.sparkle_sig }}" \
            --mac-url "https://github.com/sabizmil/Gloam/releases/download/${{ github.ref_name }}/Gloam-${{ github.ref_name }}-macos.dmg" \
            --win-url "https://github.com/sabizmil/Gloam/releases/download/${{ github.ref_name }}/Gloam-${{ github.ref_name }}-windows-setup.exe"

      - name: Commit updated appcast
        run: |
          git config user.name "github-actions"
          git config user.email "actions@github.com"
          git add appcast.xml appcast_windows.xml
          git commit -m "Update appcast for ${{ github.ref_name }}"
          git push
```

### Release Process (Your Workflow)

```bash
# 1. Bump version in pubspec.yaml
#    version: 0.2.0+2

# 2. Commit
git add pubspec.yaml
git commit -m "Bump version to 0.2.0"

# 3. Tag and push
git tag v0.2.0
git push && git push --tags

# 4. GitHub Actions builds macOS + Windows, creates GitHub Release,
#    uploads artifacts, updates appcast, and your friends' apps
#    automatically prompt them to update.
```

---

## First-Time Installation

### macOS

Your friends:
1. Download `Gloam-0.2.0-macos.dmg` from GitHub Releases
2. Open the DMG, drag Gloam to Applications
3. First launch: right-click → Open → confirm (bypasses Gatekeeper for unsigned or dev-signed apps)
4. Once notarized: double-click works directly

### Windows

Your friends:
1. Download `Gloam-0.2.0-windows-setup.exe` from GitHub Releases
2. Run the installer (SmartScreen warning if unsigned — click "More info" → "Run anyway")
3. Gloam installs to Program Files and creates Start Menu + Desktop shortcuts
4. Once signed with Azure Trusted Signing: no SmartScreen warning

### After First Install

Updates are automatic. On launch, Gloam checks the appcast feed. If a new version exists:
- **macOS**: Native Sparkle dialog — "A new version of Gloam is available! Version 0.3.0 is now available — you have 0.2.0. Would you like to update now?"
- **Windows**: Similar WinSparkle dialog — "Install Update" / "Remind Me Later" / "Skip This Version"

---

## Implementation Tasks

| Task | Days | Description |
|------|------|-------------|
| 1. Add `auto_updater` + configure | 0.5 | pubspec, Info.plist, init code |
| 2. Generate Sparkle ed25519 keys | 0.5 | One-time setup, store in GitHub secrets |
| 3. Create `scripts/release_macos.sh` | 0.5 | Build, sign with Developer ID, create DMG, notarize, staple |
| 4. Create `scripts/windows_installer.iss` | 0.5 | Inno Setup script for Windows installer |
| 5. Create GitHub Actions workflow | 1.0 | CI/CD for both platforms |
| 6. Create appcast files + update script | 0.5 | XML feeds + Python script to update on release |
| 7. Test end-to-end on both platforms | 1.0 | Build, install, trigger update, verify |
| **Total** | **4.5** | |

## Prerequisites (Things You Need to Do)

1. **Apple Developer ID Application certificate** — go to developer.apple.com → Certificates → create "Developer ID Application" cert. Export as .p12. Store as GitHub secret.
2. **App-specific password** for notarization — appleid.apple.com → Security → App-Specific Passwords. Store as GitHub secret.
3. **(Optional) Windows code signing** — Azure Trusted Signing ($9.99/month) or skip for now (SmartScreen warning is tolerable for friends-only distribution).
4. **Inno Setup** — install on Windows runner (CI handles this) or test locally.

## Secrets to Configure in GitHub

| Secret | Purpose |
|--------|---------|
| `APPLE_CERT_P12` | Base64-encoded Developer ID Application cert |
| `APPLE_CERT_PASSWORD` | Password for the .p12 |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_TEAM_ID` | `9PBKL722LG` |
| `APPLE_APP_PASSWORD` | App-specific password for notarytool |
| `SPARKLE_PRIVATE_KEY` | ed25519 private key for signing updates |
| `WINDOWS_CERT_PFX` | (Optional) Windows signing cert |
| `WINDOWS_CERT_PASSWORD` | (Optional) cert password |

---

## What Your Friends Experience

**First time:** Download DMG/EXE from a link you share → install → done.

**Every update after that:**
1. They launch Gloam
2. Dialog appears: "Gloam 0.3.0 is available — you have 0.2.0"
3. They click "Install Update"
4. App downloads, updates, relaunches — 30 seconds
5. They're on the latest version

No manual downloads. No reinstallation. No checking for updates. It just works.

---

## Change History

- 2026-03-27: Initial plan for macOS + Windows auto-updating distribution via Sparkle/WinSparkle + GitHub Actions.
