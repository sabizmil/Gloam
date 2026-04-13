import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Whether this is a dev build (set via --dart-define=IS_DEV=true).
const _isDev = bool.fromEnvironment('IS_DEV');

/// Lightweight HTTP server exposing app state for debugging.
///
/// Only runs in debug mode. Listens on localhost:9999.
/// Query with curl from the terminal to inspect rooms, voice state, etc.
///
/// Content-level endpoints (messages, event payloads) are only available
/// when IS_DEV=true to prevent accidental exposure in production debug builds.
class DebugServer {
  DebugServer({required Client client}) : _client = client;

  final Client _client;
  HttpServer? _server;
  StreamSubscription? _syncSub;
  static final List<String> logs = [];

  /// Rolling buffer of recent Matrix events (last 500).
  static const _maxEvents = 500;
  final List<Map<String, dynamic>> _eventBuffer = [];

  /// Registry for active TimelineNotifiers — populated by the provider.
  /// Key is roomId, value is the notifier's debugState getter.
  static final Map<String, Map<String, dynamic> Function()> timelineRegistry =
      {};

  /// Link preview cache telemetry. Incremented by the provider.
  static final LinkPreviewStats linkPreviewStats = LinkPreviewStats();

  /// Encrypted media cache telemetry. Incremented by the provider.
  static final MediaCacheStats mediaStats = MediaCacheStats();

  /// Start the debug server. No-op in release mode.
  Future<void> start({int port = 9999}) async {
    if (!kDebugMode) return;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      debugPrint('[debug-server] listening on http://localhost:$port');
      _server!.listen(_handleRequest);

      // Tap into the sync stream to capture events
      _syncSub = _client.onSync.stream.listen(_captureSyncEvents);
    } catch (e) {
      debugPrint('[debug-server] failed to start: $e');
    }
  }

  /// Capture events from each sync response into the rolling buffer.
  void _captureSyncEvents(SyncUpdate sync) {
    // Room timeline events (join)
    final joinRooms = sync.rooms?.join;
    if (joinRooms != null) {
      for (final entry in joinRooms.entries) {
        final roomId = entry.key;
        final room = _client.getRoomById(roomId);
        final roomName = room?.getLocalizedDisplayname() ?? roomId;

        // Timeline events
        for (final event in entry.value.timeline?.events ?? <MatrixEvent>[]) {
          _pushEvent(event, roomId, roomName, 'timeline');
        }

        // State events
        for (final event in entry.value.state ?? <MatrixEvent>[]) {
          _pushEvent(event, roomId, roomName, 'state');
        }
      }
    }

    // Invite events
    final inviteRooms = sync.rooms?.invite;
    if (inviteRooms != null) {
      for (final entry in inviteRooms.entries) {
        final roomId = entry.key;
        for (final event in entry.value.inviteState ?? <StrippedStateEvent>[]) {
          _eventBuffer.add({
            'ts': DateTime.now().toIso8601String(),
            'source': 'invite',
            'roomId': roomId,
            'roomName': roomId,
            'type': event.type,
            'stateKey': event.stateKey,
            'sender': event.senderId,
            'content': event.content,
          });
        }
      }
    }

    // Leave events
    final leaveRooms = sync.rooms?.leave;
    if (leaveRooms != null) {
      for (final entry in leaveRooms.entries) {
        final roomId = entry.key;
        for (final event
            in entry.value.timeline?.events ?? <MatrixEvent>[]) {
          _pushEvent(event, roomId, roomId, 'leave');
        }
      }
    }

    // Trim buffer
    while (_eventBuffer.length > _maxEvents) {
      _eventBuffer.removeAt(0);
    }
  }

  void _pushEvent(
      MatrixEvent event, String roomId, String roomName, String source) {
    _eventBuffer.add({
      'ts': event.originServerTs.toIso8601String(),
      'eventId': event.eventId,
      'source': source,
      'roomId': roomId,
      'roomName': roomName,
      'type': event.type,
      'sender': event.senderId,
      'stateKey': event.stateKey,
      'content': event.content,
      'unsigned': event.unsigned,
    });
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final segments = request.uri.pathSegments;
    final params = request.uri.queryParameters;

    try {
      final result = switch (path) {
        '/debug/rooms' => _rooms(),
        '/debug/voice' => _voice(),
        '/debug/user' => _user(),
        '/debug/sync' => _sync(),
        '/debug/spaces' => _spaces(),
        '/debug/logs' => {'logs': logs},
        '/debug/hierarchy' => await _hierarchy(),
        '/debug/logs/clear' => () {
            logs.clear();
            return {'cleared': true};
          }(),
        '/debug/timelines' => Map.fromEntries(
            timelineRegistry.entries.map((e) => MapEntry(e.key, e.value()))),
        '/debug/link-preview-stats' => linkPreviewStats.toJson(),
        '/debug/media-stats' => mediaStats.toJson(),

        // --- Content-level endpoints (dev-only) ---
        '/debug/events' => _isDev
            ? _events(params)
            : {'error': 'Content endpoints require IS_DEV=true'},
        '/debug/invites' => _isDev
            ? _invites()
            : {'error': 'Content endpoints require IS_DEV=true'},

        _ when _isDev &&
            segments.length == 4 &&
            segments[0] == 'debug' &&
            segments[1] == 'room' &&
            segments[3] == 'messages' =>
          _roomMessages(Uri.decodeComponent(segments[2]), params),
        _ when _isDev &&
            segments.length == 3 &&
            segments[0] == 'debug' &&
            segments[1] == 'event' =>
          _singleEvent(Uri.decodeComponent(segments[2])),
        _ when segments.length == 3 &&
            segments[0] == 'debug' &&
            segments[1] == 'room' =>
          _roomDetail(Uri.decodeComponent(segments[2])),

        _ => {'error': 'Unknown endpoint', 'endpoints': _endpoints()},
      };

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(const JsonEncoder.withIndent('  ').convert(result));
    } catch (e, st) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': '$e', 'stack': '$st'}));
    }

    await request.response.close();
  }

  List<String> _endpoints() => [
        'GET /debug/rooms              — all rooms summary',
        'GET /debug/room/{id}          — room detail + state events',
        'GET /debug/voice              — voice connection state',
        'GET /debug/user               — current user info',
        'GET /debug/sync               — sync status',
        'GET /debug/spaces             — space hierarchy',
        'GET /debug/timelines          — active timeline notifiers',
        'GET /debug/link-preview-stats — link preview cache hit/miss counters',
        'GET /debug/media-stats        — encrypted media cache hit/miss counters',
        'GET /debug/logs               — app logs',
        'GET /debug/logs/clear         — clear logs',
        if (_isDev) ...[
          'GET /debug/events            — recent events (?limit=N&sender=X&type=X&room=X)',
          'GET /debug/room/{id}/messages — message content in room (?limit=N)',
          'GET /debug/invites           — pending + recent invites',
          'GET /debug/event/{id}        — single event by ID',
        ],
      ];

  // ---------------------------------------------------------------------------
  // Core endpoints
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _rooms() {
    final rooms = _client.rooms;
    return rooms.map((r) {
      final createEvent = r.getState(EventTypes.RoomCreate);
      final roomType = createEvent?.content['type'];

      return {
        'id': r.id,
        'name': r.getLocalizedDisplayname(),
        'membership': r.membership.name,
        'isDirect': r.isDirectChat,
        'directChatMatrixID': r.directChatMatrixID,
        'encrypted': r.encrypted,
        'memberCount': r.summary.mJoinedMemberCount ?? 0,
        'roomType': roomType,
        'topic': r.topic,
        'tags': r.tags.keys.toList(),
        'unreadCount': r.notificationCount,
        'lastEvent': r.lastEvent?.type,
        'lastEventBody': r.lastEvent?.body,
        'lastEventTime': r.lastEvent?.originServerTs.toIso8601String(),
        'isSpace': r.isSpace,
        'spaceChildren': r.isSpace
            ? r.spaceChildren.map((c) => c.roomId).toList()
            : null,
        'stateEventTypes': _stateEventTypes(r),
      };
    }).toList()
      ..sort((a, b) => (b['lastEventTime'] as String? ?? '')
          .compareTo(a['lastEventTime'] as String? ?? ''));
  }

  Map<String, dynamic> _roomDetail(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null) return {'error': 'Room not found', 'roomId': roomId};

    final createEvent = _r(room, EventTypes.RoomCreate);

    return {
      'id': room.id,
      'name': room.getLocalizedDisplayname(),
      'membership': room.membership.name,
      'isDirect': room.isDirectChat,
      'directChatMatrixID': room.directChatMatrixID,
      'encrypted': room.encrypted,
      'topic': room.topic,
      'roomType': createEvent?['type'],
      'tags': room.tags.keys.toList(),
      'memberCount': room.summary.mJoinedMemberCount ?? 0,
      'ownPowerLevel': room.ownPowerLevel,
      'isSpace': room.isSpace,
      'stateEvents': _allStateEvents(room),
      'members': _members(room),
      'spaceChildren': room.isSpace
          ? room.spaceChildren
              .map((c) => {
                    'roomId': c.roomId,
                    'suggested': c.suggested,
                  })
              .toList()
          : null,
    };
  }

  Map<String, dynamic> _voice() {
    final voiceRooms = <Map<String, dynamic>>[];

    for (final room in _client.rooms) {
      final callMembers =
          room.states['org.matrix.msc3401.call.member'] ?? {};
      if (callMembers.isNotEmpty) {
        final participants = <Map<String, dynamic>>[];
        for (final entry in callMembers.entries) {
          final memberships = entry.value.content['memberships'];
          if (memberships is List && memberships.isNotEmpty) {
            participants.add({
              'userId': entry.key,
              'memberships': memberships,
            });
          }
        }
        if (participants.isNotEmpty) {
          voiceRooms.add({
            'roomId': room.id,
            'roomName': room.getLocalizedDisplayname(),
            'participants': participants,
          });
        }
      }
    }

    return {
      'activeVoiceRooms': voiceRooms,
      'myUserId': _client.userID,
      'myDeviceId': _client.deviceID,
    };
  }

  Map<String, dynamic> _user() {
    return {
      'userId': _client.userID,
      'deviceId': _client.deviceID,
      'deviceName': _client.deviceName,
      'homeserver': _client.homeserver?.toString(),
      'isLogged': _client.isLogged(),
      'encryptionEnabled': _client.encryptionEnabled,
      'roomCount': _client.rooms.length,
      'directChatCount':
          _client.rooms.where((r) => r.isDirectChat).length,
      'spaceCount': _client.rooms.where((r) => r.isSpace).length,
    };
  }

  Map<String, dynamic> _sync() {
    return {
      'prevBatch': _client.prevBatch != null ? '(set)' : null,
      'isLogged': _client.isLogged(),
      'homeserver': _client.homeserver?.toString(),
    };
  }

  List<Map<String, dynamic>> _spaces() {
    return _client.rooms.where((r) => r.isSpace).map((space) {
      return {
        'id': space.id,
        'name': space.getLocalizedDisplayname(),
        'children': space.spaceChildren.map((c) {
          final childRoom = _client.getRoomById(c.roomId ?? '');
          return {
            'roomId': c.roomId,
            'name': childRoom?.getLocalizedDisplayname(),
            'roomType': childRoom != null
                ? childRoom
                    .getState(EventTypes.RoomCreate)
                    ?.content['type']
                : null,
            'suggested': c.suggested,
          };
        }).toList(),
      };
    }).toList();
  }

  Future<Map<String, dynamic>> _hierarchy() async {
    final results = <String, dynamic>{};
    for (final space in _client.rooms.where((r) => r.isSpace)) {
      try {
        final resp = await _client.getSpaceHierarchy(space.id, maxDepth: 10);
        results[space.getLocalizedDisplayname()] = resp.rooms.map((r) => {
              'roomId': r.roomId,
              'name': r.name,
              'roomType': r.roomType,
              'numJoinedMembers': r.numJoinedMembers,
              'joinRule': r.joinRule,
            }).toList();
      } catch (e) {
        results[space.getLocalizedDisplayname()] = {'error': '$e'};
      }
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // Content-level endpoints (dev-only)
  // ---------------------------------------------------------------------------

  /// Recent events from the rolling buffer with optional filters.
  ///
  /// Query params:
  ///   ?limit=N       — max events to return (default 50)
  ///   ?sender=@user  — filter by sender
  ///   ?type=m.room.message — filter by event type
  ///   ?room=!roomId  — filter by room ID
  Map<String, dynamic> _events(Map<String, String> params) {
    final limit = int.tryParse(params['limit'] ?? '') ?? 50;
    final sender = params['sender'];
    final type = params['type'];
    final roomId = params['room'];

    var events = _eventBuffer.reversed.toList();

    if (sender != null) {
      events = events.where((e) => e['sender'] == sender).toList();
    }
    if (type != null) {
      events = events.where((e) => e['type'] == type).toList();
    }
    if (roomId != null) {
      events = events.where((e) => e['roomId'] == roomId).toList();
    }

    final result = events.take(limit).toList();

    return {
      'count': result.length,
      'totalBuffered': _eventBuffer.length,
      'filters': {
        if (sender != null) 'sender': sender,
        if (type != null) 'type': type,
        if (roomId != null) 'room': roomId,
      },
      'events': result,
    };
  }

  /// Messages in a specific room from the event buffer.
  Map<String, dynamic> _roomMessages(
      String roomId, Map<String, String> params) {
    final room = _client.getRoomById(roomId);
    if (room == null) return {'error': 'Room not found', 'roomId': roomId};

    final limit = int.tryParse(params['limit'] ?? '') ?? 50;

    // Get message events from the buffer for this room
    final messages = _eventBuffer.reversed
        .where((e) =>
            e['roomId'] == roomId && e['type'] == 'm.room.message')
        .take(limit)
        .toList();

    // Get all events (any type) from the buffer for this room
    final allEvents = _eventBuffer.reversed
        .where((e) => e['roomId'] == roomId)
        .take(limit)
        .toList();

    return {
      'roomId': roomId,
      'roomName': room.getLocalizedDisplayname(),
      'encrypted': room.encrypted,
      'lastEvent': room.lastEvent?.body,
      'lastEventType': room.lastEvent?.type,
      'messages': messages,
      'allEvents': allEvents,
    };
  }

  /// Pending and recent invite events.
  Map<String, dynamic> _invites() {
    // Current pending invites from the client
    final pendingInvites = _client.rooms
        .where((r) => r.membership == Membership.invite)
        .map((r) {
      final inviter = r.getState(EventTypes.RoomMember, _client.userID ?? '');
      return {
        'roomId': r.id,
        'roomName': r.getLocalizedDisplayname(),
        'isSpace': r.isSpace,
        'isDirect': r.isDirectChat,
        'inviter': inviter?.senderId,
        'inviterName': inviter?.content['displayname'],
        'ts': (inviter is MatrixEvent) ? inviter.originServerTs.toIso8601String() : null,
        'processed': false,
      };
    }).toList();

    // Recent invite events from the buffer
    final recentInviteEvents = _eventBuffer.reversed
        .where((e) => e['source'] == 'invite')
        .take(20)
        .toList();

    return {
      'pending': pendingInvites,
      'recentFromBuffer': recentInviteEvents,
    };
  }

  /// Look up a single event by ID from the buffer.
  Map<String, dynamic> _singleEvent(String eventId) {
    final event = _eventBuffer.firstWhere(
      (e) => e['eventId'] == eventId,
      orElse: () => <String, dynamic>{},
    );

    if (event.isEmpty) {
      return {'error': 'Event not found in buffer', 'eventId': eventId};
    }

    return event;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Get the content of a state event by type.
  Map<String, dynamic>? _r(Room room, String eventType) {
    final event = room.getState(eventType);
    return event?.content;
  }

  /// List all state event types present in a room.
  List<String> _stateEventTypes(Room room) {
    return room.states.keys.toList()..sort();
  }

  /// Dump all state events in a room.
  Map<String, dynamic> _allStateEvents(Room room) {
    final result = <String, dynamic>{};
    for (final typeEntry in room.states.entries) {
      final type = typeEntry.key;
      final stateKeys = <String, dynamic>{};
      for (final skEntry in typeEntry.value.entries) {
        stateKeys[skEntry.key] = skEntry.value.content;
      }
      result[type] = stateKeys;
    }
    return result;
  }

  /// List room members with their power levels and display names.
  List<Map<String, dynamic>> _members(Room room) {
    final memberStates = room.states[EventTypes.RoomMember] ?? {};
    return memberStates.entries.map((e) {
      final content = e.value.content;
      return {
        'userId': e.key,
        'displayName': content['displayname'],
        'membership': content['membership'],
        'avatarUrl': content['avatar_url'],
        'powerLevel': room.getPowerLevelByUserId(e.key),
      };
    }).toList();
  }

  /// Stop the debug server.
  Future<void> dispose() async {
    await _syncSub?.cancel();
    await _server?.close();
    _server = null;
  }
}

class LinkPreviewStats {
  int hits = 0;
  int staleHits = 0;
  int misses = 0;
  int fetches = 0;
  int failures = 0;

  Map<String, dynamic> toJson() => {
        'hits': hits,
        'stale_hits': staleHits,
        'misses': misses,
        'fetches': fetches,
        'failures': failures,
      };
}

class MediaCacheStats {
  int hits = 0;
  int misses = 0;
  int fetches = 0;

  Map<String, dynamic> toJson() => {
        'hits': hits,
        'misses': misses,
        'fetches': fetches,
      };
}
