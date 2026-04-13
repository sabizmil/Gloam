import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'link_preview_meta.dart';

class LinkPreviewCache {
  LinkPreviewCache._();
  static final LinkPreviewCache instance = LinkPreviewCache._();

  Database? _db;
  Future<Database>? _opening;

  static const defaultTtl = Duration(days: 7);
  static const failedTtl = Duration(hours: 1);

  Future<Database> _open() {
    if (_db != null) return Future.value(_db!);
    return _opening ??= _openImpl();
  }

  Future<Database> _openImpl() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/gloam_link_previews.db';
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE link_preview_cache (
              url TEXT PRIMARY KEY,
              title TEXT,
              description TEXT,
              image_url TEXT,
              fetched_at INTEGER NOT NULL,
              expires_at INTEGER NOT NULL,
              failed INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_link_preview_expires '
            'ON link_preview_cache(expires_at)',
          );
        },
      ),
    );
    _db = db;

    unawaited(purgeExpired());
    return db;
  }

  Future<LinkPreviewMeta?> get(String url) async {
    final db = await _open();
    final rows = await db.query(
      'link_preview_cache',
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LinkPreviewMeta.fromRow(rows.first);
  }

  Future<void> put(LinkPreviewMeta meta) async {
    final db = await _open();
    await db.insert(
      'link_preview_cache',
      meta.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> purgeExpired({DateTime? before}) async {
    final db = await _open();
    final cutoff = (before ?? DateTime.now()).millisecondsSinceEpoch;
    return db.delete(
      'link_preview_cache',
      where: 'expires_at < ?',
      whereArgs: [cutoff],
    );
  }
}
