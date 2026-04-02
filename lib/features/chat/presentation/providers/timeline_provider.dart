import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../../services/debug_server.dart';
import '../../../../services/matrix_service.dart';
import '../../../../services/search_service.dart';

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
  final Uri? replyToSenderAvatarUrl;
  final Map<String, ReactionGroup> reactions;
  final bool isRedacted;
  final int redactedCount; // > 1 when consecutive redacted messages are collapsed
  final int? mediaSizeBytes;
  final int? imageWidth;
  final int? imageHeight;
  final String? fileSendingStatus; // generatingThumbnail, encrypting, uploading
  final Uri? thumbnailUrl;
  final bool isThreadReply;
  final String? threadRootEventId;

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
    this.replyToSenderAvatarUrl,
    this.reactions = const {},
    this.isRedacted = false,
    this.redactedCount = 1,
    this.mediaSizeBytes,
    this.imageWidth,
    this.imageHeight,
    this.fileSendingStatus,
    this.thumbnailUrl,
    this.isThreadReply = false,
    this.threadRootEventId,
  });

  bool get isLocalEcho => eventId.startsWith('~');
}

enum MessageSendState { sending, sent, error }

class ReactionGroup {
  final String emoji;
  final int count;
  final bool includesMe;
  final List<String> reactorNames;
  const ReactionGroup({
    required this.emoji,
    required this.count,
    required this.includesMe,
    this.reactorNames = const [],
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
  final SearchService _searchService;

  TimelineNotifier(this._client, this._roomId, this._searchService) : super([]) {
    DebugServer.timelineRegistry[_roomId] = () => timelineDebugState;
    _init();
  }

  Room? get _room => _client.getRoomById(_roomId);

  void _log(String msg) => DebugServer.logs.add('[timeline:$_roomId] $msg');

  /// Expose timeline state for debug endpoints.
  Map<String, dynamic> get timelineDebugState => {
    'roomId': _roomId,
    'eventCount': _timeline?.events.length ?? 0,
    'isFragmented': isFragmented,
    'allowNewEvent': _timeline?.allowNewEvent ?? true,
    'canRequestHistory': _timeline?.canRequestHistory ?? false,
    'canRequestFuture': _timeline?.canRequestFuture ?? false,
    'jumpTargetEventId': _jumpTargetEventId,
    'stateMessageCount': state.length,
    if (_timeline != null && _timeline!.events.isNotEmpty) ...{
      'firstEventId': _timeline!.events.first.eventId,
      'lastEventId': _timeline!.events.last.eventId,
    },
  };

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

    // Index all loaded timeline events for search.
    if (_timeline != null) {
      _searchService.indexTimeline(_roomId, _timeline!.events);
    }
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
    final reversed = messages.reversed.toList();

    // Collapse consecutive redacted messages into a single entry
    final collapsed = <TimelineMessage>[];
    for (final msg in reversed) {
      if (msg.isRedacted &&
          collapsed.isNotEmpty &&
          collapsed.last.isRedacted) {
        // Merge into the previous redacted entry
        final prev = collapsed.last;
        collapsed[collapsed.length - 1] = TimelineMessage(
          eventId: prev.eventId,
          senderId: prev.senderId,
          senderName: prev.senderName,
          senderAvatarUrl: prev.senderAvatarUrl,
          timestamp: prev.timestamp,
          type: prev.type,
          body: prev.body,
          isRedacted: true,
          redactedCount: prev.redactedCount + 1,
        );
      } else {
        collapsed.add(msg);
      }
    }

    // Skip state update if the message list hasn't changed —
    // avoids unnecessary ListView relayouts that cause scroll jumps.
    if (_stateUnchanged(collapsed)) return;

    state = collapsed;

    // Auto-mark as read when the room is actively viewed
    if (_isActive) markAsRead();
  }

  /// Fast check: do the new messages match the current state?
  /// Compares event IDs, redacted status, edit status, and reaction counts
  /// to detect meaningful changes without deep equality.
  bool _stateUnchanged(List<TimelineMessage> newState) {
    final old = state;
    if (old.length != newState.length) return false;
    for (var i = 0; i < old.length; i++) {
      if (old[i].eventId != newState[i].eventId ||
          old[i].isRedacted != newState[i].isRedacted ||
          old[i].redactedCount != newState[i].redactedCount ||
          old[i].isEdited != newState[i].isEdited ||
          old[i].body != newState[i].body ||
          old[i].reactions.length != newState[i].reactions.length ||
          old[i].sendState != newState[i].sendState) {
        return false;
      }
    }
    return true;
  }

  /// Extract the display body for an event, stripping reply fallback and
  /// handling edits. The SDK's `calcUnlocalizedBody` removes the `> <@user>`
  /// quoted fallback that Matrix embeds in reply/thread bodies.
  String _extractBody(Event event) {
    return event.calcUnlocalizedBody(hideReply: true, hideEdit: true);
  }

  TimelineMessage _mapEvent(Event event, String? myUserId) {
    // Handle replies and threads
    String? replyToEventId;
    String? replyToSenderName;
    String? replyToBody;
    Uri? replyToSenderAvatarUrl;
    bool isThreadReply = false;
    String? threadRootEventId;

    // Check relation type — m.thread vs m.in_reply_to
    final relatesTo = event.content.tryGetMap<String, Object?>('m.relates_to');
    final relType = relatesTo?.tryGet<String>('rel_type');

    if (relType == RelationshipTypes.thread) {
      // This is a thread reply (m.thread relation)
      isThreadReply = true;
      threadRootEventId = relatesTo?.tryGet<String>('event_id');
      // Thread events may also carry m.in_reply_to for the within-thread reply
      final inReplyToMap = relatesTo?.tryGetMap<String, Object?>('m.in_reply_to');
      replyToEventId = inReplyToMap?.tryGet<String>('event_id');
    } else {
      // Regular reply (m.in_reply_to only)
      final inReplyToMap = relatesTo?.tryGetMap<String, Object?>('m.in_reply_to');
      replyToEventId = inReplyToMap?.tryGet<String>('event_id');
    }

    // Populate reply metadata from the referenced event
    if (replyToEventId != null) {
      try {
        final replyEvent = _timeline!.events.firstWhere(
          (e) => e.eventId == replyToEventId,
        );
        final replySender = replyEvent.senderFromMemoryOrFallback;
        replyToSenderName = replySender.calcDisplayname();
        replyToBody = _extractBody(replyEvent);
        replyToSenderAvatarUrl = replySender.avatarUrl;
      } catch (_) {
        // Reply target not in loaded timeline — leave fields null
      }
    }

    // Handle reactions
    final reactionMap = <String, ReactionGroup>{};
    final aggregatedEvents = event.aggregatedEvents(
      _timeline!,
      RelationshipTypes.reaction,
    );
    final reactionCounts = <String, int>{};
    final reactionIncludesMe = <String, bool>{};
    final reactionNames = <String, List<String>>{};

    for (final reaction in aggregatedEvents) {
      final relatesToMap =
          reaction.content.tryGetMap<String, Object?>('m.relates_to');
      final emoji = relatesToMap?.tryGet<String>('key') ?? '';
      if (emoji.isEmpty) continue;
      reactionCounts[emoji] = (reactionCounts[emoji] ?? 0) + 1;
      // Resolve reactor display name
      final reactor = _room?.unsafeGetUserFromMemoryOrFallback(reaction.senderId);
      final name = reaction.senderId == myUserId
          ? 'you'
          : (reactor?.calcDisplayname() ?? reaction.senderId);
      (reactionNames[emoji] ??= []).add(name);
      if (reaction.senderId == myUserId) {
        reactionIncludesMe[emoji] = true;
      }
    }
    for (final entry in reactionCounts.entries) {
      reactionMap[entry.key] = ReactionGroup(
        emoji: entry.key,
        count: entry.value,
        includesMe: reactionIncludesMe[entry.key] ?? false,
        reactorNames: reactionNames[entry.key] ?? [],
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

    // In DM rooms, senderFromMemoryOrFallback for the current user can
    // inherit the DM partner's avatar from the room state fallback.
    // Only clear it if it actually matches the partner's avatar.
    if (event.senderId == _room!.client.userID && _room!.isDirectChat) {
      final partnerId = _room!.directChatMatrixID;
      if (partnerId != null && senderAvatarUrl != null) {
        final partner = _room!.unsafeGetUserFromMemoryOrFallback(partnerId);
        if (partner.avatarUrl != null &&
            senderAvatarUrl.toString() == partner.avatarUrl.toString()) {
          senderAvatarUrl = null; // Inherited partner's avatar — clear it
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
      replyToSenderAvatarUrl: replyToSenderAvatarUrl,
      isThreadReply: isThreadReply,
      threadRootEventId: threadRootEventId,
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
      thumbnailUrl: event.thumbnailMxcUrl,
    );
  }

  /// Request older messages from the server.
  bool _loadingMore = false;

  Future<void> loadMore() async {
    if (_loadingMore) return;
    _loadingMore = true;
    try {
      await _timeline?.requestHistory();
      // Index newly loaded historical messages for search
      if (_timeline != null) {
        _searchService.indexTimeline(_roomId, _timeline!.events);
      }
    } finally {
      _loadingMore = false;
    }
  }

  /// Whether the timeline is viewing historical context (not live).
  /// True when we jumped to an event and haven't caught up to the present yet.
  /// Once forward pagination closes the gap (allowNewEvent flips to true),
  /// this returns false even though the SDK's isFragmentedTimeline stays true.
  bool get isFragmented =>
      _timeline != null &&
      _timeline!.isFragmentedTimeline &&
      !_timeline!.allowNewEvent;

  /// The event ID we're currently jumping to (for highlight after load).
  String? _jumpTargetEventId;
  String? get jumpTargetEventId => _jumpTargetEventId;

  /// Jump the timeline to center around a specific event.
  /// Destroys the current timeline and creates a fragmented one.
  Future<void> jumpToEvent(String eventId) async {
    final room = _room;
    if (room == null) {
      _log('jumpToEvent: room is null');
      return;
    }

    _log('jumpToEvent: target=$eventId, old timeline had ${_timeline?.events.length ?? 0} events');
    _jumpTargetEventId = eventId;

    // Tear down old timeline
    _syncSub?.cancel();
    _timeline?.cancelSubscriptions();

    try {
      // Create new timeline centered on the target event
      _timeline = await room.getTimeline(
        onChange: (_) => _rebuild(),
        onInsert: (_) => _rebuild(),
        onRemove: (_) => _rebuild(),
        eventContextId: eventId,
      );

      final eventCount = _timeline!.events.length;
      final isFragmented = _timeline!.isFragmentedTimeline;
      final targetFound = _timeline!.events.any((e) => e.eventId == eventId);
      final targetIndex = _timeline!.events.indexWhere((e) => e.eventId == eventId);
      _log('jumpToEvent: new timeline loaded, events=$eventCount, isFragmented=$isFragmented, targetFound=$targetFound, targetIndex=$targetIndex');

      if (eventCount > 0) {
        _log('jumpToEvent: first=${_timeline!.events.first.eventId.substring(0, 20)}... last=${_timeline!.events.last.eventId.substring(0, 20)}...');
      }

      _rebuild();

      // Index the new page for search
      _searchService.indexTimeline(_roomId, _timeline!.events);
    } catch (e) {
      _log('jumpToEvent: ERROR $e');
    }

    // Re-listen for member state updates
    _syncSub = _client.onSync.stream.listen((syncUpdate) {
      final roomUpdate = syncUpdate.rooms?.join?[_roomId];
      if (roomUpdate == null) return;
      final hasMemberState = roomUpdate.state
              ?.any((e) => e.type == EventTypes.RoomMember) ??
          false;
      if (hasMemberState) _rebuild();
    });
  }

  /// Return to the live present timeline.
  /// Destroys the fragmented timeline and loads from the latest.
  Future<void> jumpToPresent() async {
    final room = _room;
    if (room == null) return;

    _jumpTargetEventId = null;

    // Tear down fragmented timeline
    _syncSub?.cancel();
    _timeline?.cancelSubscriptions();

    // Create fresh timeline from the present
    _timeline = await room.getTimeline(
      onChange: (_) => _rebuild(),
      onInsert: (_) => _rebuild(),
      onRemove: (_) => _rebuild(),
    );
    _rebuild();

    _timeline!.requestKeys(onlineKeyBackupOnly: false);

    _syncSub = _client.onSync.stream.listen((syncUpdate) {
      final roomUpdate = syncUpdate.rooms?.join?[_roomId];
      if (roomUpdate == null) return;
      final hasMemberState = roomUpdate.state
              ?.any((e) => e.type == EventTypes.RoomMember) ??
          false;
      if (hasMemberState) _rebuild();
    });

    await _ensureMinimumMessages(30);

    if (_timeline != null) {
      _searchService.indexTimeline(_roomId, _timeline!.events);
    }
  }

  /// Load newer messages (forward pagination on fragmented timelines).
  bool _loadingNewer = false;

  Future<void> loadNewer() async {
    if (_loadingNewer || !isFragmented) return;
    _loadingNewer = true;
    try {
      await _timeline?.requestFuture(historyCount: 30);
      if (_timeline != null) {
        _searchService.indexTimeline(_roomId, _timeline!.events);
      }
      // If forward pagination caught up to the present, the SDK flips
      // allowNewEvent=true and the timeline is no longer fragmented.
      // Force-emit state so the "viewing older messages" banner disappears,
      // even if the message list itself didn't change.
      if (!isFragmented) {
        _jumpTargetEventId = null;
        state = List.of(state); // Force new reference to trigger rebuild
      }
    } finally {
      _loadingNewer = false;
    }
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

  /// Send a reply within a thread using proper m.thread relation.
  Future<void> sendThreadReply(
    String text,
    String rootEventId, {
    String? inReplyToEventId,
  }) async {
    final room = _room;
    if (room == null) return;

    Event? replyEvent;
    if (inReplyToEventId != null) {
      try {
        replyEvent = _timeline?.events.firstWhere(
          (e) => e.eventId == inReplyToEventId,
        );
      } catch (_) {
        replyEvent = await room.getEventById(inReplyToEventId);
      }
    }

    await room.sendTextEvent(
      text,
      threadRootEventId: rootEventId,
      inReplyTo: replyEvent,
    );
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

  /// Send a GIF/sticker with known dimensions.
  /// Bypasses sendFileEvent to avoid synchronous thumbnail generation
  /// and does a direct upload + manual event construction.
  Future<void> sendGif(Uint8List bytes, String filename, {int? width, int? height}) async {
    final room = _room;
    if (room == null) return;

    final mimeType = filename.endsWith('.webp')
        ? 'image/webp'
        : filename.endsWith('.gif')
            ? 'image/gif'
            : 'image/png';

    Uri uploadUri;
    Map<String, dynamic>? fileBlock;

    if (room.encrypted && _client.fileEncryptionEnabled) {
      // Encrypt and upload
      final plain = MatrixImageFile(bytes: bytes, name: filename, mimeType: mimeType);
      final encrypted = await plain.encrypt();
      final encFile = encrypted.toMatrixFile();
      uploadUri = await _client.uploadContent(
        encFile.bytes,
        filename: encFile.name,
        contentType: encFile.mimeType,
      );
      fileBlock = {
        'url': uploadUri.toString(),
        'mimetype': mimeType,
        'v': 'v2',
        'key': {
          'alg': 'A256CTR',
          'ext': true,
          'k': encrypted.k,
          'key_ops': ['encrypt', 'decrypt'],
          'kty': 'oct',
        },
        'iv': encrypted.iv,
        'hashes': {'sha256': encrypted.sha256},
      };
    } else {
      // Upload directly
      uploadUri = await _client.uploadContent(
        bytes,
        filename: filename,
        contentType: mimeType,
      );
    }

    final content = <String, dynamic>{
      'msgtype': MessageTypes.Image,
      'body': filename,
      'filename': filename,
      if (fileBlock != null) 'file': fileBlock,
      if (fileBlock == null) 'url': uploadUri.toString(),
      'info': {
        'mimetype': mimeType,
        'size': bytes.length,
        if (width != null) 'w': width,
        if (height != null) 'h': height,
      },
    };

    await room.sendEvent(content);
  }

  /// Send a file/image in a thread.
  Future<void> sendThreadFile(MatrixFile file, String rootEventId) async {
    final room = _room;
    if (room == null) return;
    // Pass thread relation via extraContent so the SDK's local echo
    // (fake event) includes it — otherwise the preview shows in the
    // main chat instead of the thread.
    await room.sendFileEvent(
      file,
      threadRootEventId: rootEventId,
      extraContent: {
        'm.relates_to': {
          'rel_type': RelationshipTypes.thread,
          'event_id': rootEventId,
        },
      },
    );
  }

  /// Send a GIF/sticker in a thread with known dimensions.
  Future<void> sendThreadGif(
    Uint8List bytes,
    String filename,
    String rootEventId, {
    int? width,
    int? height,
  }) async {
    final room = _room;
    if (room == null) return;

    final mimeType = filename.endsWith('.webp')
        ? 'image/webp'
        : filename.endsWith('.gif')
            ? 'image/gif'
            : 'image/png';

    Uri uploadUri;
    Map<String, dynamic>? fileBlock;

    if (room.encrypted && _client.fileEncryptionEnabled) {
      final plain = MatrixImageFile(bytes: bytes, name: filename, mimeType: mimeType);
      final encrypted = await plain.encrypt();
      final encFile = encrypted.toMatrixFile();
      uploadUri = await _client.uploadContent(
        encFile.bytes,
        filename: encFile.name,
        contentType: encFile.mimeType,
      );
      fileBlock = {
        'url': uploadUri.toString(),
        'mimetype': mimeType,
        'v': 'v2',
        'key': {
          'alg': 'A256CTR',
          'ext': true,
          'k': encrypted.k,
          'key_ops': ['encrypt', 'decrypt'],
          'kty': 'oct',
        },
        'iv': encrypted.iv,
        'hashes': {'sha256': encrypted.sha256},
      };
    } else {
      uploadUri = await _client.uploadContent(
        bytes,
        filename: filename,
        contentType: mimeType,
      );
    }

    final content = <String, dynamic>{
      'msgtype': MessageTypes.Image,
      'body': filename,
      'filename': filename,
      if (fileBlock != null) 'file': fileBlock,
      if (fileBlock == null) 'url': uploadUri.toString(),
      'info': {
        'mimetype': mimeType,
        'size': bytes.length,
        if (width != null) 'w': width,
        if (height != null) 'h': height,
      },
      'm.relates_to': {
        'rel_type': RelationshipTypes.thread,
        'event_id': rootEventId,
      },
    };

    await room.sendEvent(content);
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
    DebugServer.timelineRegistry.remove(_roomId);
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
    final searchService = ref.read(searchServiceProvider);
    if (client == null) {
      return TimelineNotifier(Client('dummy'), roomId, searchService);
    }
    return TimelineNotifier(client, roomId, searchService);
  },
);

/// Currently selected room ID.
final selectedRoomProvider = StateProvider<String?>((ref) => null);

/// True while a mobile chat route is pushed on the Navigator stack.
final mobileChatRouteActiveProvider = StateProvider<bool>((ref) => false);
