import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class MediaRef {
  const MediaRef({required this.roomId, required this.eventId});
  final String roomId;
  final String eventId;

  @override
  bool operator ==(Object other) =>
      other is MediaRef && other.roomId == roomId && other.eventId == eventId;

  @override
  int get hashCode => Object.hash(roomId, eventId);

  @override
  String toString() => 'MediaRef($roomId, $eventId)';
}

/// Disk-backed cache for decrypted attachment bytes.
///
/// Files are stored at `<appSupport>/gloam_media_cache/<sanitizedRoomId>/<sanitizedEventId>`.
/// Eviction is LRU-by-mtime, triggered via [sweepLRU] — typically on app start.
class EncryptedMediaCache {
  EncryptedMediaCache._();
  static final EncryptedMediaCache instance = EncryptedMediaCache._();

  static const maxBytes = 500 * 1024 * 1024;
  static const targetBytes = 400 * 1024 * 1024;

  Directory? _root;
  Future<Directory>? _opening;

  Future<Directory> _ensureRoot() {
    if (_root != null) return Future.value(_root!);
    return _opening ??= _openImpl();
  }

  Future<Directory> _openImpl() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/gloam_media_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<File> _fileFor(MediaRef ref) async {
    final root = await _ensureRoot();
    final room = _sanitize(ref.roomId);
    final event = _sanitize(ref.eventId);
    final roomDir = Directory('${root.path}/$room');
    if (!await roomDir.exists()) await roomDir.create(recursive: true);
    return File('${roomDir.path}/$event');
  }

  Future<Uint8List?> read(MediaRef ref) async {
    final file = await _fileFor(ref);
    if (!await file.exists()) return null;
    // Bump mtime so LRU treats this as recently-used.
    unawaited(file.setLastAccessed(DateTime.now()).catchError((_) {}));
    return file.readAsBytes();
  }

  Future<void> write(MediaRef ref, Uint8List bytes) async {
    final file = await _fileFor(ref);
    await file.writeAsBytes(bytes, flush: false);
  }

  /// Walk the cache dir and evict oldest files until total size < [targetBytes].
  /// Runs on a background isolate-free sweep; safe to call repeatedly.
  Future<int> sweepLRU() async {
    final root = await _ensureRoot();
    final entries = <_Entry>[];
    int total = 0;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          entries.add(_Entry(entity, stat.size, stat.accessed));
          total += stat.size;
        } catch (_) {}
      }
    }

    if (total <= maxBytes) return 0;

    entries.sort((a, b) => a.accessed.compareTo(b.accessed));
    int deleted = 0;
    for (final entry in entries) {
      if (total <= targetBytes) break;
      try {
        await entry.file.delete();
        total -= entry.size;
        deleted++;
      } catch (_) {}
    }
    return deleted;
  }
}

class _Entry {
  _Entry(this.file, this.size, this.accessed);
  final File file;
  final int size;
  final DateTime accessed;
}
