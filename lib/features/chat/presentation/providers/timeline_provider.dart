import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../../services/matrix_service.dart';

/// Lightweight message model — isolates UI from SDK types.
class TimelineMessage {
  final String eventId;
  final String senderId;
  final String senderName;
  final Uri? senderAvatarUrl;
  final DateTime timestamp;
  final String type; // m.text, m.image, m.file, m.audio, m.video, m.emote, m.notice
  final String body;
  final String? formattedBody;
  final String? mimeType;
  final Uri? mediaUrl;
  final MessageSendState sendState;
  final bool isEdited;
  final String? replyToEventId;
  final String? replyToSenderName;
  final String? replyToBody;
  final Map<String, ReactionGroup> reactions;
  final bool isRedacted;
  final int? mediaSizeBytes;
  final int? imageWidth;
  final int? imageHeight;

  const TimelineMessage({
    required this.eventId,
    required this.senderId,
    required this.senderName,
    this.senderAvatarUrl,
    required this.timestamp,
    required this.type,
    required this.body,
    this.formattedBody,
    this.mimeType,
    this.mediaUrl,
    this.sendState = MessageSendState.sent,
    this.isEdited = false,
    this.replyToEventId,
    this.replyToSenderName,
    this.replyToBody,
    this.reactions = const {},
    this.isRedacted = false,
    this.mediaSizeBytes,
    this.imageWidth,
    this.imageHeight,
  });

  bool get isLocalEcho => eventId.startsWith('~');
}

enum MessageSendState { sending, sent, error }

class ReactionGroup {
  final String emoji;
  final int count;
  final bool includesMe;
  const ReactionGroup({
    required this.emoji,
    required this.count,
    required this.includesMe,
  });
}

/// Provides the room's timeline as a list of [TimelineMessage]s.
/// Rebuilds when the timeline updates (new messages, edits, reactions, etc.)
class TimelineNotifier extends StateNotifier<List<TimelineMessage>> {
  final Client _client;
  final String _roomId;
  Timeline? _timeline;
  StreamSubscription? _sub;
  StreamSubscription? _syncSub;

  TimelineNotifier(this._client, this._roomId) : super([]) {
    _init();
  }

  Room? get _room => _client.getRoomById(_roomId);

  Future<void> _init() async {
    final room = _room;
    if (room == null) return;

    _timeline = await room.getTimeline(
      onChange: (_) => _rebuild(),
      onInsert: (_) => _rebuild(),
      onRemove: (_) => _rebuild(),
    );

    // Listen for sync updates that include member state events for this room.
    // Member state arrives asynchronously (via requestUser or lazy-loaded sync)
    // and the Timeline callbacks don't fire for state-only changes. Without
    // this, sender avatars/names mapped during _rebuild() stay stale until
    // a timeline event triggers a rebuild (e.g. scrolling to load history).
    _syncSub = _client.onSync.stream.listen((sync) {
      final joinRoom = sync.rooms?.join?[_roomId];
      if (joinRoom == null) return;
      final hasNewMemberState = joinRoom.state?.any(
            (e) => e.type == EventTypes.RoomMember,
          ) ??
          false;
      final hasTimelineMemberState = joinRoom.timeline?.events?.any(
            (e) => e.type == EventTypes.RoomMember,
          ) ??
          false;
      if (hasNewMemberState || hasTimelineMemberState) {
        _rebuild();
      }
    });

    _rebuild();

    // unsafeGetUserFromMemoryOrFallback fires off requestUser() for any
    // members not yet in the room state cache. Those requests resolve via
    // direct API calls (not through sync), so neither the Timeline callbacks
    // nor the sync listener above will catch them. Schedule a deferred
    // rebuild to pick up member data that arrives shortly after initial load.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _rebuild();
    });
  }

  void _rebuild() {
    final timeline = _timeline;
    if (timeline == null) return;

    final messages = <TimelineMessage>[];
    final myUserId = _client.userID;

    for (final event in timeline.events) {
      // Use getDisplayEvent to get the decrypted version
      final displayEvent = event.getDisplayEvent(timeline);

      if (displayEvent.type == EventTypes.Message ||
          displayEvent.type == EventTypes.Encrypted ||
          displayEvent.type == EventTypes.Sticker) {
        messages.add(_mapEvent(displayEvent, myUserId));
      } else if (displayEvent.type == EventTypes.Redaction) {
        continue;
      }
      // Skip state events for now (joins, leaves, etc.)
    }

    // SDK returns newest first — reverse for display (oldest at top)
    state = messages.reversed.toList();
  }

  /// Extract the display body for an event, handling edits correctly.
  /// For edited messages, uses m.new_content body instead of the raw
  /// event body which includes a "* old text" fallback prefix.
  String _extractBody(Event event) {
    // Check if this event has m.new_content (it's an edit)
    final newContent = event.content.tryGetMap<String, Object?>('m.new_content');
    if (newContent != null) {
      final newBody = newContent.tryGet<String>('body');
      if (newBody != null) return newBody;
    }
    // For non-edits, or if m.new_content doesn't have a body, use the
    // SDK's calcLocalizedBodyFallback which strips reply fallbacks
    return event.calcLocalizedBodyFallback(
      const MatrixDefaultLocalizations(),
      hideEdit: true,
      hideReply: true,
    );
  }

  TimelineMessage _mapEvent(Event event, String? myUserId) {
    // Handle replies
    String? replyToEventId;
    String? replyToSenderName;
    String? replyToBody;

    // Check if this message is a reply via m.relates_to
    final relatesTo = event.content.tryGetMap<String, Object?>('m.relates_to');
    final inReplyToMap = relatesTo?.tryGetMap<String, Object?>('m.in_reply_to');
    replyToEventId = inReplyToMap?.tryGet<String>('event_id');

    // Handle reactions
    final reactionMap = <String, ReactionGroup>{};
    final aggregatedEvents = event.aggregatedEvents(
      _timeline!,
      RelationshipTypes.reaction,
    );
    final reactionCounts = <String, int>{};
    final reactionIncludesMe = <String, bool>{};

    for (final reaction in aggregatedEvents) {
      final relatesToMap =
          reaction.content.tryGetMap<String, Object?>('m.relates_to');
      final emoji = relatesToMap?.tryGet<String>('key') ?? '';
      if (emoji.isEmpty) continue;
      reactionCounts[emoji] = (reactionCounts[emoji] ?? 0) + 1;
      if (reaction.senderId == myUserId) {
        reactionIncludesMe[emoji] = true;
      }
    }
    for (final entry in reactionCounts.entries) {
      reactionMap[entry.key] = ReactionGroup(
        emoji: entry.key,
        count: entry.value,
        includesMe: reactionIncludesMe[entry.key] ?? false,
      );
    }

    // Determine send state
    var sendState = MessageSendState.sent;
    if (event.status.isSending) {
      sendState = MessageSendState.sending;
    } else if (event.status.isError) {
      sendState = MessageSendState.error;
    }

    // Determine message type
    String type;
    final msgType = event.messageType;
    switch (msgType) {
      case MessageTypes.Image:
        type = 'm.image';
      case MessageTypes.File:
        type = 'm.file';
      case MessageTypes.Audio:
        type = 'm.audio';
      case MessageTypes.Video:
        type = 'm.video';
      case MessageTypes.Emote:
        type = 'm.emote';
      case MessageTypes.Notice:
        type = 'm.notice';
      default:
        type = 'm.text';
    }

    final sender = event.senderFromMemoryOrFallback;
    Uri? senderAvatarUrl = sender.avatarUrl;

    // In DM rooms, senderFromMemoryOrFallback can return a fallback User
    // whose avatar inherits the room's DM avatar instead of the sender's own.
    // The original BUG-008 fix compared senderAvatarUrl == _room!.avatar, but
    // that equality check can fail on initial load when _room!.avatar hasn't
    // resolved yet (race condition). Instead, directly compare against the DM
    // partner's avatar to catch the contamination regardless of room avatar
    // resolution timing.
    if (event.senderId == _room!.client.userID &&
        _room!.isDirectChat &&
        senderAvatarUrl != null) {
      final dmPartnerId = _room!.directChatMatrixID;
      if (dmPartnerId != null) {
        final dmPartner =
            _room!.unsafeGetUserFromMemoryOrFallback(dmPartnerId);
        if (senderAvatarUrl == dmPartner.avatarUrl ||
            senderAvatarUrl == _room!.avatar) {
          senderAvatarUrl = null;
        }
      }
    }

    return TimelineMessage(
      eventId: event.eventId,
      senderId: event.senderId,
      senderName: sender.calcDisplayname(),
      senderAvatarUrl: senderAvatarUrl,
      timestamp: event.originServerTs,
      type: type,
      body: _extractBody(event),
      formattedBody: event.formattedText.isNotEmpty ? event.formattedText : null,
      mimeType: event.content.tryGetMap<String, Object?>('info')?.tryGet<String>('mimetype'),
      mediaUrl: event.attachmentMxcUrl,
      sendState: sendState,
      isEdited: event.hasAggregatedEvents(
        _timeline!,
        RelationshipTypes.edit,
      ),
      replyToEventId: replyToEventId,
      replyToSenderName: replyToSenderName,
      replyToBody: replyToBody,
      reactions: reactionMap,
      isRedacted: event.redacted,
      mediaSizeBytes:
          event.content.tryGetMap<String, Object?>('info')?.tryGet<int>('size'),
      imageWidth:
          event.content.tryGetMap<String, Object?>('info')?.tryGet<int>('w'),
      imageHeight:
          event.content.tryGetMap<String, Object?>('info')?.tryGet<int>('h'),
    );
  }

  /// Request older messages from the server.
  Future<void> loadMore() async {
    await _timeline?.requestHistory();
  }

  /// Send a text message. Returns immediately (optimistic).
  Future<void> sendTextMessage(String text) async {
    final room = _room;
    if (room == null) return;
    await room.sendTextEvent(text);
  }

  /// Send a reply to a specific event.
  Future<void> sendReply(String text, String replyToEventId) async {
    final room = _room;
    if (room == null || _timeline == null) return;

    // Find the event in the loaded timeline first, fall back to fetching
    Event? replyEvent;
    try {
      replyEvent = _timeline!.events.firstWhere(
        (e) => e.eventId == replyToEventId,
      );
    } catch (_) {
      replyEvent = await room.getEventById(replyToEventId);
    }
    if (replyEvent != null) {
      await room.sendTextEvent(text, inReplyTo: replyEvent);
    }
  }

  /// Edit a message.
  Future<void> editMessage(String eventId, String newText) async {
    final room = _room;
    if (room == null) return;
    // Disable command parsing for edits — otherwise text starting with
    // "/" or "*" gets interpreted as slash commands instead of edited content
    await room.sendTextEvent(
      newText,
      editEventId: eventId,
      parseCommands: false,
    );
  }

  /// Redact (delete) a message.
  Future<void> redactMessage(String eventId) async {
    final room = _room;
    if (room == null) return;
    await room.redactEvent(eventId);
  }

  /// Toggle a reaction — add if not reacted, remove if already reacted.
  Future<void> react(String eventId, String emoji) async {
    final room = _room;
    if (room == null || _timeline == null) return;

    // Find the target event in the timeline
    final targetEvent = _timeline!.events
        .where((e) => e.eventId == eventId)
        .firstOrNull;
    if (targetEvent == null) {
      await room.sendReaction(eventId, emoji);
      return;
    }

    // Check if the current user already reacted with this emoji
    final myUserId = _client.userID;
    final existingReactions = targetEvent.aggregatedEvents(
      _timeline!,
      RelationshipTypes.reaction,
    );

    Event? myReaction;
    for (final reaction in existingReactions) {
      final key = reaction.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key == emoji && reaction.senderId == myUserId) {
        myReaction = reaction;
        break;
      }
    }

    if (myReaction != null) {
      // Already reacted — remove by redacting the reaction event
      await room.redactEvent(myReaction.eventId);
    } else {
      // Not reacted — add reaction
      await room.sendReaction(eventId, emoji);
    }
  }

  /// Send a file/image attachment.
  Future<void> sendFileMessage(MatrixFile file) async {
    final room = _room;
    if (room == null) return;
    await room.sendFileEvent(file);
  }

  /// Send typing notification.
  Future<void> setTyping(bool isTyping) async {
    final room = _room;
    if (room == null) return;
    await room.setTyping(isTyping);
  }

  /// Mark the room as read (send read receipt for the latest event).
  Future<void> markAsRead() async {
    final room = _room;
    if (room == null || _timeline == null) return;
    if (_timeline!.events.isEmpty) return;
    await room.setReadMarker(
      _timeline!.events.first.eventId,
      mRead: _timeline!.events.first.eventId,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _syncSub?.cancel();
    _timeline?.cancelSubscriptions();
    super.dispose();
  }
}

/// Family provider — one timeline per room.
final timelineProvider = StateNotifierProvider.family<TimelineNotifier,
    List<TimelineMessage>, String>(
  (ref, roomId) {
    final client = ref.watch(matrixServiceProvider).client;
    if (client == null) {
      return TimelineNotifier(Client('dummy'), roomId);
    }
    return TimelineNotifier(client, roomId);
  },
);

/// Currently selected room ID.
final selectedRoomProvider = StateProvider<String?>((ref) => null);
