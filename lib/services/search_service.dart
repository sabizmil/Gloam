import 'dart:async';

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

    // Create FTS5 table and metadata
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

    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS index_meta (
        room_id TEXT PRIMARY KEY,
        last_indexed_event_id TEXT,
        last_indexed_timestamp INTEGER,
        event_count INTEGER DEFAULT 0
      )
    ''');

    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        query TEXT PRIMARY KEY,
        use_count INTEGER DEFAULT 1,
        last_used_at INTEGER
      )
    ''');
  }

  /// Start indexing incoming messages from the sync stream.
  void startLiveIndexing() {
    _syncSub = _client.onSync.stream.listen((_) => _indexNewMessages());
  }

  void dispose() {
    _syncSub?.cancel();
    _db?.close();
  }

  /// Index any new messages that haven't been indexed yet.
  Future<void> _indexNewMessages() async {
    if (_db == null) return;

    for (final room in _client.rooms) {
      if (room.membership != Membership.join) continue;

      final lastEvent = room.lastEvent;
      if (lastEvent == null) continue;
      if (lastEvent.type != EventTypes.Message) continue;

      // Check if already indexed
      final meta = await _db!.query(
        'index_meta',
        where: 'room_id = ?',
        whereArgs: [room.id],
      );

      final lastIndexedId =
          meta.isNotEmpty ? meta.first['last_indexed_event_id'] as String? : null;

      if (lastIndexedId == lastEvent.eventId) continue;

      // Index this message
      await _indexMessage(
        eventId: lastEvent.eventId,
        roomId: room.id,
        sender: lastEvent.senderId,
        body: lastEvent.body,
        timestamp: lastEvent.originServerTs.millisecondsSinceEpoch,
      );

      // Update metadata
      await _db!.insert(
        'index_meta',
        {
          'room_id': room.id,
          'last_indexed_event_id': lastEvent.eventId,
          'last_indexed_timestamp':
              lastEvent.originServerTs.millisecondsSinceEpoch,
          'event_count': (meta.isNotEmpty
                  ? (meta.first['event_count'] as int? ?? 0)
                  : 0) +
              1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
    // Skip empty or very short messages
    if (body.trim().length < 2) return;

    try {
      await _db!.insert('message_index', {
        'body': body,
        'sender': sender,
        'room_id': roomId,
        'event_id': eventId,
        'timestamp': timestamp,
      });
    } catch (_) {
      // Duplicate or other insert error — ignore
    }
  }

  /// Index a batch of timeline events for a room (backfill).
  Future<void> indexTimeline(String roomId, List<Event> events) async {
    if (_db == null) return;

    final batch = _db!.batch();
    for (final event in events) {
      if (event.type != EventTypes.Message) continue;
      batch.insert(
        'message_index',
        {
          'body': event.body,
          'sender': event.senderId,
          'room_id': roomId,
          'event_id': event.eventId,
          'timestamp': event.originServerTs.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Search the local index.
  Future<List<SearchResult>> search(
    String query, {
    String? roomId,
    String? sender,
    int limit = 50,
  }) async {
    if (_db == null) return [];
    if (query.trim().isEmpty) return [];

    // Build FTS5 query
    var ftsQuery = query.trim();
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

    String sql;
    if (conditions.isEmpty) {
      sql = '''
        SELECT *, bm25(message_index) as rank
        FROM message_index
        WHERE message_index MATCH ?
        ORDER BY rank
        LIMIT ?
      ''';
      args.insertAll(0, [ftsQuery]);
      args.add(limit);
    } else {
      sql = '''
        SELECT *, bm25(message_index) as rank
        FROM message_index
        WHERE message_index MATCH ? AND ${conditions.join(' AND ')}
        ORDER BY rank
        LIMIT ?
      ''';
      args.insertAll(0, [ftsQuery]);
      args.add(limit);
    }

    final rows = await _db!.rawQuery(sql, args);

    return rows.map((row) {
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

      return SearchResult(
        eventId: row['event_id'] as String? ?? '',
        roomId: rId,
        senderId: senderId,
        senderName: senderName,
        roomName: roomName,
        body: row['body'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
        score: bm25.abs() + recencyBoost,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
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
