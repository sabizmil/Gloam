import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/debug_server.dart';
import '../../../../services/matrix_service.dart';
import '../../data/encrypted_media_cache.dart';

/// Disk-cached decrypted bytes for encrypted attachments.
/// On cache miss, asks the SDK to download + decrypt the event, writes the
/// plaintext to disk, and returns. Subsequent accesses in-session are
/// Riverpod-cached (in-memory); across sessions they come from the disk.
final encryptedMediaProvider =
    FutureProvider.family<Uint8List, MediaRef>((ref, key) async {
  final cache = EncryptedMediaCache.instance;

  final cached = await cache.read(key);
  if (cached != null) {
    DebugServer.mediaStats.hits++;
    return cached;
  }

  DebugServer.mediaStats.misses++;

  final client = ref.read(matrixServiceProvider).client;
  if (client == null) {
    throw StateError('Matrix client not available');
  }
  final room = client.getRoomById(key.roomId);
  if (room == null) {
    throw StateError('Room ${key.roomId} not found');
  }
  final event = await room.getEventById(key.eventId);
  if (event == null) {
    throw StateError('Event ${key.eventId} not found');
  }

  final file = await event.downloadAndDecryptAttachment();
  await cache.write(key, file.bytes);
  DebugServer.mediaStats.fetches++;
  return file.bytes;
});
