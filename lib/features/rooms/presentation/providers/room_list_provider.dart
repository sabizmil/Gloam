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
  final bool isInvite;
  final String? inviterId;
  final String? inviterName;
  final String pushRuleState; // 'notify', 'mentionsOnly', 'dontNotify'

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
    this.isInvite = false,
    this.inviterId,
    this.inviterName,
    this.pushRuleState = 'mentionsOnly',
  });

  bool get isMuted => pushRuleState == 'dontNotify';
  bool get isNotifyAll => pushRuleState == 'notify';

  RoomListItem withDisplayName(String name) => RoomListItem(
        roomId: roomId,
        displayName: name,
        avatarUrl: avatarUrl,
        lastMessagePreview: lastMessagePreview,
        lastMessageSender: lastMessageSender,
        lastMessageTimestamp: lastMessageTimestamp,
        unreadCount: unreadCount,
        mentionCount: mentionCount,
        isEncrypted: isEncrypted,
        isDirect: isDirect,
        isInvite: isInvite,
        inviterId: inviterId,
        inviterName: inviterName,
        pushRuleState: pushRuleState,
      );
}

/// Transforms SDK rooms into [RoomListItem]s, sorted by recent activity.
/// Includes both joined rooms and pending invites.
List<RoomListItem> _buildRoomList(Client client) {
  final rooms = client.rooms
      .where((r) =>
          r.membership == Membership.join ||
          r.membership == Membership.invite)
      .toList();

  // Sort: invites first, then by last event timestamp descending
  rooms.sort((a, b) {
    // Invites always on top
    if (a.membership == Membership.invite && b.membership != Membership.invite) return -1;
    if (b.membership == Membership.invite && a.membership != Membership.invite) return 1;

    final aTime = a.lastEvent?.originServerTs ?? DateTime(0);
    final bTime = b.lastEvent?.originServerTs ?? DateTime(0);
    return bTime.compareTo(aTime);
  });

  return rooms.map((room) {
    final isInvite = room.membership == Membership.invite;

    final lastEvent = room.lastEvent;
    String? preview;
    String? sender;

    if (lastEvent != null && !isInvite) {
      sender = lastEvent.senderFromMemoryOrFallback.calcDisplayname();
      if (lastEvent.type == EventTypes.Encrypted) {
        preview = 'Encrypted message';
      } else if (lastEvent.type == EventTypes.Message) {
        preview = lastEvent.body;
      } else {
        preview = lastEvent.type;
      }
    }

    // Resolve inviter for invite rooms
    String? inviterId;
    String? inviterName;
    if (isInvite) {
      // The membership event for our user was sent by the inviter
      final myMemberEvent =
          room.getState(EventTypes.RoomMember, client.userID!);
      if (myMemberEvent != null) {
        inviterId = myMemberEvent.senderId;
        final inviter =
            room.unsafeGetUserFromMemoryOrFallback(inviterId);
        inviterName = inviter.calcDisplayname();
      }
    }

    // Self-DM: the SDK filters out the current user from heroes,
    // leaving an empty display name and unreliable avatar.
    final isSelfDM =
        room.isDirectChat && room.directChatMatrixID == client.userID;
    final String displayName;
    final Uri? avatarUrl;
    if (isInvite && room.isDirectChat && inviterName != null) {
      // DM invite: show the inviter's name
      displayName = inviterName;
      final inviter =
          room.unsafeGetUserFromMemoryOrFallback(inviterId!);
      avatarUrl = inviter.avatarUrl;
    } else if (isSelfDM) {
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
      isInvite: isInvite,
      inviterId: inviterId,
      inviterName: inviterName,
      pushRuleState: isInvite ? 'notify' : room.pushRuleState.name,
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

/// Count of pending invites — for badge display.
final inviteCountProvider = Provider<int>((ref) {
  final roomsAsync = ref.watch(roomListProvider);
  return roomsAsync.when(
    data: (rooms) => rooms.where((r) => r.isInvite).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});
