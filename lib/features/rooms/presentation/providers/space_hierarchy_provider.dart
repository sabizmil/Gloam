import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../../services/matrix_service.dart';
import 'room_list_provider.dart';

/// A room entry from the server-resolved space hierarchy.
class SpaceRoom {
  final String roomId;
  final String? name;
  final String? topic;
  final Uri? avatarUrl;
  final int numJoinedMembers;
  final String? roomType;
  final String? joinRule;
  final bool isJoined;
  final List<String> viaServers;

  const SpaceRoom({
    required this.roomId,
    this.name,
    this.topic,
    this.avatarUrl,
    this.numJoinedMembers = 0,
    this.roomType,
    this.joinRule,
    this.isJoined = false,
    this.viaServers = const [],
  });

  SpaceRoom copyWith({bool? isJoined}) => SpaceRoom(
        roomId: roomId,
        name: name,
        topic: topic,
        avatarUrl: avatarUrl,
        numJoinedMembers: numJoinedMembers,
        roomType: roomType,
        joinRule: joinRule,
        isJoined: isJoined ?? this.isJoined,
        viaServers: viaServers,
      );

  /// Whether this room can potentially be joined by tapping.
  bool get isJoinable =>
      joinRule == 'public' ||
      joinRule == 'restricted' ||
      joinRule == 'knock' ||
      joinRule == null; // null = unknown, let them try

  /// Whether this room requires an invite (no point tapping).
  bool get isInviteOnly => joinRule == 'invite' || joinRule == 'private';
}

/// Raw hierarchy data from the server — cached, only re-fetches on invalidate.
final _rawSpaceHierarchyProvider =
    FutureProvider.family<List<SpaceRoom>, String>((ref, spaceId) async {
  final client = ref.read(matrixServiceProvider).client;
  if (client == null) return [];

  try {
    // maxDepth not set = unlimited depth, resolves nested sub-spaces fully
    final response = await client.getSpaceHierarchy(spaceId);
    return response.rooms
        .where((r) => r.roomId != spaceId && r.roomType != 'm.space')
        .map((chunk) {
          final domain = chunk.roomId.split(':').last;
          return SpaceRoom(
            roomId: chunk.roomId,
            name: chunk.name,
            topic: chunk.topic,
            avatarUrl: chunk.avatarUrl,
            numJoinedMembers: chunk.numJoinedMembers,
            roomType: chunk.roomType,
            joinRule: chunk.joinRule,
            viaServers: [domain],
          );
        })
        .toList();
  } catch (e) {
    // Fall back to local spaceChildren if server request fails
    final space = client.getRoomById(spaceId);
    if (space == null || !space.isSpace) return [];

    return space.spaceChildren
        .where((c) => c.roomId != null)
        .map((c) {
          final childRoom = client.getRoomById(c.roomId!);
          return SpaceRoom(
            roomId: c.roomId!,
            name: childRoom?.getLocalizedDisplayname(),
            numJoinedMembers: childRoom?.summary.mJoinedMemberCount ?? 0,
            roomType: childRoom
                ?.getState(EventTypes.RoomCreate)
                ?.content
                .tryGet<String>('type'),
          );
        })
        .toList();
  }
});

/// Public provider — combines cached server data with live isJoined state.
/// Re-evaluates isJoined whenever the room list changes (join/leave).
final spaceHierarchyProvider =
    Provider.family<AsyncValue<List<SpaceRoom>>, String>((ref, spaceId) {
  final rawAsync = ref.watch(_rawSpaceHierarchyProvider(spaceId));
  // Watch room list to react to join/leave changes
  final roomListAsync = ref.watch(roomListProvider);

  return rawAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, s) => AsyncValue.error(e, s),
    data: (rooms) {
      final client = ref.read(matrixServiceProvider).client;
      final joinedIds =
          roomListAsync.whenOrNull(data: (list) => list.map((r) => r.roomId).toSet())
          ?? <String>{};

      return AsyncValue.data(
        rooms
            .map((r) => r.copyWith(
                isJoined: client?.getRoomById(r.roomId) != null ||
                    joinedIds.contains(r.roomId)))
            .toList(),
      );
    },
  );
});

/// Look up a room's name from cached hierarchy data.
/// Returns null if not found in any space hierarchy.
final hierarchyRoomNameProvider =
    Provider.family<String?, String>((ref, roomId) {
  final client = ref.read(matrixServiceProvider).client;
  if (client == null) return null;

  // Check each space's hierarchy for this room
  for (final space in client.rooms.where((r) => r.isSpace)) {
    final hierarchy = ref.watch(spaceHierarchyProvider(space.id));
    final name = hierarchy.whenOrNull(
      data: (rooms) {
        final match = rooms.where((r) => r.roomId == roomId).firstOrNull;
        return match?.name;
      },
    );
    if (name != null) return name;
  }
  return null;
});
