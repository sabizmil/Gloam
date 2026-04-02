import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../../services/matrix_service.dart';

/// A user who is "following" the conversation — their read receipt
/// matches the room's latest event.
class FollowingUser {
  final String userId;
  final String displayName;
  final Uri? avatarUrl;
  final DateTime lastReadTs;

  const FollowingUser({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.lastReadTs,
  });
}

/// Watches room receipt state and emits a list of users whose latest
/// read receipt matches the room's most recent event.
class FollowingNotifier extends StateNotifier<List<FollowingUser>> {
  final Client _client;
  final String _roomId;
  StreamSubscription? _syncSub;

  FollowingNotifier(this._client, this._roomId) : super([]) {
    _rebuild();
    _syncSub = _client.onSync.stream.listen((_) => _rebuild());
  }

  Room? get _room => _client.getRoomById(_roomId);

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  void _rebuild() {
    final room = _room;
    if (room == null) {
      state = [];
      return;
    }

    final myUserId = _client.userID;
    final latestEventId = room.lastEvent?.eventId;
    if (latestEventId == null) {
      state = [];
      return;
    }

    final otherReceipts = room.receiptState.global.otherUsers;
    final followers = <FollowingUser>[];

    for (final entry in otherReceipts.entries) {
      final userId = entry.key;
      final receipt = entry.value;

      // Skip self
      if (userId == myUserId) continue;

      // User's latest receipt matches the room's latest event = following
      if (receipt.eventId == latestEventId) {
        // Only include users who are actually online
        final presence = _client.presences[userId];
        final isOnline = presence?.currentlyActive == true ||
            presence?.presence == PresenceType.online;
        if (!isOnline) continue;

        final user = room.unsafeGetUserFromMemoryOrFallback(userId);
        followers.add(FollowingUser(
          userId: userId,
          displayName: user.calcDisplayname(),
          avatarUrl: user.avatarUrl,
          lastReadTs: receipt.timestamp,
        ));
      }
    }

    // Sort by most recent read first
    followers.sort((a, b) => b.lastReadTs.compareTo(a.lastReadTs));
    state = followers;
  }
}

/// Family provider — one per room.
final followingProvider =
    StateNotifierProvider.family<FollowingNotifier, List<FollowingUser>, String>(
  (ref, roomId) {
    final client = ref.watch(matrixServiceProvider).client;
    if (client == null) {
      return FollowingNotifier(Client('dummy'), roomId);
    }
    return FollowingNotifier(client, roomId);
  },
);
