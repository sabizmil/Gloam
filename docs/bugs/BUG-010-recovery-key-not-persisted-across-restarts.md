# BUG-010: Recovery key not persisted across app restarts

**Reported:** 2026-03-26
**Status:** Open
**Priority:** P1 (broken feature)

## Description

After entering the recovery key in the recovery key dialog, the SSSS unlock state does not persist across app restarts. On relaunch, the key icon reappears in the chat header, and previously decryptable messages may revert to "The sender has not sent us the session key." The user must re-enter the recovery key every time the app starts, which is unacceptable UX -- other Matrix clients (Element, FluffyChat) store the SSSS key securely and auto-unlock on restart.

## Steps to Reproduce

1. Open the app, navigate to an encrypted room
2. Enter the recovery key via the key icon in the chat header
3. Verify messages decrypt and the key icon disappears (or should -- see BUG-001 archived)
4. Quit the app completely (Cmd+Q on macOS)
5. Relaunch the app
6. Navigate to the same encrypted room
7. Key icon is visible again, some messages show as undecryptable

## Expected Behavior

- Enter the recovery key once after initial login
- The key (or a derived secret) is stored securely in the platform's keychain/keystore
- On subsequent app launches, SSSS auto-unlocks using the stored key
- Messages remain decryptable without user intervention
- The key persists until the user explicitly logs out

## Actual Behavior

- SSSS unlock is ephemeral -- exists only in memory for the current session
- On app restart, `client.encryption!.ssss.open()` yields a fresh `OpenSSSS` that has no cached private key
- The key icon reappears (because messages are undecryptable again)
- User must re-enter the recovery key every launch

## Root Cause Analysis

The issue spans two files:

### 1. No storage of the recovery key (`recovery_key_dialog.dart`, lines 30-77)

The `_unlock()` method calls `ssss.open()` and `keyInfo.unlock(keyOrPassphrase: input)` but never persists `input` (the recovery key) or the derived SSSS private key to secure storage. Once the app process ends, the unlocked state is lost.

```dart
// recovery_key_dialog.dart:49-59
final ssss = client!.encryption!.ssss;
if (ssss.defaultKeyId == null) { ... }
final keyInfo = ssss.open();
await keyInfo.unlock(keyOrPassphrase: input);
// <-- Nothing stores `input` or the derived key
```

### 2. No auto-unlock on startup (`home_screen.dart`, lines 131-157 / `matrix_service.dart`, lines 34-60)

The `_AuthenticatedHomeState.initState()` initializes the verification service and notifications but never checks for a stored recovery key to auto-unlock SSSS. The `MatrixService.initialize()` method restores the Matrix session from the SDK's database but does not handle SSSS.

### 3. `flutter_secure_storage` is declared but unused

The `pubspec.yaml` (line 32) includes `flutter_secure_storage: ^9.2.4` as a dependency, but a search of the `lib/` directory shows **zero imports** of `flutter_secure_storage` anywhere. The package was added but never wired up.

## Implementation Plan

### Step 1: Create a secure storage service

Create `lib/services/secure_storage_service.dart`:
```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _recoveryKeyKey = 'gloam_ssss_recovery_key';
  final _storage = const FlutterSecureStorage();

  Future<void> storeRecoveryKey(String key) async {
    await _storage.write(key: _recoveryKeyKey, value: key);
  }

  Future<String?> getRecoveryKey() async {
    return await _storage.read(key: _recoveryKeyKey);
  }

  Future<void> clearRecoveryKey() async {
    await _storage.delete(key: _recoveryKeyKey);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
```

### Step 2: Persist the recovery key after successful unlock

In `recovery_key_dialog.dart`, after `keyInfo.unlock()` succeeds, store the recovery key:
```dart
await keyInfo.unlock(keyOrPassphrase: input);
// Persist for auto-unlock on next launch
await SecureStorageService().storeRecoveryKey(input);
```

### Step 3: Auto-unlock SSSS on app startup

In `home_screen.dart` `_AuthenticatedHomeState.initState()` (or in `matrix_service.dart`), after session restore, attempt auto-unlock:
```dart
final storedKey = await SecureStorageService().getRecoveryKey();
if (storedKey != null && client.encryption != null) {
  try {
    final ssss = client.encryption!.ssss;
    if (ssss.defaultKeyId != null) {
      final keyInfo = ssss.open();
      await keyInfo.unlock(keyOrPassphrase: storedKey);
      // Also trigger key backup restore (see BUG-009)
    }
  } catch (e) {
    // Stored key invalid (user changed it?) -- clear and show key icon
    await SecureStorageService().clearRecoveryKey();
  }
}
```

### Step 4: Clear on logout

In `auth_provider.dart` `logout()` method, or `matrix_service.dart` `logout()`, clear the stored key:
```dart
await SecureStorageService().clearAll();
```

### Step 5: Update key icon visibility

The key icon in `chat_screen.dart` (line 560) currently checks `hasUndecryptable`, which is derived from message body text matching. After auto-unlock works, this should naturally hide the icon since messages will decrypt. But as a safety net, also check `client.encryption?.ssss.open().privateKey != null` to suppress the icon when SSSS is currently unlocked.

## Affected Files

- **New**: `lib/services/secure_storage_service.dart` -- secure storage wrapper
- `lib/features/settings/presentation/recovery_key_dialog.dart` -- persist key after unlock
- `lib/features/rooms/presentation/home_screen.dart` -- auto-unlock SSSS on startup
- `lib/services/matrix_service.dart` -- potentially add SSSS auto-unlock to `initialize()`
- `lib/features/auth/presentation/providers/auth_provider.dart` -- clear secure storage on logout
- `lib/features/chat/presentation/screens/chat_screen.dart` -- key icon visibility refinement
