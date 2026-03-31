import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';

import 'matrix_service.dart';

/// Search result from the local FTS5 index.
class SearchResult {
  final String eventId;
  final String roomId;
  final String senderId;
  final String senderName;
  final String roomName;
  final String body;
  final DateTime timestamp;
  final double score;

  const SearchResult({
    required this.eventId,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.roomName,
    required this.body,
    required this.timestamp,
    required this.score,
  });
}

/// Schema version — bump to force a full reindex.
const _schemaVersion = 2;

/// Client-side encrypted search using SQLite FTS5.
///
/// Indexes decrypted message content for instant search across all rooms,
/// including E2EE rooms where server-side search is impossible.
class SearchService {
  Database? _db;
  final Client _client;
  StreamSubscription? _syncSub;

  SearchService(this._client);

  Future<void> initialize() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = '${dir.path}/gloam_search.db';

    _db = await databaseFactory.openDatabase(dbPath);

    // Check schema version — drop and recreate if outdated
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS schema_version (
        version INTEGER PRIMARY KEY
      )
    ''');
    final versionRows = await _db!.query('schema_version');
    final currentVersion = versionRows.isNotEmpty
        ? versionRows.first['version'] as int
        : 0;

    if (currentVersion < _schemaVersion) {
      // Drop old tables and recreate
      try {
        await _db!.execute('DROP TABLE IF EXISTS message_index');
        await _db!.execute('DROP TABLE IF EXISTS indexed_events');
        await _db!.execute('DROP TABLE IF EXISTS index_meta');
      } catch (_) {}
      debugPrint('[search] Migrating index to schema v$_schemaVersion');
    }

    // FTS5 table for full-text search
    await _db!.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS message_index USING fts5(
        body,
        sender,
        room_id,
        event_id UNINDEXED,
        timestamp UNINDEXED,
        tokenize='unicode61 remove_diacritics 2'
      )
    ''');

    // Separate table to track which event IDs have been indexed.
    // FTS5 UNINDEXED columns can't be efficiently queried, so we
    // use this for fast dedup lookups.
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS indexed_events (
        event_id TEXT PRIMARY KEY
      )
    ''');

    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        query TEXT PRIMARY KEY,
        use_count INTEGER DEFAULT 1,
        last_used_at INTEGER
      )
    ''');

    // Update schema version
    await _db!.insert(
      'schema_version',
      {'version': _schemaVersion},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Start indexing incoming messages from the sync stream.
  void startLiveIndexing() {
    _syncSub = _client.onSync.stream.listen((syncUpdate) {
      _indexSyncEvents(syncUpdate);
    });
  }

  void dispose() {
    _syncSub?.cancel();
    _db?.close();
  }

  /// Index ALL message events from a sync response — not just the last one.
  Future<void> _indexSyncEvents(SyncUpdate sync) async {
    if (_db == null) return;
    final joinedRooms = sync.rooms?.join;
    if (joinedRooms == null) return;

    for (final entry in joinedRooms.entries) {
      final roomId = entry.key;
      final roomData = entry.value;
      final timelineEvents = roomData.timeline?.events;
      if (timelineEvents == null || timelineEvents.isEmpty) continue;

      for (final event in timelineEvents) {
        if (event.type != EventTypes.Message) continue;
        final body = event.content.tryGet<String>('body') ?? '';
        await _indexMessage(
          eventId: event.eventId,
          roomId: roomId,
          sender: event.senderId,
          body: body,
          timestamp: event.originServerTs.millisecondsSinceEpoch,
        );
      }
    }
  }

  Future<void> _indexMessage({
    required String eventId,
    required String roomId,
    required String sender,
    required String body,
    required int timestamp,
  }) async {
    if (_db == null) return;
    if (body.trim().length < 2) return;

    try {
      // Fast dedup via the indexed_events table
      final existing = await _db!.query(
        'indexed_events',
        where: 'event_id = ?',
        whereArgs: [eventId],
        limit: 1,
      );
      if (existing.isNotEmpty) return;

      await _db!.insert('message_index', {
        'body': body,
        'sender': sender,
        'room_id': roomId,
        'event_id': eventId,
        'timestamp': timestamp,
      });
      await _db!.insert(
        'indexed_events',
        {'event_id': eventId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {}
  }

  /// Index a batch of timeline events for a room (backfill).
  /// Called when a room's timeline loads to index historical messages.
  Future<void> indexTimeline(String roomId, List<Event> events) async {
    if (_db == null) return;
    if (events.isEmpty) return;

    // Filter to message events and collect event IDs for dedup check
    final messageEvents = events
        .where((e) => e.type == EventTypes.Message)
        .toList();
    if (messageEvents.isEmpty) return;

    // Batch check which events are already indexed
    final eventIds = messageEvents.map((e) => e.eventId).toList();
    final placeholders = List.filled(eventIds.length, '?').join(',');
    final existing = await _db!.rawQuery(
      'SELECT event_id FROM indexed_events WHERE event_id IN ($placeholders)',
      eventIds,
    );
    final existingIds = existing.map((r) => r['event_id'] as String).toSet();

    // Only insert new events
    final newEvents = messageEvents
        .where((e) => !existingIds.contains(e.eventId))
        .toList();
    if (newEvents.isEmpty) return;

    final batch = _db!.batch();
    for (final event in newEvents) {
      final body = event.body;
      if (body.trim().length < 2) continue;

      batch.insert('message_index', {
        'body': body,
        'sender': event.senderId,
        'room_id': roomId,
        'event_id': event.eventId,
        'timestamp': event.originServerTs.millisecondsSinceEpoch,
      });
      batch.insert(
        'indexed_events',
        {'event_id': event.eventId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Search the local index.
  /// Uses FTS5 MATCH for word-based queries, falls back to LIKE for
  /// URLs and queries with special characters that FTS5 can't tokenize.
  Future<List<SearchResult>> search(
    String query, {
    String? roomId,
    String? sender,
    int limit = 50,
  }) async {
    if (_db == null) return [];
    if (query.trim().isEmpty) return [];

    final trimmed = query.trim();

    // Determine if query needs LIKE fallback (URLs, special chars)
    final needsLikeFallback = trimmed.contains('://') ||
        trimmed.contains('.com') ||
        trimmed.contains('.org') ||
        trimmed.contains('.io') ||
        trimmed.contains('/') ||
        RegExp(r'[^\w\s]').hasMatch(trimmed);

    final conditions = <String>[];
    final args = <dynamic>[];

    if (roomId != null) {
      conditions.add('room_id = ?');
      args.add(roomId);
    }
    if (sender != null) {
      conditions.add('sender = ?');
      args.add(sender);
    }

    final condSql = conditions.isNotEmpty
        ? ' AND ${conditions.join(' AND ')}'
        : '';

    // Try FTS5 MATCH first
    List<Map<String, Object?>> rows = [];
    try {
      final ftsArgs = [trimmed, ...args, limit];
      rows = await _db!.rawQuery('''
        SELECT *, bm25(message_index) as rank
        FROM message_index
        WHERE message_index MATCH ?$condSql
        ORDER BY rank
        LIMIT ?
      ''', ftsArgs);
    } catch (_) {
      // FTS5 query syntax error — fall through to LIKE
    }

    // LIKE fallback for URLs and when FTS5 returns nothing
    if (rows.isEmpty && needsLikeFallback) {
      final likeArgs = ['%$trimmed%', ...args, limit];
      rows = await _db!.rawQuery('''
        SELECT *, 0.0 as rank
        FROM message_index
        WHERE body LIKE ?$condSql
        ORDER BY CAST(timestamp AS INTEGER) DESC
        LIMIT ?
      ''', likeArgs);
    }

    // Deduplicate by event_id
    final seen = <String>{};
    final results = <SearchResult>[];

    for (final row in rows) {
      final eventId = row['event_id'] as String? ?? '';
      if (eventId.isEmpty || !seen.add(eventId)) continue;

      final ts = row['timestamp'] as int? ?? 0;
      final senderId = row['sender'] as String? ?? '';
      final rId = row['room_id'] as String? ?? '';

      // Resolve display names
      final room = _client.getRoomById(rId);
      final roomName = room?.getLocalizedDisplayname() ?? rId;
      final senderName = room
              ?.getParticipants()
              .where((u) => u.id == senderId)
              .firstOrNull
              ?.calcDisplayname() ??
          senderId;

      final bm25 = (row['rank'] as num?)?.toDouble() ?? 0.0;
      final daysSince =
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)).inDays;
      final recencyBoost = 10.0 / (1.0 + daysSince.toDouble());

      results.add(SearchResult(
        eventId: eventId,
        roomId: rId,
        senderId: senderId,
        senderName: senderName,
        roomName: roomName,
        body: row['body'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
        score: bm25.abs() + recencyBoost,
      ));
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  /// Save a search query to history.
  Future<void> saveToHistory(String query) async {
    if (_db == null) return;
    await _db!.insert(
      'search_history',
      {
        'query': query,
        'use_count': 1,
        'last_used_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get recent search history.
  Future<List<String>> getHistory({int limit = 10}) async {
    if (_db == null) return [];
    final rows = await _db!.query(
      'search_history',
      orderBy: 'last_used_at DESC',
      limit: limit,
    );
    return rows.map((r) => r['query'] as String).toList();
  }

  /// Get the total number of indexed messages.
  Future<int> get indexedMessageCount async {
    if (_db == null) return 0;
    final result = await _db!.rawQuery('SELECT COUNT(*) as c FROM message_index');
    return (result.first['c'] as int?) ?? 0;
  }
}

final searchServiceProvider = Provider<SearchService>((ref) {
  final client = ref.watch(matrixServiceProvider).client;
  return SearchService(client ?? Client('dummy'));
});
