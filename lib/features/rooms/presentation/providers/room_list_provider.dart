import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../../services/matrix_service.dart';

/// Lightweight room model for the room list — avoids leaking SDK types to UI.
class RoomListItem {
  final String roomId;
  final String displayName;
  final Uri? avatarUrl;
  final String? lastMessagePreview;
  final String? lastMessageSender;
  final DateTime? lastMessageTimestamp;
  final int unreadCount;
  final int mentionCount;
  final bool isEncrypted;
  final bool isDirect;

  const RoomListItem({
    required this.roomId,
    required this.displayName,
    this.avatarUrl,
    this.lastMessagePreview,
    this.lastMessageSender,
    this.lastMessageTimestamp,
    this.unreadCount = 0,
    this.mentionCount = 0,
    this.isEncrypted = false,
    this.isDirect = false,
  });
}

/// Transforms SDK rooms into [RoomListItem]s, sorted by recent activity.
List<RoomListItem> _buildRoomList(Client client) {
  final rooms = client.rooms.where((r) => r.membership == Membership.join).toList();

  // Sort by last event timestamp, descending
  rooms.sort((a, b) {
    final aTime = a.lastEvent?.originServerTs ?? DateTime(0);
    final bTime = b.lastEvent?.originServerTs ?? DateTime(0);
    return bTime.compareTo(aTime);
  });

  return rooms.map((room) {
    final lastEvent = room.lastEvent;
    String? preview;
    String? sender;

    if (lastEvent != null) {
      sender = lastEvent.senderFromMemoryOrFallback.calcDisplayname();
      if (lastEvent.type == EventTypes.Encrypted) {
        preview = 'Encrypted message';
      } else if (lastEvent.type == EventTypes.Message) {
        preview = lastEvent.body;
      } else {
        preview = lastEvent.type;
      }
    }

    // Self-DM: the SDK filters out the current user from heroes,
    // leaving an empty display name and unreliable avatar.
    final isSelfDM =
        room.isDirectChat && room.directChatMatrixID == client.userID;
    final String displayName;
    final Uri? avatarUrl;
    if (isSelfDM) {
      final self = room.unsafeGetUserFromMemoryOrFallback(client.userID!);
      displayName = self.calcDisplayname();
      avatarUrl = self.avatarUrl;
    } else {
      displayName = room.getLocalizedDisplayname();
      avatarUrl = room.avatar;
    }

    return RoomListItem(
      roomId: room.id,
      displayName: displayName,
      avatarUrl: avatarUrl,
      lastMessagePreview: preview,
      lastMessageSender: sender,
      lastMessageTimestamp: lastEvent?.originServerTs,
      unreadCount: room.notificationCount,
      mentionCount: room.highlightCount,
      isEncrypted: room.encrypted,
      isDirect: room.isDirectChat,
    );
  }).toList();
}

/// Stream-based provider that rebuilds when the sync updates rooms.
final roomListProvider = StreamProvider<List<RoomListItem>>((ref) async* {
  final matrixService = ref.watch(matrixServiceProvider);
  final client = matrixService.client;
  if (client == null) {
    yield [];
    return;
  }

  // Emit initial state
  yield _buildRoomList(client);

  // Re-emit on every sync update
  await for (final _ in client.onSync.stream) {
    yield _buildRoomList(client);
  }
});
