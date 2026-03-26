# BUG-009: Megolm session keys not restored from key backup after SSSS unlock

**Reported:** 2026-03-26
**Status:** Open
**Priority:** P1 (broken feature)

## Description

After entering the recovery/security key via the recovery key dialog, some messages still show "The sender has not sent us the session key" while others in the same room history decrypt fine. This indicates that while SSSS is being unlocked, the app never triggers a full restore of Megolm session keys from the server-side key backup.

## Steps to Reproduce

1. Log in on a fresh device (or clear app data)
2. Open an encrypted room with historical messages
3. Observe many messages show "The sender has not sent us the session key"
4. Open Settings > Encryption > Enter Recovery Key
5. Enter a valid recovery key; dialog shows "keys restored -- messages decrypting..."
6. Close dialog, return to the encrypted room
7. Some messages now decrypt, but many still show the session key error

## Expected Behavior

After entering the recovery key:
1. SSSS is unlocked (this works)
2. The key backup decryption key is derived from SSSS
3. All available Megolm session keys are downloaded from the server-side key backup
4. Existing encrypted events in loaded timelines are re-decrypted
5. All previously undecryptable messages (where keys exist in the backup) become readable

## Actual Behavior

Only step 1 happens. The app unlocks SSSS via `ssss.open()` + `keyInfo.unlock()` but never:
- Calls `client.encryption!.keyManager.request()` for missing sessions
- Checks or enables key backup restoration via `client.encryption!.keyManager`
- Triggers a bulk download of Megolm sessions from the backup
- Forces timeline re-decryption after keys are obtained

## Root Cause Analysis

The issue is in `lib/features/settings/presentation/recovery_key_dialog.dart`, lines 49-67.

The `_unlock()` method does only this:
```dart
final ssss = client!.encryption!.ssss;
final keyInfo = ssss.open();
await keyInfo.unlock(keyOrPassphrase: input);
// Wait a moment for keys to restore, then close
await Future.delayed(const Duration(seconds: 2));
```

This unlocks SSSS (the encrypted secret store on the server) but does **not**:

1. **Load the key backup decryption key from SSSS**: After unlocking SSSS, the app must read the `m.megolm_backup.v1` secret to get the private key for decrypting the key backup. The Matrix SDK typically does this via `client.encryption!.keyManager.loadSingleKey(roomId, sessionId)` or a bulk method.

2. **Enable key backup**: The SDK's `client.encryption!.keyManager.enabled` may still be `false` because the backup private key hasn't been cached. After SSSS unlock, the app should call something like:
   ```dart
   await client.encryption!.keyManager.loadFromEncryptedKeyBackup();
   ```
   or iterate through rooms with undecryptable events and request keys.

3. **Request missing keys**: For each room with undecryptable messages, the app should trigger key requests via `client.encryption!.keyManager.request()` or use the SDK's built-in backup restore flow.

4. **Force timeline rebuild**: After keys are obtained, the timeline events need to be re-decrypted. The `TimelineNotifier._rebuild()` method re-maps events, but `event.getDisplayEvent(timeline)` will only show decrypted content if the Megolm session was loaded into the Olm machine. Without triggering key restoration, the sessions remain missing.

The `Future.delayed(const Duration(seconds: 2))` on line 67 is a naive wait that assumes key restoration happens automatically -- it doesn't in this SDK configuration.

## Implementation Plan

1. **In `recovery_key_dialog.dart`, after `keyInfo.unlock()`**: Add the missing key backup restoration steps:
   ```dart
   // 1. Unlock SSSS
   await keyInfo.unlock(keyOrPassphrase: input);

   // 2. Get the backup key from SSSS and enable backup
   // The SDK caches the backup key once SSSS is unlocked properly
   await client.encryption!.keyManager.loadFromEncryptedKeyBackup();

   // 3. Request missing keys for all rooms
   for (final room in client.rooms) {
     if (room.encrypted) {
       await client.encryption!.keyManager
           .maybeAutoRequest(room.id);
     }
   }
   ```

2. **Investigate the exact SDK API**: The `matrix` Dart SDK (v0.40.2) may provide specific methods. Check:
   - `client.encryption!.keyManager.loadSingleKey(roomId, sessionId)` -- per-session
   - `client.encryption!.backupEnabled` / `client.encryption!.keyManager.enabled`
   - `client.encryption!.keyManager.request(room, sessionId, senderKey)` -- request from other devices
   - Whether `ssss.getCached(EventTypes.MegolmBackup)` returns the backup decryption key after unlock

3. **Add a progress indicator** in the recovery key dialog showing keys being restored (not just a 2-second delay).

4. **Force timeline refresh** after key restoration completes -- either by disposing/recreating the timeline or calling `_rebuild()` after a sync completes.

5. **Consider adding auto-key-request on encrypted event display**: In `TimelineNotifier._rebuild()`, when an event of type `EventTypes.Encrypted` is encountered (failed decryption), queue a key request for that session.

## Affected Files

- `lib/features/settings/presentation/recovery_key_dialog.dart` -- main fix: add key backup restore after SSSS unlock
- `lib/services/matrix_service.dart` -- potentially add helper methods for key backup restoration
- `lib/features/chat/presentation/providers/timeline_provider.dart` -- add re-decryption trigger after keys are obtained
- `lib/features/rooms/presentation/home_screen.dart` -- potentially trigger key backup check on app startup if SSSS was previously unlocked
