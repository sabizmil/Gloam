# Gloam — Infrastructure & DevOps Plan

**Document:** 10-infrastructure.md
**Date:** 2026-03-25
**Status:** Planning

---

## 1. CI/CD Pipeline

### GitHub Actions Architecture

All CI runs on GitHub Actions. The repository uses a monorepo structure (single Flutter project, all platforms).

### Workflow Files

```
.github/
├── workflows/
│   ├── pr-checks.yml          # Runs on every PR
│   ├── build-release.yml      # Runs on version tags (v*)
│   ├── nightly.yml            # Scheduled nightly builds + device tests
│   └── deploy-sygnal.yml      # Sygnal push gateway deployment
├── actions/
│   ├── setup-flutter/         # Composite action: install Flutter, cache pub
│   └── setup-signing/         # Composite action: decode certs, configure signing
└── CODEOWNERS
```

### PR Checks (`pr-checks.yml`)

Triggered on every pull request and push to `main`.

```yaml
jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - flutter analyze (lint)
      - flutter format --set-exit-if-changed
      - dart run build_runner build (code gen up to date)
      - dart run custom_lint (riverpod lints)

  test-linux:
    runs-on: ubuntu-latest
    steps:
      - flutter test --coverage
      - Upload coverage to Codecov
      - Golden test comparison

  test-macos:
    runs-on: macos-14  # ARM runner
    steps:
      - flutter test
      - flutter build macos (build verification)

  test-windows:
    runs-on: windows-latest
    steps:
      - flutter test
      - flutter build windows (build verification)

  build-android:
    runs-on: ubuntu-latest
    steps:
      - flutter build apk --debug (build verification, no signing)

  build-ios:
    runs-on: macos-14
    steps:
      - flutter build ios --no-codesign (build verification)
```

**PR merge requirements:**
- All checks pass
- At least one approval (when team grows)
- No force-push to `main`

### Platform Build Matrix

| Platform | Runner | Build Command | Signing | Artifact |
|----------|--------|--------------|---------|----------|
| **iOS** | `macos-14` (M1) | `flutter build ipa` | Fastlane match (App Store) | `.ipa` |
| **Android** | `ubuntu-latest` | `flutter build appbundle` | Keystore (GitHub Secrets) | `.aab` |
| **macOS** | `macos-14` (M1) | `flutter build macos` | Developer ID + notarization | `.dmg` (via `create-dmg`) |
| **Windows** | `windows-latest` | `flutter build windows` | Code signing cert (SignTool) | `.msix` |
| **Linux** | `ubuntu-latest` | `flutter build linux` | N/A (Flatpak/Snap signing) | `.flatpak`, `.snap`, `.tar.gz` |

### Release Build (`build-release.yml`)

Triggered on version tags (`v*`).

```yaml
on:
  push:
    tags: ['v*']

jobs:
  build-ios:
    runs-on: macos-14
    steps:
      - Setup Flutter
      - Setup signing (Fastlane match)
      - flutter build ipa --release
      - fastlane ios beta  # Upload to TestFlight
      - Upload .ipa to GitHub Release

  build-android:
    runs-on: ubuntu-latest
    steps:
      - Setup Flutter
      - Decode keystore from GitHub Secrets
      - flutter build appbundle --release
      - fastlane android beta  # Upload to Play Console (internal track)
      - Upload .aab to GitHub Release

  build-macos:
    runs-on: macos-14
    steps:
      - Setup Flutter
      - Setup signing (Developer ID certificate)
      - flutter build macos --release
      - Notarize with `xcrun notarytool`
      - Package into .dmg with create-dmg
      - Upload .dmg to GitHub Release

  build-windows:
    runs-on: windows-latest
    steps:
      - Setup Flutter
      - flutter build windows --release
      - Sign with SignTool + code signing cert
      - Package as .msix
      - Upload to GitHub Release

  build-linux:
    runs-on: ubuntu-latest
    steps:
      - Setup Flutter
      - flutter build linux --release
      - Package as Flatpak (flatpak-builder)
      - Package as Snap (snapcraft)
      - Package as .tar.gz (portable)
      - Upload all to GitHub Release

  create-release:
    needs: [build-ios, build-android, build-macos, build-windows, build-linux]
    runs-on: ubuntu-latest
    steps:
      - Create GitHub Release with all artifacts
      - Generate changelog from commits since last tag
```

### Artifact Storage

| Artifact | Storage | Retention |
|----------|---------|-----------|
| PR build artifacts | GitHub Actions artifacts | 7 days |
| Release builds | GitHub Releases | Permanent |
| iOS builds | TestFlight | 90 days (Apple policy) |
| Android builds | Play Console internal track | Permanent |
| Crash symbols (dSYM, etc.) | Sentry | Per Sentry plan (90 days free) |

### Fastlane Configuration

```
fastlane/
├── Appfile              # App identifiers, team IDs
├── Fastfile             # Lane definitions
├── Matchfile            # Code signing config (match)
└── metadata/
    ├── ios/
    │   ├── en-US/
    │   │   ├── description.txt
    │   │   ├── keywords.txt
    │   │   └── release_notes.txt
    │   └── screenshots/
    └── android/
        ├── en-US/
        │   ├── full_description.txt
        │   ├── short_description.txt
        │   └── changelogs/
        └── images/
```

**Fastlane lanes:**
- `ios beta` — Build, sign, upload to TestFlight
- `ios release` — Build, sign, upload to App Store (manual release)
- `android beta` — Build, sign, upload to Play Console internal track
- `android release` — Promote from internal to production track
- `match` — Sync code signing certificates from private Git repo

---

## 2. Push Notification Infrastructure

### Architecture

```
┌─────────────┐     ┌─────────────┐     ┌───────────┐     ┌─────────┐
│  Homeserver  │────▶│   Sygnal    │────▶│ APNs/FCM  │────▶│ Device  │
│  (Synapse)   │     │(push gateway)│    │           │     │         │
└─────────────┘     └─────────────┘     └───────────┘     └─────────┘
                           │
                           │ UnifiedPush
                           ▼
                    ┌───────────┐
                    │ UP Distrib│────▶ Device (de-Googled)
                    └───────────┘
```

### Sygnal Deployment

**Sygnal** is the Matrix standard push gateway. It receives push notifications from the homeserver and forwards them to platform-specific push services.

| Property | Value |
|----------|-------|
| Image | `matrixdotorg/sygnal:latest` |
| Hosting | VPS (Hetzner, DigitalOcean) or container service (Fly.io, Railway) |
| Resources | 1 vCPU, 512MB RAM (lightweight Go service) |
| Database | PostgreSQL (notification tracking, push token storage) |
| TLS | Caddy reverse proxy or Cloudflare tunnel |
| Domain | `push.gloam.chat` |
| Monitoring | Health check endpoint + uptime monitoring |

**Sygnal configuration:**

```yaml
# sygnal.yaml
sygnal:
  ap:
    gloam_ios:
      type: apns
      keyfile: /etc/sygnal/apns_key.p8
      key_id: "ABCDE12345"
      team_id: "TEAM123456"
      topic: "chat.gloam.app"
    gloam_android:
      type: gcm
      api_key: "<FCM server key>"
```

### APNs Configuration (iOS / macOS)

| Item | Detail |
|------|--------|
| Certificate type | APNs Auth Key (`.p8`) — preferred over per-app certificates |
| Key ID | Registered in Apple Developer portal |
| Team ID | Apple Developer team identifier |
| Bundle ID / Topic | `chat.gloam.app` (iOS), `chat.gloam.app.macos` (macOS) |
| Environment | Sandbox (development) + Production |
| Notification Service Extension | `GloamNotificationService` — decrypts encrypted push payloads before display |
| Rich notifications | Sender avatar, room name, decrypted message preview |

**APNs key rotation:** Auth keys don't expire but should be rotated annually. Store in CI secrets and sygnal config. Old key remains valid during transition.

### FCM Configuration (Android)

| Item | Detail |
|------|--------|
| Project | Firebase project: `gloam-chat` |
| Server key | Legacy server key for sygnal (FCM v1 API migration planned) |
| google-services.json | Bundled in Android app at build time |
| Channel ID | `gloam_messages` — message notifications |
| Priority | High priority for message notifications (wakes device) |
| Data-only | Push payload is data-only (not notification) to allow client-side decryption before display |

### UnifiedPush Gateway

For de-Googled Android devices (GrapheneOS, LineageOS without GMS).

| Item | Detail |
|------|--------|
| Protocol | UnifiedPush (HTTP POST to distributor app) |
| Gateway | Sygnal acts as UnifiedPush gateway via UP-compatible endpoint |
| Distributor apps | ntfy, NextPush, Conversations (user installs one) |
| Registration | App detects UnifiedPush distributor at runtime; falls back to FCM if none found |
| Endpoint | User's UP distributor URL registered with sygnal |

### Push Notification Monitoring

| Metric | How | Alert Threshold |
|--------|-----|----------------|
| Push delivery latency | Sygnal logs → Grafana | > 5 seconds P95 |
| Push delivery failure rate | Sygnal error logs | > 5% per hour |
| APNs feedback | APNs feedback service | Any invalid token spike |
| FCM errors | FCM diagnostics API | Any quota or auth errors |
| Sygnal uptime | External health check (UptimeRobot) | Any downtime |

---

## 3. Homeserver Considerations

### Development Homeserver

A private Synapse instance for development and testing.

| Property | Value |
|----------|-------|
| Software | Synapse (latest stable) |
| Hosting | VPS (same as sygnal, or local Docker) |
| Domain | `dev.gloam.chat` |
| Sliding Sync | Enabled (native in Synapse, default on) |
| OIDC | MAS (Matrix Authentication Service) for testing OIDC flows |
| Media | Local storage (dev) or S3-compatible (staging) |
| Federation | Enabled (for testing federation edge cases) |
| Users | Test accounts for each platform + bot accounts for load testing |

**Docker Compose setup:**

```yaml
services:
  synapse:
    image: matrixdotorg/synapse:latest
    volumes:
      - synapse_data:/data
    environment:
      - SYNAPSE_SERVER_NAME=dev.gloam.chat
    ports:
      - "8008:8008"

  postgres:
    image: postgres:16
    volumes:
      - pg_data:/var/lib/postgresql/data

  mas:
    image: ghcr.io/element-hq/matrix-authentication-service:latest
    # For OIDC testing
```

### Recommended Homeservers (Users)

Gloam defaults to `matrix.org` for new accounts (largest, most accessible). The onboarding flow hides server selection behind "Advanced: Use your own server."

| Homeserver | Sliding Sync | OIDC | Notes |
|-----------|-------------|------|-------|
| matrix.org | Yes (Synapse) | MAS deployed | Default. Largest public server. Can be slow under load. |
| gloam.chat (future) | Yes | Yes | Optional — branded homeserver for Gloam users, if demand warrants it. |
| Self-hosted Synapse | Yes (if updated) | Optional | Target audience likely self-hosts. Documentation provided. |
| Conduit | Yes | Limited | Lightweight Rust homeserver. Growing adoption. |
| Dendrite | Partial | Limited | Second-gen Go homeserver. Sliding Sync support varies. |

### Compatibility Testing

Test against these homeserver configurations:
1. **Synapse + Sliding Sync + MAS** — primary target
2. **Synapse + Sliding Sync + legacy auth** — common self-hosted setup
3. **Synapse without Sliding Sync** — fallback path (sync v2)
4. **Conduit** — secondary target, lighter-weight
5. **matrix.org (production)** — real-world performance testing

---

## 4. Domain & Hosting

### DNS Configuration

| Record | Type | Value | Purpose |
|--------|------|-------|---------|
| `gloam.chat` | A/AAAA | Vercel/Cloudflare IP | Landing page |
| `www.gloam.chat` | CNAME | `gloam.chat` | Redirect |
| `push.gloam.chat` | A | VPS IP | Sygnal push gateway |
| `dev.gloam.chat` | A | VPS IP | Development homeserver |
| `_matrix._tcp.dev.gloam.chat` | SRV | `dev.gloam.chat:8448` | Matrix federation (dev server) |
| `.well-known` | — | Served by landing page | Matrix server discovery |

### Landing Page

| Property | Value |
|----------|-------|
| Framework | Static site (Astro or plain HTML) |
| Hosting | Vercel (free tier) or Cloudflare Pages (free tier) |
| Content | Product overview, screenshots, download links, FAQ |
| `.well-known/matrix/client` | Points to homeserver for `@user:gloam.chat` accounts (if/when branded homeserver exists) |

### Sygnal Hosting

| Option | Cost | Pros | Cons |
|--------|------|------|------|
| **Fly.io** | ~$5/mo | Easy deploy, auto-TLS, global edge | Vendor lock-in concern |
| **Hetzner VPS** | ~$4/mo (CX22) | Cheap, reliable, EU-based | Manual setup, own TLS |
| **DigitalOcean** | ~$6/mo (Basic droplet) | Simple, good docs | Slightly more expensive |
| **Railway** | ~$5/mo | Git push to deploy, auto-TLS | Pricing can spike |

**Recommendation:** Hetzner CX22 (2 vCPU, 4GB RAM, 40GB SSD) at EUR 3.99/mo. Run both sygnal and the dev Synapse instance on the same VPS. Use Caddy for automatic TLS.

### Sentry

| Property | Value |
|----------|-------|
| Plan | Free tier (5K errors/mo, 10K transactions/mo) |
| Project | `gloam-flutter` |
| DSN | Stored in CI secrets, embedded at build time |
| Platforms | Single Sentry project covers all 5 Flutter platforms |
| Source maps | Upload dSYM (iOS), ProGuard mapping (Android), Dart symbols |

---

## 5. App Store Accounts

### Apple Developer Program

| Property | Value |
|----------|-------|
| Cost | $99/year |
| Required for | iOS App Store, macOS App Store, TestFlight |
| Account type | Individual (upgrade to Organization if incorporating) |
| Setup time | 1-2 days (identity verification) |
| Bundle IDs | `chat.gloam.app` (iOS), `chat.gloam.app.macos` (macOS) |
| Capabilities needed | Push Notifications, App Groups (for notification extension), Keychain Sharing |

**Required assets (iOS):**

| Asset | Specification |
|-------|--------------|
| App icon | 1024x1024px PNG, no alpha |
| Screenshots (iPhone 6.7") | 1290x2796px, minimum 3, maximum 10 |
| Screenshots (iPhone 6.5") | 1284x2778px (optional but recommended) |
| Screenshots (iPad 12.9") | 2048x2732px (required if universal app) |
| App preview video | 15-30 seconds, optional |
| Description | Up to 4000 characters |
| Keywords | Up to 100 characters |
| Privacy policy URL | Required |
| Support URL | Required |

**Required assets (macOS):**

| Asset | Specification |
|-------|--------------|
| App icon | 1024x1024px PNG |
| Screenshots | 1280x800px or 1440x900px or 2560x1600px or 2880x1800px, minimum 1 |

### Google Play Developer Account

| Property | Value |
|----------|-------|
| Cost | $25 one-time |
| Required for | Google Play Store |
| Account type | Individual (upgrade to Organization later) |
| Setup time | 1-2 days (identity verification for new accounts can take up to 7 days) |
| Package name | `chat.gloam.app` |

**Required assets:**

| Asset | Specification |
|-------|--------------|
| App icon | 512x512px PNG |
| Feature graphic | 1024x500px PNG |
| Screenshots (phone) | 16:9 or 9:16, minimum 2, maximum 8, per device type |
| Screenshots (tablet 7") | Optional but recommended |
| Screenshots (tablet 10") | Optional but recommended |
| Short description | Up to 80 characters |
| Full description | Up to 4000 characters |
| Privacy policy URL | Required |
| Content rating questionnaire | Required |
| Data safety form | Required (declare data collection practices) |

### Microsoft Partner Center

| Property | Value |
|----------|-------|
| Cost | Free (for individual developers) |
| Required for | Microsoft Store (Windows) |
| Package format | MSIX |
| Setup time | 1-2 days |

**Required assets:**

| Asset | Specification |
|-------|--------------|
| App icon | 300x300px PNG |
| Screenshots | 1366x768px minimum, maximum 10 |
| Description | Up to 10,000 characters |
| Privacy policy URL | Required |

### Flathub (Linux)

| Property | Value |
|----------|-------|
| Cost | Free |
| Required for | Flatpak distribution (primary Linux channel) |
| Package format | Flatpak manifest (YAML) |
| Setup time | PR to flathub/flathub repo, review 1-2 weeks |
| App ID | `chat.gloam.app` (reverse domain) |

**Required assets:**

| Asset | Specification |
|-------|--------------|
| AppStream metadata | XML file with description, screenshots, releases |
| App icon | SVG preferred, 128x128px PNG fallback |
| Screenshots | 16:9, PNG, minimum 2 |

### Snap Store (Linux)

| Property | Value |
|----------|-------|
| Cost | Free |
| Required for | Snap distribution (Ubuntu ecosystem) |
| Package format | Snap (snapcraft.yaml) |
| Setup time | Register snap name, initial upload, 1-2 days |
| Snap name | `gloam` |

**Required assets:**

| Asset | Specification |
|-------|--------------|
| Icon | 256x256px PNG |
| Banner | 1920x640px PNG (optional) |
| Screenshots | 2-5 recommended |

---

## 6. Code Signing & Security

### iOS Provisioning & Entitlements

**Provisioning profiles (managed by Fastlane Match):**

| Profile | Type | Usage |
|---------|------|-------|
| Development | iOS Development | Local development builds |
| Ad Hoc | Ad Hoc Distribution | Internal testing (device UDIDs) |
| App Store | App Store Distribution | TestFlight + App Store |
| Notification Extension | App Store Distribution | `GloamNotificationService` extension |

**Entitlements:**

```xml
<!-- Gloam.entitlements -->
<key>aps-environment</key>
<string>production</string>

<key>com.apple.security.application-groups</key>
<array>
  <string>group.chat.gloam.app</string>  <!-- Shared data between app + notification extension -->
</array>

<key>keychain-access-groups</key>
<array>
  <string>$(AppIdentifierPrefix)chat.gloam.app</string>
</array>

<key>com.apple.developer.usernotifications.filtering</key>
<true/>  <!-- Notification Service Extension can modify/suppress notifications -->
```

**Fastlane Match:**
- Certificates and profiles stored in a private Git repo (encrypted)
- CI decrypts with `MATCH_PASSWORD` from GitHub Secrets
- Separate match repos for development and distribution certs

### macOS Notarization

| Step | Tool | Detail |
|------|------|--------|
| Sign app bundle | `codesign` | Developer ID Application certificate |
| Sign all frameworks/dylibs | `codesign` | Recursive signing with hardened runtime |
| Create DMG | `create-dmg` | Branded installer with background image |
| Sign DMG | `codesign` | Developer ID Application |
| Submit for notarization | `xcrun notarytool submit` | Apple reviews for malware |
| Staple ticket | `xcrun stapler staple` | Embeds notarization ticket in DMG |
| Verify | `spctl --assess` | Confirms Gatekeeper will accept |

**macOS entitlements:**

```xml
<!-- Gloam-macOS.entitlements -->
<key>com.apple.security.app-sandbox</key>
<true/>

<key>com.apple.security.network.client</key>
<true/>  <!-- Outbound network (Matrix API) -->

<key>com.apple.security.files.user-selected.read-write</key>
<true/>  <!-- File picker for attachments -->

<key>com.apple.security.personal-information.photos-library</key>
<true/>  <!-- Photo library access -->

<key>com.apple.security.device.camera</key>
<true/>  <!-- Camera for video calls, QR scanning -->

<key>com.apple.security.device.microphone</key>
<true/>  <!-- Microphone for voice messages, calls -->
```

### Android Signing

| Item | Detail |
|------|--------|
| Keystore | JKS or PKCS12 file, generated once, stored encrypted |
| Key alias | `gloam-release` |
| Passwords | GitHub Secrets: `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD` |
| Keystore storage | Base64-encoded in GitHub Secret: `ANDROID_KEYSTORE_BASE64` |
| Play App Signing | Enabled — Google manages the app signing key, we hold the upload key |

**CI signing step:**

```bash
echo $ANDROID_KEYSTORE_BASE64 | base64 --decode > android/app/upload-keystore.jks
```

**key.properties (generated in CI):**

```properties
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyPassword=$ANDROID_KEY_PASSWORD
keyAlias=gloam-release
storeFile=upload-keystore.jks
```

### Windows Code Signing

| Item | Detail |
|------|--------|
| Certificate | EV or OV code signing certificate (e.g., DigiCert, Sectigo) |
| Cost | ~$200-400/year (OV), ~$400-700/year (EV) |
| Tool | SignTool (Windows SDK) |
| Benefit | EV cert provides immediate SmartScreen reputation (no "unknown publisher" warning) |
| MSIX | Signed during packaging |
| Alternative (initial) | Self-signed for direct downloads, code-signed for Microsoft Store |

**CI signing step:**

```powershell
# Decode certificate from GitHub Secret
$certBytes = [Convert]::FromBase64String($env:WINDOWS_CERT_BASE64)
[IO.File]::WriteAllBytes("cert.pfx", $certBytes)

# Sign the MSIX
SignTool sign /f cert.pfx /p $env:WINDOWS_CERT_PASSWORD /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 gloam.msix
```

### Secrets Management in CI

All secrets stored in GitHub Actions encrypted secrets. Never committed to the repository.

| Secret | Used By | Rotation |
|--------|---------|----------|
| `MATCH_PASSWORD` | Fastlane Match (iOS cert decryption) | Annually |
| `MATCH_GIT_TOKEN` | Fastlane Match (private repo access) | 90 days |
| `APP_STORE_CONNECT_API_KEY` | Fastlane (iOS upload) | 1 year (Apple limit) |
| `ANDROID_KEYSTORE_BASE64` | Android signing | Never (upload key is permanent) |
| `ANDROID_KEYSTORE_PASSWORD` | Android signing | Never |
| `ANDROID_KEY_PASSWORD` | Android signing | Never |
| `PLAY_STORE_JSON_KEY` | Fastlane (Android upload) | Per Google service account |
| `WINDOWS_CERT_BASE64` | Windows code signing | Annually (cert expiry) |
| `WINDOWS_CERT_PASSWORD` | Windows code signing | Annually |
| `SENTRY_DSN` | Crash reporting | Rarely |
| `SENTRY_AUTH_TOKEN` | Symbol upload | Per Sentry org |
| `SYGNAL_APNS_KEY` | Push notification config | Annually |
| `SYGNAL_FCM_KEY` | Push notification config | Rarely |

**Security rules:**
- Secrets are scoped to specific environments (`production`, `staging`) where possible
- Branch protection: only `main` and `release/*` branches can access production secrets
- Dependabot alerts enabled for all dependencies
- No secrets in build logs (GitHub Actions masks them automatically)

---

## 7. Monitoring & Observability

### Sentry Crash Reporting

| Config | Value |
|--------|-------|
| Platform | `sentry_flutter` package |
| Sample rate (errors) | 100% (all errors captured) |
| Sample rate (transactions/performance) | 10% |
| Release tracking | Git tag as release name (`gloam@1.0.0+1`) |
| Environment | `production`, `staging`, `development` |
| PII scrubbing | Enabled — no usernames, room names, message content |

**Custom tags for Matrix-specific debugging:**

```dart
Sentry.configureScope((scope) {
  scope.setTag('homeserver', _anonymizeServer(homeserverUrl)); // "synapse/1.x" not full URL
  scope.setTag('sliding_sync', 'true');
  scope.setTag('encryption_enabled', 'true');
  scope.setTag('platform', Platform.operatingSystem);
});
```

**Key error grouping:**
- E2EE errors: grouped by `CryptoErrorKind`
- Sync errors: grouped by HTTP status + error code
- SDK errors: grouped by matrix_dart_sdk exception type

### Performance Monitoring

Tracked via Sentry Performance:

| Transaction | SLO | Alert Threshold |
|-------------|-----|----------------|
| `app.cold_start` | < 1.5s P95 | > 3s P95 |
| `room.open` | < 200ms P95 | > 500ms P95 |
| `message.send` (local echo) | < 100ms P95 | > 300ms P95 |
| `search.query` | < 500ms P95 | > 1s P95 |
| `sync.initial` | < 2s P95 | > 5s P95 |
| `crypto.decrypt` | < 50ms P95 | > 200ms P95 |

**Custom spans:**

```dart
final transaction = Sentry.startTransaction('room.open', 'navigation');
final dbSpan = transaction.startChild('db.query', description: 'load_timeline');
// ... load from drift
await dbSpan.finish();
final renderSpan = transaction.startChild('ui.render', description: 'timeline_build');
// ... build widget tree
await renderSpan.finish();
await transaction.finish();
```

### Push Delivery Tracking

| Metric | Source | How |
|--------|--------|-----|
| Push sent by homeserver | Synapse logs / sygnal access logs | Count outgoing push requests |
| Push delivered to APNs/FCM | Sygnal response codes | Track 200 vs error responses |
| Push received by device | App callback | Log in-app when push received (anonymized) |
| Push → app open latency | App cold start from push intent | Sentry transaction: `app.open_from_push` |
| Push token refresh rate | App lifecycle | Track re-registrations (indicates churn or token issues) |

**Alerting:**
- Sygnal error rate > 5% → PagerDuty/email alert
- Sygnal downtime → UptimeRobot → Slack/email
- APNs feedback with >10 invalid tokens → log warning (cleanup stale tokens)

### Opt-In Analytics

Gloam respects user privacy. Analytics are:
- **Opt-in only** (off by default)
- **Aggregate only** (no individual user tracking)
- **No third-party analytics SDKs** (no Google Analytics, no Amplitude, no Mixpanel)
- **Self-hosted** if implemented (Plausible or PostHog self-hosted)

If analytics are enabled (user opts in via Settings):

| Event | Data Collected | NOT Collected |
|-------|---------------|--------------|
| `app_open` | Platform, app version, screen size | User ID, homeserver |
| `room_open` | Encrypted (bool), member count bucket (1, 2-10, 10-50, 50+) | Room ID, room name |
| `message_send` | Message type (text/image/file), encrypted (bool) | Content, recipient |
| `search_used` | Filter types used, result count bucket | Query text |
| `feature_used` | Feature name (threads, reactions, voice message) | Context |
| `error_encountered` | Error type (network/crypto/sync) | Error details |

**Implementation:** Custom event logging to self-hosted PostHog instance. No data leaves the user's device unless they opt in. The toggle is in Settings > Privacy > "Help improve Gloam."

---

*This infrastructure plan covers the operational foundation for Gloam. It should be updated as hosting decisions are finalized, accounts are created, and the CI/CD pipeline is built out during Phase 0.*
