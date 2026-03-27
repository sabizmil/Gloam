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
  final String? fileSendingStatus; // generatingThumbnail, encrypting, uploading

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
    this.fileSendingStatus,
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
    _rebuild();

    // Request missing Megolm session keys for any undecryptable events.
    // Keys can be lost if the app is killed mid-sync before flushing to DB.
    _timeline!.requestKeys(onlineKeyBackupOnly: false);

    // Member state events (avatars, display names) arrive via sync but
    // don't trigger Timeline callbacks. Listen for syncs that carry
    // member state for this room and rebuild when they do.
    _syncSub = _client.onSync.stream.listen((syncUpdate) {
      final roomUpdate = syncUpdate.rooms?.join?[_roomId];
      if (roomUpdate == null) return;
      final hasMemberState = roomUpdate.state
              ?.any((e) => e.type == EventTypes.RoomMember) ??
          false;
      if (hasMemberState) _rebuild();
    });

    // requestUser() resolves via direct API calls (not sync), so
    // schedule a deferred rebuild to pick up member data that arrives
    // shortly after initial load.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _rebuild();
    });

    // The initial sync page may be mostly redactions/reactions that we
    // filter out, leaving very few visible messages. Pre-fetch extra
    // pages so the timeline has enough content to fill the viewport.
    await _ensureMinimumMessages(30);
  }

  /// Keep requesting history until we have at least [minVisible] display
  /// messages or the server says there's no more history.
  ///
  /// For newly-joined federated rooms, the timeline may be empty and
  /// canRequestHistory may be false initially. We retry with a delay
  /// to catch messages as the federation bootstrap completes.
  Future<void> _ensureMinimumMessages(int minVisible) async {
    if (_timeline == null) return;

    for (var attempt = 0; attempt < 10; attempt++) {
      // Count how many visible messages we'd show
      final visibleCount = _timeline!.events.where((e) {
        final relType = e.content
            .tryGetMap<String, Object?>('m.relates_to')
            ?.tryGet<String>('rel_type');
        if (relType == RelationshipTypes.edit ||
            relType == RelationshipTypes.reaction) return false;
        final display = e.getDisplayEvent(_timeline!);
        return display.type == EventTypes.Message ||
            display.type == EventTypes.Encrypted ||
            display.type == EventTypes.Sticker;
      }).length;

      if (visibleCount >= minVisible) break;

      if (_timeline!.canRequestHistory) {
        await _timeline!.requestHistory();
        _rebuild();
      } else if (attempt < 5 && visibleCount == 0) {
        // Room might still be bootstrapping — wait and retry
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        // Try requesting again in case the room state has caught up
        try {
          await _timeline!.requestHistory();
          _rebuild();
        } catch (_) {
          // Server may not be ready yet — keep retrying
        }
      } else {
        break;
      }
    }
  }

  bool _decrypting = false;

  void _rebuild() {
    // Synchronous pass first — show what we have now
    _buildMessages();

    // Then attempt async decryption if there are encrypted events
    if (!_decrypting) {
      _tryDecryptAndRebuild();
    }
  }

  Future<void> _tryDecryptAndRebuild() async {
    final timeline = _timeline;
    final encryption = _client.encryption;
    if (timeline == null || encryption == null || _room?.encrypted != true) {
      return;
    }

    final encrypted = <int>[];
    for (var i = 0; i < timeline.events.length; i++) {
      if (timeline.events[i].type == EventTypes.Encrypted) {
        encrypted.add(i);
      }
    }
    if (encrypted.isEmpty) return;

    _decrypting = true;
    var decryptedCount = 0;

    for (final i in encrypted) {
      final event = timeline.events[i];
      try {
        final decrypted = await encryption.decryptRoomEvent(
          event,
          store: true,
          updateType: EventUpdateType.history,
        );
        if (decrypted.type != EventTypes.Encrypted) {
          timeline.events[i] = decrypted;
          decryptedCount++;
        }
      } catch (_) {
        // Decryption failed — leave event as-is
      }
    }

    _decrypting = false;

    if (decryptedCount > 0) _buildMessages();
  }

  void _buildMessages() {
    final timeline = _timeline;
    if (timeline == null) return;

    final messages = <TimelineMessage>[];
    final myUserId = _client.userID;
    final seenEventIds = <String>{};

    for (final event in timeline.events) {
      // Skip edit and reaction relation events — they're aggregated
      // into their parent events, not displayed standalone
      final relType = event.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('rel_type');
      if (relType == RelationshipTypes.edit ||
          relType == RelationshipTypes.reaction) {
        continue;
      }

      // Use getDisplayEvent to get the decrypted/replaced version
      final displayEvent = event.getDisplayEvent(timeline);

      // Deduplicate — an edit can cause the same event to appear twice
      if (!seenEventIds.add(displayEvent.eventId)) continue;

      // Only display actual content events — skip redaction protocol events,
      // state events, and everything else. Redacted messages are handled by
      // the `redacted` flag on the original event, not by displaying the
      // m.room.redaction event itself.
      if (displayEvent.type == EventTypes.Message ||
          displayEvent.type == EventTypes.Encrypted ||
          displayEvent.type == EventTypes.Sticker) {
        messages.add(_mapEvent(displayEvent, myUserId));
      }
    }

    // SDK returns newest first — reverse for display (oldest at top)
    state = messages.reversed.toList();

    // Auto-mark as read when the room is actively viewed
    if (_isActive) markAsRead();
  }

  /// Extract the display body for an event, handling edits correctly.
  /// For edited messages, uses m.new_content body instead of the raw
  /// event body which includes a "* old text" fallback prefix.
  String _extractBody(Event event) {
    // If this event has m.new_content (it's an edit), use the new body
    final newContent = event.content.tryGetMap<String, Object?>('m.new_content');
    if (newContent != null) {
      final newBody = newContent.tryGet<String>('body');
      if (newBody != null) return newBody;
    }
    // Plain event — use body directly
    return event.body;
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

    // Determine message type — if the event is still encrypted
    // (decryption failed), show as undecryptable rather than raw text.
    String type;
    if (event.type == EventTypes.Encrypted) {
      type = 'm.bad_encrypted';
    } else {
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
    }

    final sender = event.senderFromMemoryOrFallback;
    Uri? senderAvatarUrl = sender.avatarUrl;

    // In DM rooms, senderFromMemoryOrFallback for the current user
    // unreliably inherits the DM partner's avatar from the room state
    // fallback. Rather than comparing URLs (which races with member state
    // loading), always clear the avatar for the current user in DMs so
    // the widget falls back to the sender's initial letter.
    if (event.senderId == _room!.client.userID && _room!.isDirectChat) {
      senderAvatarUrl = null;
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
      fileSendingStatus:
          event.unsigned?[fileSendingStatusKey] as String?,
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
  ///
  /// For local echoes (failed sends, pending uploads), removes the event
  /// locally. For server-confirmed events, sends a redaction to the server.
  Future<void> redactMessage(String eventId) async {
    final room = _room;
    if (room == null) return;

    // Local echoes have transaction IDs that don't start with '$'.
    // The server will reject redaction requests for these.
    if (!eventId.startsWith('\$')) {
      // Remove the local echo from the timeline
      final event = _timeline?.events
          .where((e) => e.eventId == eventId)
          .firstOrNull;
      if (event != null) {
        await event.remove();
        _rebuild();
      }
      return;
    }

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

  String? _lastReadEventId;
  bool _isActive = false;

  /// Mark this room as actively viewed — will auto-send read receipts.
  void setActive(bool active) {
    _isActive = active;
    if (active) markAsRead();
  }

  /// Mark the room as read (send read receipt for the latest event).
  Future<void> markAsRead() async {
    final room = _room;
    if (room == null || _timeline == null) return;
    if (_timeline!.events.isEmpty) return;

    final latestEventId = _timeline!.events.first.eventId;
    // Skip if we already sent a receipt for this event
    if (latestEventId == _lastReadEventId) return;
    _lastReadEventId = latestEventId;

    try {
      await room.setReadMarker(latestEventId, mRead: latestEventId);
    } catch (_) {
      // Best-effort — don't crash if receipt fails
      _lastReadEventId = null;
    }
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

/// True while a mobile chat route is pushed on the Navigator stack.
final mobileChatRouteActiveProvider = StateProvider<bool>((ref) => false);
