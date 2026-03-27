import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../services/matrix_service.dart';

/// All data needed to render the user profile modal.
class UserProfileData {
  const UserProfileData({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.homeserver,
    this.powerLevel,
    this.roleLabel,
    this.presence,
    this.mutualRooms = const [],
    this.existingDmId,
  });

  final String userId;
  final String displayName;
  final Uri? avatarUrl;
  final String homeserver;
  final int? powerLevel;
  final String? roleLabel;
  final String? presence; // 'online', 'offline', 'unavailable', or null
  final List<MutualRoom> mutualRooms;
  final String? existingDmId;
}

class MutualRoom {
  const MutualRoom({required this.id, required this.name});
  final String id;
  final String name;
}

/// Fetches profile data for a user in the context of a room.
///
/// [param] is "userId|roomId" concatenated (family providers need a single key).
final userProfileProvider =
    FutureProvider.family<UserProfileData, String>((ref, param) async {
  final parts = param.split('|');
  final userId = parts[0];
  final roomId = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;

  final client = ref.read(matrixServiceProvider).client;
  if (client == null) throw Exception('Not logged in');

  // Display name + avatar — try room member state first (fast, cached),
  // fall back to server profile fetch
  String displayName = userId.split(':').first.substring(1);
  Uri? avatarUrl;

  if (roomId != null) {
    final room = client.getRoomById(roomId);
    if (room != null) {
      final user = room.unsafeGetUserFromMemoryOrFallback(userId);
      displayName = user.calcDisplayname();
      avatarUrl = user.avatarUrl;
    }
  }

  // If we didn't get a good name from the room, try the server
  if (displayName == userId.split(':').first.substring(1)) {
    try {
      final profile = await client.getProfileFromUserId(userId);
      if (profile.displayName != null) displayName = profile.displayName!;
      avatarUrl ??= profile.avatarUrl;
    } catch (_) {
      // Server might not respond — use what we have
    }
  }

  // Power level from room context
  int? powerLevel;
  String? roleLabel;
  if (roomId != null) {
    final room = client.getRoomById(roomId);
    if (room != null) {
      powerLevel = room.getPowerLevelByUserId(userId);
      roleLabel = switch (powerLevel) {
        100 => 'Admin',
        >= 50 => 'Moderator',
        > 0 => 'Privileged',
        _ => 'Member',
      };
    }
  }

  // Mutual rooms
  final mutualRooms = <MutualRoom>[];
  for (final room in client.rooms) {
    if (room.membership != Membership.join) continue;
    if (room.isDirectChat) continue; // Skip DMs from mutual list
    // Check if user is a member — use states map for efficiency
    final memberStates = room.states[EventTypes.RoomMember];
    if (memberStates != null && memberStates.containsKey(userId)) {
      final membership = memberStates[userId]?.content['membership'];
      if (membership == 'join') {
        mutualRooms.add(MutualRoom(
          id: room.id,
          name: room.getLocalizedDisplayname(),
        ));
      }
    }
  }

  // Existing DM
  final existingDmId = client.getDirectChatFromUserId(userId);

  // Presence
  String? presence;
  try {
    final p = client.presences[userId];
    if (p != null) {
      presence = p.currentlyActive == true ? 'online' : 'offline';
    }
  } catch (_) {}

  // Homeserver
  final homeserver = userId.contains(':')
      ? userId.split(':').last
      : 'unknown';

  return UserProfileData(
    userId: userId,
    displayName: displayName,
    avatarUrl: avatarUrl,
    homeserver: homeserver,
    powerLevel: powerLevel,
    roleLabel: roleLabel,
    presence: presence,
    mutualRooms: mutualRooms,
    existingDmId: existingDmId,
  );
});
