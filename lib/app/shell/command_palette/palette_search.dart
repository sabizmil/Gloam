import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../features/chat/presentation/providers/timeline_provider.dart';
import '../../../services/matrix_service.dart';

/// A message result from local-cache search.
class MessageResult {
  const MessageResult({
    required this.event,
    required this.room,
    required this.snippet,
  });

  final Event event;
  final Room room;
  final String snippet;
}

/// A member result — a user discovered through palette member search.
/// [contextRoom] is the best room to navigate to when this result is opened.
class MemberResult {
  const MemberResult({
    required this.userId,
    required this.displayName,
    required this.contextRoom,
  });

  final String userId;
  final String displayName;
  final Room contextRoom;
}

/// Driven by the dialog after ~150ms debounce to avoid scanning timelines on
/// every keystroke. Empty string = no message search performed.
final paletteMessageQueryProvider = StateProvider<String>((_) => '');

/// Searches local timeline cache (last ~500 events per joined room) for
/// messages whose body contains the query (case-insensitive).
///
/// Caveats:
/// - Only searches what's in the local Matrix database — rooms you've
///   never opened may have minimal cached history.
/// - Limited to ~30 most-recent rooms to keep scans fast on heavy accounts.
/// - Future work: a real client-side full-text index over decrypted events.
final paletteMessageResultsProvider =
    FutureProvider<List<MessageResult>>((ref) async {
  final query = ref.watch(paletteMessageQueryProvider).trim();
  if (query.length < 2) return const [];
  final client = ref.read(matrixServiceProvider).client;
  if (client == null) return const [];

  final lower = query.toLowerCase();

  // Sort joined rooms by recency, scan top 30 only.
  final rooms = client.rooms
      .where((r) => r.membership == Membership.join)
      .toList()
    ..sort((a, b) => b.latestEventReceivedTime
        .compareTo(a.latestEventReceivedTime));
  final scanRooms = rooms.take(30).toList();

  final results = <MessageResult>[];
  for (final room in scanRooms) {
    List<Event> events;
    try {
      events = await client.database?.getEventList(room, limit: 500) ??
          const <Event>[];
    } catch (_) {
      continue;
    }
    for (final event in events) {
      if (event.type != EventTypes.Message) continue;
      final body = event.text;
      if (body.isEmpty) continue;
      if (!body.toLowerCase().contains(lower)) continue;
      results.add(MessageResult(
        event: event,
        room: room,
        snippet: _snippet(body, lower),
      ));
    }
  }

  // Sort newest first, cap total.
  results.sort((a, b) =>
      b.event.originServerTs.compareTo(a.event.originServerTs));
  return results.take(40).toList();
});

String _snippet(String body, String lowerQuery) {
  final idx = body.toLowerCase().indexOf(lowerQuery);
  if (idx < 0) return body.length > 80 ? '${body.substring(0, 80)}…' : body;
  final start = (idx - 20).clamp(0, body.length);
  final end = (idx + lowerQuery.length + 60).clamp(0, body.length);
  final prefix = start > 0 ? '…' : '';
  final suffix = end < body.length ? '…' : '';
  return '$prefix${body.substring(start, end)}$suffix'
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Members of: (current room) ∪ (all 1:1 DMs) ∪ (any joined room ≤4 members).
/// Excludes the local user. Deduplicated by userId; contextRoom prefers a DM.
List<MemberResult> searchMembers(Client client, String query) {
  if (query.length < 2) return const [];
  final lower = query.toLowerCase();
  final myId = client.userID;

  // Build candidate rooms.
  final roomScores = <Room, int>{};
  for (final room in client.rooms) {
    if (room.membership != Membership.join) continue;
    if (room.isDirectChat) {
      roomScores[room] = 0; // DM = highest priority context
    } else if (room.summary.mJoinedMemberCount != null &&
        room.summary.mJoinedMemberCount! <= 4) {
      roomScores[room] = 1;
    }
  }

  final byUser = <String, MemberResult>{};
  for (final entry in roomScores.entries) {
    final room = entry.key;
    for (final user in room.getParticipants()) {
      if (user.id == myId) continue;
      final name = user.displayName?.isNotEmpty == true
          ? user.displayName!
          : user.id;
      if (!name.toLowerCase().contains(lower) &&
          !user.id.toLowerCase().contains(lower)) {
        continue;
      }
      // Prefer earlier (lower-score) context room.
      final existing = byUser[user.id];
      if (existing == null ||
          (roomScores[existing.contextRoom] ?? 99) > entry.value) {
        byUser[user.id] = MemberResult(
          userId: user.id,
          displayName: name,
          contextRoom: room,
        );
      }
    }
  }
  return byUser.values.toList()
    ..sort((a, b) => a.displayName.compareTo(b.displayName));
}

/// Convenience: opens a room (or finds the DM with this member and opens it).
void openMember(WidgetRef ref, MemberResult member) {
  // For now, navigate to the context room. If it's a DM, that's the right
  // behavior; if it's a small room, we land in shared context.
  ref.read(selectedRoomProvider.notifier).state = member.contextRoom.id;
}
