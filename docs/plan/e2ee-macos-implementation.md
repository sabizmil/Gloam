# E2EE macOS Implementation Plan

**Date:** 2026-03-26
**Status:** Blocking — encryption works for new messages, but historical decryption and device verification are broken on macOS desktop.

---

## Current State

| Feature | Status | Root Cause |
|---------|--------|------------|
| E2EE for new messages | Working | `flutter_olm` + manually bundled `libolm.3.dylib` |
| Sending encrypted messages | Working | Same as above |
| Device name "Gloam (macOS)" | Working | Set in `initialDeviceDisplayName` |
| Historical message decryption | Broken | SSSS key backup unlock needs `libcrypto.1.1.dylib` (OpenSSL 1.1) for PBKDF2 key derivation. Not available on macOS — `flutter_openssl_crypto` only bundles it for iOS. |
| Interactive device verification | Broken | Gloam listens for incoming verification requests but cannot initiate verification from its side. Cinny's "Verify" button sends a request that Gloam needs to accept, but the emoji comparison flow isn't completing. |
| Cross-signing setup | Not implemented | New accounts should auto-generate cross-signing keys. Existing accounts need to restore from SSSS. |

---

## Problem 1: libcrypto.1.1.dylib for macOS

### Why It's Needed

The Matrix SDK's SSSS (Secure Secret Storage and Sharing) uses PBKDF2 for passphrase-based key derivation. The `olm` Dart package and `matrix_dart_sdk` call into OpenSSL's `libcrypto` via FFI for this operation. On iOS, `flutter_openssl_crypto` bundles the library. On macOS desktop, nothing provides it.

The specific call chain:
```
User enters recovery key/passphrase
  → ssss.open().unlock(passphrase: ...)
  → NativeImplementations.keyFromPassphrase()
  → PBKDF2 via libcrypto FFI
  → DynamicLibrary.open('libcrypto.1.1.dylib')
  → CRASH: library not found
```

Recovery keys (base58-encoded) DON'T need PBKDF2 — they decode directly. But the SDK's `checkKey()` validation or `_postUnlock()` backup restoration may still trigger libcrypto calls.

### Solution Options

| Option | Effort | Pros | Cons |
|--------|--------|------|------|
| **A: Build and bundle OpenSSL 1.1 from source** | High | Fully solves the problem, works offline | OpenSSL 1.1 is EOL, security risk. Complex build matrix for ARM64. |
| **B: Build and bundle OpenSSL 3.x, create a compatibility shim** | High | Modern, maintained OpenSSL | API differences from 1.1 → 3.x require a wrapper dylib that maps old symbols to new. |
| **C: Pure Dart PBKDF2 implementation** | Medium | No native dependency. Cross-platform. | Slower than native (10-50x for high iteration counts). But PBKDF2 is only called once during unlock — acceptable. |
| **D: Use `cryptography` Dart package** | Low | Pure Dart, well-maintained, already implements PBKDF2, HKDF, etc. | Need to wire it into the SDK's `NativeImplementations` interface as a custom implementation. |
| **E: Use `webcrypto` package** | Low | Uses platform native crypto (CommonCrypto on macOS). Fast. | Async API, need to adapt to SDK's expected interface. |

### Recommended: Option D — Pure Dart crypto via `cryptography` package

**Why:**
- Zero native dependencies to bundle
- Works on ALL platforms (macOS, Windows, Linux, iOS, Android, Web) without per-platform bundling
- The `cryptography` package is mature (4.0+), well-maintained, and implements PBKDF2-SHA-512, HKDF-SHA-256, and all primitives the Matrix SDK needs
- PBKDF2 is only called once during SSSS unlock — the ~50ms overhead of pure Dart vs native is invisible to the user
- Eliminates the entire "bundle OpenSSL" problem permanently

**Implementation:**

1. Add `cryptography: ^2.7.0` to pubspec.yaml
2. Create a custom `NativeImplementations` subclass that overrides `keyFromPassphrase` to use pure Dart PBKDF2:

```dart
class GloamNativeImplementations extends NativeImplementations {
  @override
  Future<Uint8List> keyFromPassphrase(KeyFromPassphraseArgs args) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha512(),
      iterations: args.info.iterations!,
      bits: args.info.bits ?? 256,
    );
    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(args.passphrase)),
      nonce: base64.decode(args.info.salt!),
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }
}
```

3. Pass this to the `Client` constructor:

```dart
Client(
  'gloam',
  nativeImplementations: GloamNativeImplementations(),
  ...
)
```

4. Remove `flutter_openssl_crypto` from pubspec (already done)
5. Remove the manual `libolm.3.dylib` copy step — still needed for olm itself, but crypto operations use pure Dart

**Also needed:** Automate the `libolm.3.dylib` bundling into the macOS build so it doesn't require a manual copy+sign step after every build. Add a Run Script build phase to the Xcode project.

---

## Problem 2: libolm Bundling Automation

### Current State

Every macOS build requires manually:
1. Copying `/opt/homebrew/lib/libolm.3.dylib` into the app bundle's `Contents/MacOS/`
2. Ad-hoc codesigning the dylib
3. Re-signing the entire app bundle

This breaks on every rebuild and is not sustainable.

### Solution

Add a **Run Script Build Phase** to the Xcode project that runs after "Copy Bundle Resources":

```bash
#!/bin/bash
# Bundle libolm for Matrix E2EE support
LIBOLM_PATH="/opt/homebrew/lib/libolm.3.dylib"
DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/MacOS/libolm.3.dylib"

if [ -f "$LIBOLM_PATH" ]; then
  cp "$LIBOLM_PATH" "$DEST"
  codesign --force --sign - "$DEST"
  echo "Bundled libolm from $LIBOLM_PATH"
else
  echo "warning: libolm not found at $LIBOLM_PATH — E2EE will not work"
fi
```

**Alternative for CI/production:** Use a CocoaPods podspec that compiles libolm from source as part of the build. This is what a proper `flutter_olm` macOS port would do. For now, the Homebrew copy is fine for development.

### Implementation

Modify `macos/Runner.xcodeproj/project.pbxproj` to add the build phase, OR create a helper script that `flutter build` calls via a build hook.

Simplest approach: Add a `Makefile` or shell wrapper:

```bash
#!/bin/bash
# build_macos.sh — Build Gloam for macOS with E2EE support
set -e
fvm flutter build macos --debug
APP="build/macos/Build/Products/Debug/gloam.app"
cp /opt/homebrew/lib/libolm.3.dylib "$APP/Contents/MacOS/"
codesign --force --sign - "$APP/Contents/MacOS/libolm.3.dylib"
codesign --force --deep --sign - "$APP"
echo "✓ Built $APP with libolm"
```

---

## Problem 3: Interactive Device Verification

### Current State

- Gloam has a `VerificationService` that listens for incoming verification requests via `client.onKeyVerificationRequest`
- When Cinny initiates verification, it sends a `m.key.verification.request` to-device event
- Gloam's listener fires, calls `request.acceptVerification()`, then waits for `KeyVerificationState.askSas`
- **Issue:** The state transition never reaches `askSas` — the verification times out or gets stuck

### Root Causes

1. **Verification protocol mismatch:** The SDK's `KeyVerification` state machine requires both sides to agree on a verification method. The current listener may not be handling the method negotiation correctly.

2. **Missing `m.key.verification.ready` response:** After receiving the request, Gloam needs to send a "ready" response before the SAS flow starts. The `acceptVerification()` call should do this, but the state machine may need the client to be actively processing sync events during the verification.

3. **Sync timing:** The verification protocol uses to-device messages. If the sync loop isn't running or is delayed, the state transitions stall.

4. **No way to initiate from Gloam:** Currently Gloam can only RESPOND to verification requests, not initiate them. Users need to be able to start verification from Gloam too.

### Solution

Replace the custom polling-based `VerificationService` with a proper stream-based implementation that tracks the verification state machine:

```dart
class VerificationService {
  void listen(Client client, GlobalKey<NavigatorState> navKey) {
    // Listen for incoming verification requests
    client.onKeyVerificationRequest.stream.listen((request) async {
      // Show a "Verification Request" dialog
      final accepted = await _showAcceptDialog(navKey, request);
      if (!accepted) {
        await request.rejectVerification();
        return;
      }

      await request.acceptVerification();

      // Listen to state changes on this request
      request.onUpdate = () {
        _handleStateChange(request, navKey);
      };
    });
  }

  void _handleStateChange(KeyVerification request, GlobalKey<NavigatorState> navKey) {
    switch (request.state) {
      case KeyVerificationState.askSas:
        _showEmojiDialog(navKey, request);
      case KeyVerificationState.done:
        _showSuccessDialog(navKey);
      case KeyVerificationState.error:
        _showErrorDialog(navKey, request.canceledCode);
      default:
        break;
    }
  }
}
```

**Key changes from current implementation:**
- Use `request.onUpdate` callback instead of polling with `Future.delayed`
- Show an explicit "Accept verification?" dialog before calling `acceptVerification()`
- Handle all verification states (not just `askSas`)
- Add ability to INITIATE verification: `client.userDeviceKeys[userId]!.startVerification()`

### Verification UI Screens

1. **Incoming request banner** — Non-modal banner at top of screen: "[Device name] wants to verify. Accept / Decline"
2. **Emoji comparison** — Modal dialog showing 7 emoji with names. "They match" / "They don't match" buttons.
3. **Success** — Brief "Device verified ✓" confirmation that auto-dismisses
4. **Error** — "Verification failed" with reason and "Try again" option
5. **Initiate verification** — Button in settings or room info panel: "Verify this device" which starts the flow from Gloam's side

---

## Problem 4: Cross-Signing Bootstrap

### Current State

Not implemented. When Gloam creates a new account, it doesn't set up cross-signing keys. When Gloam logs into an existing account, it doesn't restore cross-signing keys from SSSS.

### What Needs to Happen

**On new account creation:**
1. Generate master, self-signing, and user-signing cross-signing keys
2. Upload to homeserver via SSSS
3. Sign the current device with the self-signing key
4. Generate a recovery key (12-word mnemonic)
5. Present to user once with "save this" prompt
6. Enable automatic key backup

**On existing account login:**
1. Check if cross-signing keys exist on the server (SSSS)
2. If yes: prompt for recovery key/passphrase to unlock SSSS → restore cross-signing keys → sign current device
3. If no: bootstrap cross-signing (same as new account)

### Implementation

The matrix_dart_sdk provides `client.encryption!.bootstrap()` which handles most of this:

```dart
final bootstrap = client.encryption!.bootstrap(
  onUpdate: (Bootstrap bs) {
    // Track bootstrap state, show UI as needed
    if (bs.state == BootstrapState.askWipeSsss) {
      bs.wipeSsss(false); // Don't wipe existing SSSS
    }
    if (bs.state == BootstrapState.askNewSsss) {
      bs.openExistingSsss(); // Use existing SSSS
    }
    if (bs.state == BootstrapState.askUnlockSsss) {
      bs.unlockSsss(recoveryKey: userProvidedKey);
    }
    if (bs.state == BootstrapState.askSetupCrossSigning) {
      bs.askSetupCrossSigning(
        setupMasterKey: true,
        setupSelfSigningKey: true,
        setupUserSigningKey: true,
      );
    }
  },
);
```

The bootstrap flow is complex with many states — it needs a dedicated UI wizard or a smart auto-handler that makes decisions invisibly.

---

## Implementation Order

| Step | Task | Blocks | Effort |
|------|------|--------|--------|
| 1 | Add `cryptography` package, implement `GloamNativeImplementations` with pure Dart PBKDF2 | Nothing | 2 hours |
| 2 | Wire `GloamNativeImplementations` into Client constructor | Step 1 | 30 min |
| 3 | Test SSSS unlock with recovery key AND passphrase on macOS | Steps 1-2 | 1 hour |
| 4 | Create `build_macos.sh` script to automate libolm bundling | Nothing | 30 min |
| 5 | Rewrite `VerificationService` with stream-based state handling | Nothing | 3 hours |
| 6 | Build verification UI (accept dialog, emoji comparison, success/error) | Step 5 | 2 hours |
| 7 | Add "Verify device" button that initiates verification from Gloam | Steps 5-6 | 1 hour |
| 8 | Implement bootstrap flow for cross-signing setup on login | Steps 1-3 | 4 hours |
| 9 | Test full flow: login → bootstrap → verify → unlock backup → decrypt history | All | 2 hours |

**Total estimated effort: ~16 hours**

---

## Success Criteria

- [ ] Entering a recovery key or passphrase on macOS successfully unlocks SSSS and decrypts historical messages
- [ ] No native crypto library errors on any platform
- [ ] Clicking "Verify" in Cinny triggers an emoji comparison dialog in Gloam
- [ ] Clicking "Verify device" in Gloam initiates verification with another session
- [ ] After verification, historical messages decrypt within 30 seconds
- [ ] New accounts get automatic cross-signing setup with recovery key presentation
- [ ] The macOS build process doesn't require manual dylib copying (automated via script)
