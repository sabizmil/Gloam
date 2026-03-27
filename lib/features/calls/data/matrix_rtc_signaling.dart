import 'dart:async';

import 'package:matrix/matrix.dart';

/// Handles MatrixRTC signaling: sending and receiving `m.call.member`
/// state events that signal voice channel participation.
///
/// This is the signaling layer — it manages room state events only.
/// Media transport is handled separately by [LivekitMediaManager].
class MatrixRTCSignaling {
  MatrixRTCSignaling({
    required Client client,
    required Room room,
  })  : _client = client,
        _room = room;

  final Client _client;
  final Room _room;

  final _memberships = StreamController<List<CallMembership>>.broadcast();
  StreamSubscription? _stateSub;
  String? _activeMembershipId;

  /// Active participants derived from room state events.
  Stream<List<CallMembership>> get memberships => _memberships.stream;

  /// Current memberships snapshot.
  List<CallMembership> get currentMemberships => _parseMemberships();

  /// Start listening for membership state event changes.
  void startListening() {
    // Emit initial state
    _memberships.add(_parseMemberships());

    // Listen for room state updates via sync
    _stateSub = _client.onSync.stream.listen((_) {
      _memberships.add(_parseMemberships());
    });
  }

  /// Join the voice channel: send our membership state event.
  Future<void> join({
    required String callId,
    required String livekitServiceUrl,
  }) async {
    _activeMembershipId = _generateMembershipId();

    final content = {
      'memberships': [
        {
          'call_id': callId,
          'scope': 'm.room',
          'application': 'm.call',
          'device_id': _client.deviceID,
          'expires': 3600000, // 1 hour in ms
          'foci_active': [
            {
              'type': 'livekit',
              'livekit_service_url': livekitServiceUrl,
            },
          ],
          'membershipID': _activeMembershipId,
        },
      ],
    };

    await _client.setRoomStateWithKey(
      _room.id,
      _callMemberEventType,
      _client.userID!,
      content,
    );

    _memberships.add(_parseMemberships());
  }

  /// Leave the voice channel: clear our membership state event.
  Future<void> leave() async {
    _activeMembershipId = null;

    try {
      await _client.setRoomStateWithKey(
        _room.id,
        _callMemberEventType,
        _client.userID!,
        {'memberships': []},
      );
    } catch (e) {
      Logs().w('Failed to clear membership event on leave', e);
    }

    _memberships.add(_parseMemberships());
  }

  /// Parse all `m.call.member` state events in the room into memberships.
  List<CallMembership> _parseMemberships() {
    final memberships = <CallMembership>[];

    // Get all state events of the call member type
    final states = _room.states[_callMemberEventType];
    if (states == null) return memberships;

    for (final entry in states.entries) {
      final userId = entry.key;
      final event = entry.value;
      final content = event.content;

      final membershipList = content['memberships'];
      if (membershipList is! List || membershipList.isEmpty) continue;

      for (final m in membershipList) {
        if (m is! Map<String, dynamic>) continue;

        // Check expiry — StrippedStateEvent doesn't carry a timestamp,
        // so we rely on the membership's own expires field and the server
        // cleaning up stale events via MSC4140 delayed events.
        // Client-side expiry checking is best-effort.
        final expiresMs = m['expires'] as int? ?? 0;
        if (expiresMs == 0) continue; // No expiry = invalid

        final deviceId = m['device_id'] as String?;
        final membershipId = m['membershipID'] as String?;
        final callId = m['call_id'] as String?;
        final fociActive = m['foci_active'] as List?;

        String? livekitUrl;
        if (fociActive != null && fociActive.isNotEmpty) {
          final focus = fociActive.first;
          if (focus is Map && focus['type'] == 'livekit') {
            livekitUrl = focus['livekit_service_url'] as String?;
          }
        }

        memberships.add(CallMembership(
          userId: userId,
          deviceId: deviceId ?? '',
          membershipId: membershipId ?? '',
          callId: callId ?? '',
          livekitServiceUrl: livekitUrl,
          isLocal: userId == _client.userID &&
              membershipId == _activeMembershipId,
        ));
      }
    }

    return memberships;
  }

  String _generateMembershipId() {
    // UUID-like ID for this participation instance
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${_client.deviceID}_$now';
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _memberships.close();
  }

  /// The unstable event type used by Element X in production.
  static const _callMemberEventType = 'org.matrix.msc3401.call.member';
}

/// A parsed call membership from a room state event.
class CallMembership {
  const CallMembership({
    required this.userId,
    required this.deviceId,
    required this.membershipId,
    required this.callId,
    this.livekitServiceUrl,
    this.isLocal = false,
  });

  final String userId;
  final String deviceId;
  final String membershipId;
  final String callId;
  final String? livekitServiceUrl;
  final bool isLocal;
}
