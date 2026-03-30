import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Lightweight HTTP server exposing app state for debugging.
///
/// Only runs in debug mode. Listens on localhost:9999.
/// Query with curl from the terminal to inspect rooms, voice state, etc.
class DebugServer {
  DebugServer({required Client client}) : _client = client;

  final Client _client;
  HttpServer? _server;
  static final List<String> logs = [];

  /// Start the debug server. No-op in release mode.
  Future<void> start({int port = 9999}) async {
    if (!kDebugMode) return;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      debugPrint('[debug-server] listening on http://localhost:$port');
      _server!.listen(_handleRequest);
    } catch (e) {
      debugPrint('[debug-server] failed to start: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final segments = request.uri.pathSegments;

    try {
      final result = switch (path) {
        '/debug/rooms' => _rooms(),
        '/debug/voice' => _voice(),
        '/debug/user' => _user(),
        '/debug/sync' => _sync(),
        '/debug/spaces' => _spaces(),
        '/debug/logs' => {'logs': logs},
        '/debug/hierarchy' => await _hierarchy(),
        '/debug/logs/clear' => () { logs.clear(); return {'cleared': true}; }(),
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
        'GET /debug/rooms         — all rooms summary',
        'GET /debug/room/{id}     — room detail + state events',
        'GET /debug/voice         — voice connection state',
        'GET /debug/user          — current user info',
        'GET /debug/sync          — sync status',
        'GET /debug/spaces        — space hierarchy',
      ];

  // ---------------------------------------------------------------------------
  // Endpoints
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

    final createEvent = r(room, EventTypes.RoomCreate);

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
    // Scan all rooms for m.rtc.member or call.member state events
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
  // Helpers
  // ---------------------------------------------------------------------------

  /// Get the content of a state event by type.
  Map<String, dynamic>? r(Room room, String eventType) {
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
    await _server?.close();
    _server = null;
  }
}
