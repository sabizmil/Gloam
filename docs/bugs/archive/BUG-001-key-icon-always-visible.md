# BUG-001: Key icon shows even after recovery key entered

**Reported:** 2026-03-26
**Status:** Open
**Priority:** P2 (visual/polish)

## Description
The key icon (🔑) in the chat header for encrypted rooms is always visible, even after the user has successfully entered their recovery key and SSSS is unlocked.

## Steps to Reproduce
1. Open an encrypted room
2. Click the key icon, enter recovery key, unlock succeeds
3. Key icon is still visible in the header

## Expected Behavior
The key icon should either:
- Disappear once SSSS is unlocked (keys restored)
- Change to a checkmark/lock icon indicating encryption is healthy
- Only appear when there are undecryptable messages in the current room

## Actual Behavior
Key icon is always shown for any encrypted room regardless of SSSS state.

## Root Cause Analysis
In `chat_screen.dart:396`, the key icon is shown with a simple `if (isEncrypted)` check. There's no check for whether SSSS is already unlocked or whether the room has undecryptable messages.

```dart
if (isEncrypted)
  Builder(
    builder: (ctx) => _HeaderAction(
      icon: Icons.key,
      onTap: () => showRecoveryKeyDialog(ctx),
    ),
  ),
```

## Implementation Plan
1. Check `client.encryption?.ssss.open().privateKey != null` to determine if SSSS is already unlocked
2. Alternatively, check if there are any `m.room.encrypted` events in the visible timeline that failed to decrypt
3. Only show the key icon when there are undecryptable messages OR SSSS is not unlocked
4. If SSSS is unlocked and all messages decrypt, hide the icon entirely

## Affected Files
- `lib/features/chat/presentation/screens/chat_screen.dart`
- `lib/services/matrix_service.dart` (add `isSsssUnlocked` getter)
