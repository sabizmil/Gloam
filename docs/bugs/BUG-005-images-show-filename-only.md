# BUG-005: Images show filename only, no preview

**Reported:** 2026-03-26
**Status:** Open
**Priority:** P1 (broken feature)

## Description
Image messages display only the filename text inside a grey box instead of showing the actual image preview. The user expects inline image previews with click-to-fullscreen and download capabilities.

## Steps to Reproduce
1. Open an encrypted room where images have been shared
2. Look at any `m.image` message
3. Instead of the image, a grey rectangle with the filename text is shown (e.g. "Screenshot 2026-03-26 at 12.22.12 PM.png")

## Expected Behavior
- Inline image thumbnail rendered in the message bubble (max 400x300)
- Click opens fullscreen viewer with pinch-to-zoom
- Loading indicator while image downloads
- Broken image fallback only if the download truly fails

## Actual Behavior
Grey box with filename. The `ImageMessage` widget falls into the error state because:
1. For encrypted rooms, the image file on the server is encrypted (AES-CTR)
2. `getDownloadUri` returns a valid HTTP URL but the bytes at that URL are encrypted ciphertext
3. `Image.network` downloads the ciphertext and tries to decode it as a PNG/JPEG — fails
4. Falls through to the error widget showing just the filename

## Root Cause Analysis
`image_message.dart` uses `getDownloadUri` + `Image.network` which doesn't handle encrypted attachments. For E2EE rooms, the flow needs to be:

1. Download the encrypted blob from the MXC URL
2. Decrypt using the key/iv/hash from the event's `file` content field
3. Display the decrypted bytes via `Image.memory`

The Matrix SDK provides `event.downloadAndDecryptAttachment()` which handles this entire flow, but `ImageMessage` doesn't use it — it operates on the `TimelineMessage` model which only stores `mediaUrl` (the MXC URI).

For unencrypted rooms, `Image.network` with the download URI works fine. The fix needs to handle both cases.

## Implementation Plan

### Option A: Use SDK's download+decrypt (recommended)
1. Pass the original `Event` or the `room` + `eventId` to `ImageMessage` instead of just the model
2. Call `event.downloadAndDecryptAttachment()` which returns `MatrixFile` with decrypted bytes
3. Display with `Image.memory(matrixFile.bytes)`
4. Cache decrypted bytes in memory (Map<eventId, Uint8List>) to avoid re-downloading

### Option B: Detect encryption and branch
1. Add `isEncrypted` flag to `TimelineMessage` model (already have `isEncrypted` on the room level)
2. Add `encryptedFileInfo` (the `file` JSON with key/iv/hash) to the model
3. In `ImageMessage`: if encrypted, download raw bytes via dio, decrypt manually using the key
4. If not encrypted, use the existing `Image.network` path

### Recommended: Option A — simpler, the SDK handles crypto

**Implementation steps:**
1. Add a `sendFileEvent` method to `TimelineNotifier` that takes a room and event ID
2. Create a `_loadEncryptedImage` path in `ImageMessage`:
   ```dart
   final client = ref.read(matrixServiceProvider).client;
   final room = client.getRoomById(roomId);
   final event = await room.getEventById(eventId);
   final file = await event.downloadAndDecryptAttachment();
   setState(() => _imageBytes = file.bytes);
   ```
3. Use `Image.memory(_imageBytes!)` for display
4. Add `roomId` to `TimelineMessage` model (it's already there: `roomId` isn't exposed but `senderId` is — we need the room context)
5. Cache results in a static map keyed by eventId

## Affected Files
- `lib/features/chat/presentation/widgets/image_message.dart` — Major rewrite to use SDK decrypt
- `lib/features/chat/presentation/providers/timeline_provider.dart` — Expose `roomId` on model
- `lib/features/chat/presentation/widgets/message_bubble.dart` — Pass roomId to ImageMessage
