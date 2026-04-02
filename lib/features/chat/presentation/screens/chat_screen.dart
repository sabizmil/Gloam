import 'dart:io' show HttpClient;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/clipboard_paste_service.dart';
import '../../../../services/debug_server.dart';
import 'package:matrix/matrix.dart' show EventTypes, Membership;

import '../../../../services/matrix_service.dart';
import '../../../../services/klipy_service.dart';
import '../../../../services/upload_service.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/timeline_provider.dart';
import '../../../rooms/presentation/providers/space_hierarchy_provider.dart';
import '../widgets/date_separator.dart';
import '../widgets/drop_overlay.dart';
import '../widgets/following_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import '../widgets/syncing_zero_state.dart';
import '../widgets/typing_indicator.dart';
import '../../../../app/shell/right_panel.dart';
import '../../../calls/presentation/providers/call_provider.dart';
import '../../../calls/presentation/screens/outgoing_call_screen.dart';
import '../../../profile/presentation/user_profile_modal.dart';
import '../../../settings/presentation/recovery_key_dialog.dart';

/// Download bytes on a background isolate (used by compute()).
Future<Uint8List> _downloadBytes(String url) async {
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  final builder = BytesBuilder();
  await response.forEach(builder.add);
  client.close();
  return builder.toBytes();
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.roomId, this.compact = false});
  final String roomId;

  /// Compact mode for text-in-voice: hides the header, reduces padding.
  final bool compact;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  // GlobalKeys only for messages that need _scrollToMessage (reply-tap nav).
  // Most items use lightweight ValueKeys on the Column instead.
  final _scrollTargetKeys = <String, GlobalKey>{};
  final _composerKey = GlobalKey<MessageComposerState>();
  ComposerState _composerState = ComposerState.normal;
  // FAB visibility in a ValueNotifier so toggling it doesn't rebuild
  // the entire ChatScreen (and the ListView with it).
  final _showScrollToBottom = ValueNotifier<bool>(false);
  String? _highlightEventId;
  /// Tracks the composer text before a paste event so we can restore
  /// the user's in-progress message after a file/image upload.
  String _prePasteText = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Mark room as actively viewed — auto-sends read receipts
    // on init and whenever new messages arrive
    Future.microtask(() {
      ref.read(timelineProvider(widget.roomId).notifier).setActive(true);
    });
    // Focus the composer so the user can start typing immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _composerKey.currentState?.focus();
    });
  }

  @override
  void dispose() {
    ref.read(timelineProvider(widget.roomId).notifier).setActive(false);
    _scrollController.dispose();
    _showScrollToBottom.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Update FAB visibility via ValueNotifier — no setState, no rebuild.
    if (_scrollController.hasClients) {
      _showScrollToBottom.value =
          _scrollController.position.pixels > 200;
    }

    // Load more when near the top (reversed list = near max scroll extent)
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      ref.read(timelineProvider(widget.roomId).notifier).loadMore();
    }

    // Load newer when near the bottom on fragmented timelines
    final notifier = ref.read(timelineProvider(widget.roomId).notifier);
    if (notifier.isFragmented &&
        _scrollController.hasClients &&
        _scrollController.position.pixels <= 200) {
      notifier.loadNewer();
    }
  }

  void _scrollToBottom() {
    final notifier = ref.read(timelineProvider(widget.roomId).notifier);
    if (notifier.isFragmented) {
      // On fragmented timeline, jump back to the present
      notifier.jumpToPresent();
      return;
    }
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _jumpToEvent(String eventId) async {
    DebugServer.logs.add('[jump] _jumpToEvent called: $eventId');
    final notifier = ref.read(timelineProvider(widget.roomId).notifier);
    await notifier.jumpToEvent(eventId);
    DebugServer.logs.add('[jump] jumpToEvent completed, scheduling scroll');

    // Find the target's index in the messages list and scroll to it.
    // We need to use index-based scrolling because the target may be
    // off-screen and its widget (GlobalKey) won't have a context yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final messages = ref.read(timelineProvider(widget.roomId))
          .where((m) => !m.isThreadReply)
          .toList();
      final msgIndex = messages.indexWhere((m) => m.eventId == eventId);
      DebugServer.logs.add('[jump] target index in messages: $msgIndex / ${messages.length}');

      if (msgIndex < 0) {
        DebugServer.logs.add('[jump] target not found in state messages');
        return;
      }

      // In a reverse ListView, index 0 = newest (bottom).
      // Message at msgIndex maps to ListView index (messages.length - 1 - msgIndex).
      final listIndex = messages.length - 1 - msgIndex;

      // Estimate scroll position. Each message is roughly 60-80px.
      // Scroll to bring the target into view, then use GlobalKey to fine-tune.
      final estimatedOffset = listIndex * 70.0;
      DebugServer.logs.add('[jump] listIndex=$listIndex, estimatedOffset=$estimatedOffset');

      _scrollController.jumpTo(
        estimatedOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );

      // After scrolling, the target widget should be rendered.
      // Wait a frame, register key, and do precise scroll + highlight.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollTargetKeys.putIfAbsent(eventId, () => GlobalKey());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToMessage(eventId);
        });
      });
    });
  }

  /// Scroll to a specific message and briefly highlight it.
  void _scrollToMessage(String eventId) {
    final key = _scrollTargetKeys[eventId];
    final ctx = key?.currentContext;
    DebugServer.logs.add('[scroll] _scrollToMessage: eventId=${eventId.substring(0, 20)}... keyExists=${key != null} contextExists=${ctx != null} totalKeys=${_scrollTargetKeys.length}');
    if (ctx == null) return;

    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.3, // position target ~30% from top of viewport
    );

    // Flash highlight
    setState(() => _highlightEventId = eventId);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightEventId = null);
    });
  }

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      if (picked.path == null) return;

      final sizeError = UploadService.validateFileSize(picked.size);
      if (sizeError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sizeError), backgroundColor: context.gloam.danger),
        );
        return;
      }

      final matrixFile = await UploadService.fromPath(picked.path!);
      ref.read(timelineProvider(widget.roomId).notifier).sendFileMessage(matrixFile);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('upload failed: $e'), backgroundColor: context.gloam.danger),
        );
      }
    }
  }

  void _sendGif(KlipyItem item) {
    final roomId = widget.roomId;
    final notifier = ref.read(timelineProvider(roomId).notifier);
    final url = item.fullUrl;
    final w = item.fullWidth;
    final h = item.fullHeight;

    // Download on a background isolate, then upload directly.
    () async {
      try {
        final bytes = await compute(_downloadBytes, url);

        final uri = Uri.parse(url);
        final name = uri.pathSegments.isNotEmpty
            ? uri.pathSegments.last
            : 'gif.webp';

        await notifier.sendGif(bytes, name, width: w, height: h);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send: $e'), backgroundColor: context.gloam.danger),
          );
        }
      }
    }();
  }

  Future<void> _handleDroppedFiles(List<DropDoneDetails> detailsList) async {
    for (final details in detailsList) {
      for (final xFile in details.files) {
        try {
          final bytes = await xFile.readAsBytes();

          final sizeError = UploadService.validateFileSize(bytes.length);
          if (sizeError != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(sizeError), backgroundColor: context.gloam.danger),
            );
            continue;
          }

          final matrixFile = UploadService.createMatrixFile(
            bytes: bytes,
            name: xFile.name,
          );
          ref.read(timelineProvider(widget.roomId).notifier).sendFileMessage(matrixFile);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('upload failed: $e'), backgroundColor: context.gloam.danger),
            );
          }
        }
      }
    }
  }

  /// Handle Cmd+V / Ctrl+V — check clipboard for file or image data.
  /// The TextField already processed the text paste by the time this runs
  /// (child-first key propagation). If a file/image is found, we restore
  /// the user's original text from _prePasteText and upload the file
  /// separately — the user's in-progress message is preserved.
  Future<void> _handlePaste() async {
    try {
      // Try file paths FIRST (e.g. copied from Finder/Explorer).
      final files = await ClipboardPasteService.getClipboardFiles();
      if (files.isNotEmpty) {
        // Restore the user's text from before the paste
        _composerKey.currentState?.text = _prePasteText;
        for (final file in files) {
          ref.read(timelineProvider(widget.roomId).notifier).sendFileMessage(file);
        }
        return;
      }

      // Try clipboard image (screenshots, images copied from browsers)
      final imageFile = await ClipboardPasteService.getClipboardImage();
      if (imageFile != null) {
        final sizeError = UploadService.validateFileSize(imageFile.bytes.length);
        if (sizeError != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(sizeError), backgroundColor: context.gloam.danger),
          );
          return;
        }
        // Restore the user's text from before the paste
        _composerKey.currentState?.text = _prePasteText;
        ref.read(timelineProvider(widget.roomId).notifier).sendFileMessage(imageFile);
        return;
      }

      // No files or images found — the TextField's native text paste
      // already handled it, so nothing more to do.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('paste failed: $e'), backgroundColor: context.gloam.danger),
        );
      }
    }
  }

  void _confirmDelete(String eventId) {
    showDialog(
      context: context,
      barrierColor: context.gloam.overlay,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.gloam.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.gloam.border),
        ),
        title: Text(
          'delete message?',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: context.gloam.textPrimary,
          ),
        ),
        content: Text(
          'this can\'t be undone.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: context.gloam.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: context.gloam.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: context.gloam.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(timelineProvider(widget.roomId).notifier)
                    .redactMessage(eventId);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('delete failed: $e'),
                        backgroundColor: context.gloam.danger),
                  );
                }
              }
            },
            child: Text('delete',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: context.gloam.textPrimary)),
          ),
        ],
      ),
    );
  }

  void _editLastMessage() {
    final messages = ref.read(timelineProvider(widget.roomId));
    final myUserId =
        ref.read(matrixServiceProvider).client?.userID;
    if (myUserId == null) return;

    // Find the most recent own message
    final lastOwn = messages.reversed.firstWhere(
      (m) => m.senderId == myUserId && !m.isRedacted,
      orElse: () => messages.first,
    );
    if (lastOwn.senderId == myUserId) {
      _handleEditAction(lastOwn);
    }
  }

  void _handleReplyAction(TimelineMessage msg) {
    setState(() {
      _composerState = ComposerState(
        mode: ComposerMode.reply,
        targetEventId: msg.eventId,
        targetSenderName: msg.senderName,
        targetBody: msg.body,
      );
    });
  }

  void _handleEditAction(TimelineMessage msg) {
    setState(() {
      _composerState = ComposerState(
        mode: ComposerMode.edit,
        targetEventId: msg.eventId,
        targetSenderName: msg.senderName,
        targetBody: msg.body,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final allMessages = ref.watch(timelineProvider(widget.roomId));
    final client = ref.watch(matrixServiceProvider).client;
    final room = client?.getRoomById(widget.roomId);
    final localName = room?.getLocalizedDisplayname() ?? '';
    // Fall back to hierarchy name for rooms with generic/missing names
    final hierarchyName = ref.watch(hierarchyRoomNameProvider(widget.roomId));
    final roomName = (localName == 'Empty chat' || localName.isEmpty)
        ? (hierarchyName ?? localName)
        : localName;
    final topic = room?.topic ?? '';
    final memberCount = room?.summary.mJoinedMemberCount ?? 0;
    final myUserId = client?.userID;
    // Detect "joined but no state" — room exists but has no create event
    final isPartiallyJoined = room != null &&
        room.membership == Membership.join &&
        room.getState(EventTypes.RoomCreate) == null;

    // Check for pending jump-to-event from search results
    final pendingEventId = ref.read(pendingScrollToEventProvider);
    if (pendingEventId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(pendingScrollToEventProvider.notifier).state = null;
        _jumpToEvent(pendingEventId);
      });
    }

    // After a jumpToEvent, the target event should be in the loaded messages.
    // Register a GlobalKey for it and scroll after the frame renders.
    final jumpTarget = ref.read(timelineProvider(widget.roomId).notifier).jumpTargetEventId;
    if (jumpTarget != null) {
      _scrollTargetKeys.putIfAbsent(jumpTarget, () => GlobalKey());
    }

    // Filter out thread replies from the main timeline
    final messages = allMessages
        .where((m) => !m.isThreadReply)
        .toList();

    // Build thread metadata per root event ID for thread indicators
    final threadData = <String, _ThreadData>{};
    for (final m in allMessages.where((m) => m.isThreadReply)) {
      final rootId = m.threadRootEventId;
      if (rootId == null) continue;
      final data = threadData.putIfAbsent(
        rootId,
        () => _ThreadData(),
      );
      data.replyCount++;
      data.participants.putIfAbsent(
        m.senderId,
        () => (name: m.senderName, avatarUrl: m.senderAvatarUrl),
      );
      if (data.lastReplyTime == null ||
          m.timestamp.isAfter(data.lastReplyTime!)) {
        data.lastReplyTime = m.timestamp;
      }
    }

    return Focus(
      autofocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final isPaste = event.logicalKey == LogicalKeyboardKey.keyV &&
              (HardwareKeyboard.instance.isMetaPressed ||
                  HardwareKeyboard.instance.isControlPressed);
          if (isPaste) {
            _handlePaste();
          } else {
            // Continuously track the composer text so _prePasteText
            // always holds the user's text from before any paste.
            _prePasteText = _composerKey.currentState?.text ?? '';
          }
        }
        return KeyEventResult.ignored;
      },
      child: FileDropZone(
      onFilesDropped: _handleDroppedFiles,
      child: Column(
      children: [
        // Header
        if (!widget.compact) _ChatHeader(
          roomName: roomName,
          topic: topic,
          memberCount: memberCount,
          isEncrypted: room?.encrypted ?? false,
          isDirect: room?.isDirectChat ?? false,
          roomId: widget.roomId,
          hasUndecryptable: messages.any((m) =>
              m.body.contains('sender has not sent us the session key') ||
              m.body == 'Encrypted message'),
          onSearchTap: () => ref.read(rightPanelProvider.notifier).state =
              const RightPanelState(view: RightPanelView.search),
          onInfoTap: () => ref.read(rightPanelProvider.notifier).state =
              const RightPanelState(view: RightPanelView.roomInfo),
          onMembersTap: () => ref.read(rightPanelProvider.notifier).state =
              const RightPanelState(view: RightPanelView.members),
        ),

        // Following the conversation bar
        if (!widget.compact) FollowingBar(roomId: widget.roomId),

        // Pending state: joined but room has no state (restricted join pending sync)
        if (isPartiallyJoined && messages.isEmpty && !widget.compact)
          Expanded(
            child: _PendingRoomState(
              roomName: roomName,
              onLeave: () async {
                await room?.leave();
                if (context.mounted) {
                  ref.read(selectedRoomProvider.notifier).state = null;
                }
              },
            ),
          )
        // Syncing zero state: joined but no messages yet AND room still syncing.
        // Once the room is fully synced (not partial), show normal empty chat.
        else if (messages.isEmpty && room?.lastEvent == null &&
            (room?.partial ?? true) && !widget.compact)
          Expanded(
            child: SyncingZeroState(
              roomName: roomName,
              serverName: _extractServer(room?.id ?? ''),
              memberCount: memberCount,
              onLeave: () async {
                await room?.leave();
                if (context.mounted) {
                  ref.read(selectedRoomProvider.notifier).state = null;
                }
              },
            ),
          )
        else ...[
        // Timeline
        Expanded(
          child: Stack(
            children: [
              ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  // Reversed: index 0 = newest
                  final reversedIndex = messages.length - 1 - index;
                  final msg = messages[reversedIndex];
                  final prevMsg = reversedIndex > 0
                      ? messages[reversedIndex - 1]
                      : null;

                  // Date separator: different calendar day from previous
                  final showDateSep = prevMsg == null ||
                      _isDifferentDay(prevMsg.timestamp, msg.timestamp);

                  // Group: same sender, within 3 minutes, same day
                  final isGrouped = prevMsg != null &&
                      !showDateSep &&
                      prevMsg.senderId == msg.senderId &&
                      msg.timestamp.difference(prevMsg.timestamp).inMinutes <
                          3 &&
                      !prevMsg.isRedacted;

                  // Register GlobalKeys for messages that need _scrollToMessage:
                  // reply targets and pending search scroll targets.
                  if (msg.replyToEventId != null) {
                    _scrollTargetKeys.putIfAbsent(
                      msg.replyToEventId!,
                      () => GlobalKey(),
                    );
                  }
                  if (pendingEventId != null && msg.eventId == pendingEventId) {
                    _scrollTargetKeys.putIfAbsent(
                      pendingEventId,
                      () => GlobalKey(),
                    );
                  }
                  if (jumpTarget != null && msg.eventId == jumpTarget) {
                    _scrollTargetKeys.putIfAbsent(
                      jumpTarget,
                      () => GlobalKey(),
                    );
                  }

                  return Column(
                    // ValueKey on the top-level widget lets Flutter
                    // reliably track items across rebuilds in a
                    // reversed list.
                    key: ValueKey<String>(msg.eventId),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showDateSep)
                        DateSeparator(date: msg.timestamp),
                      GestureDetector(
                        onLongPress: () => _showMessageActions(context, msg,
                            isOwnMessage: msg.senderId == myUserId),
                        onSecondaryTap: () => _showMessageActions(
                            context, msg,
                            isOwnMessage: msg.senderId == myUserId),
                        child: AnimatedContainer(
                          key: _scrollTargetKeys[msg.eventId],
                          duration: const Duration(milliseconds: 500),
                          decoration: BoxDecoration(
                            color: _highlightEventId == msg.eventId
                                ? context.gloam.bgElevated
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: MessageBubble(
                            message: msg,
                            isGrouped: isGrouped,
                            roomId: widget.roomId,
                            isOwnMessage: msg.senderId == myUserId,
                            onAvatarTap: () => showUserProfile(
                              context, ref,
                              userId: msg.senderId,
                              roomId: widget.roomId,
                            ),
                            onReply: () => _handleReplyAction(msg),
                            onEdit: () => _handleEditAction(msg),
                            onReact: (emoji) => ref
                                .read(
                                    timelineProvider(widget.roomId).notifier)
                                .react(msg.eventId, emoji),
                            onDelete: () => _confirmDelete(msg.eventId),
                            onThread: () {
                              ref.read(rightPanelProvider.notifier).state =
                                  RightPanelState(
                                view: RightPanelView.thread,
                                threadRoot: msg,
                              );
                            },
                            onCopy: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('copied to clipboard'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            onReplyTap: msg.replyToEventId != null
                                ? () {
                                    // Try scrolling first; if the message isn't loaded, jump to it
                                    final key = _scrollTargetKeys[msg.replyToEventId!];
                                    if (key?.currentContext != null) {
                                      _scrollToMessage(msg.replyToEventId!);
                                    } else {
                                      _jumpToEvent(msg.replyToEventId!);
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ),
                      // Thread indicator
                      if (threadData.containsKey(msg.eventId))
                        _ThreadIndicator(
                          data: threadData[msg.eventId]!,
                          onTap: () {
                            ref.read(rightPanelProvider.notifier).state =
                                RightPanelState(
                              view: RightPanelView.thread,
                              threadRoot: msg,
                            );
                          },
                        ),
                    ],
                  );
                },
              ),

              // "Jump to Present" banner on fragmented timelines
              if (ref.watch(timelineProvider(widget.roomId).notifier).isFragmented)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: _scrollToBottom,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: context.gloam.accentDim,
                        border: Border(
                          top: BorderSide(color: context.gloam.accent),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'viewing older messages — tap to jump to present',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: context.gloam.accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Scroll-to-bottom FAB — rebuilds independently via
              // ValueListenableBuilder, not via ChatScreen setState.
              ValueListenableBuilder<bool>(
                valueListenable: _showScrollToBottom,
                builder: (context, show, _) {
                  if (!show) return const SizedBox.shrink();
                  return Positioned(
                    right: 20,
                    bottom: 12,
                    child: Material(
                      color: context.gloam.bgElevated,
                      shape: CircleBorder(
                        side: BorderSide(color: context.gloam.border),
                      ),
                      elevation: 0,
                      child: InkWell(
                        onTap: _scrollToBottom,
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(Icons.keyboard_arrow_down,
                              size: 20, color: context.gloam.textSecondary),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // Typing indicator
        TypingIndicator(roomId: widget.roomId),

        // Composer
        MessageComposer(
          key: _composerKey,
          roomName: roomName,
          composerState: _composerState,
          onSend: (text) => ref
              .read(timelineProvider(widget.roomId).notifier)
              .sendTextMessage(text),
          onReply: (text, eventId) => ref
              .read(timelineProvider(widget.roomId).notifier)
              .sendReply(text, eventId),
          onEdit: (text, eventId) async {
            try {
              await ref
                  .read(timelineProvider(widget.roomId).notifier)
                  .editMessage(eventId, text);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('edit failed: $e'),
                      backgroundColor: context.gloam.danger),
                );
              }
            }
          },
          onEditLastMessage: _editLastMessage,
          onTyping: (isTyping) => ref
              .read(timelineProvider(widget.roomId).notifier)
              .setTyping(isTyping),
          onAttach: () => _pickAndUploadFile(),
          onGif: (item) => _sendGif(item),
          onCancelAction: () =>
              setState(() => _composerState = ComposerState.normal),
        ),
        ], // end else (has messages)
      ],
    )));
  }

  String _extractServer(String roomId) {
    final colonIndex = roomId.indexOf(':');
    if (colonIndex >= 0 && colonIndex < roomId.length - 1) {
      return roomId.substring(colonIndex + 1);
    }
    return '';
  }

  void _showMessageActions(
    BuildContext context,
    TimelineMessage msg, {
    required bool isOwnMessage,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.gloam.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(GloamSpacing.radiusLg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick reactions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['👍', '❤️', '😂', '🔥', '👀', '🎉']
                    .map((emoji) => GestureDetector(
                          onTap: () {
                            ref
                                .read(timelineProvider(widget.roomId).notifier)
                                .react(msg.eventId, emoji);
                            Navigator.pop(ctx);
                          },
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 28)),
                        ))
                    .toList(),
              ),
            ),
            Divider(color: context.gloam.border, height: 1),
            _ActionTile(
              icon: Icons.reply,
              label: 'reply',
              onTap: () {
                Navigator.pop(ctx);
                _handleReplyAction(msg);
              },
            ),
            _ActionTile(
              icon: Icons.chat_bubble_outline,
              label: 'thread',
              onTap: () {
                Navigator.pop(ctx);
                ref.read(rightPanelProvider.notifier).state =
                    RightPanelState(
                  view: RightPanelView.thread,
                  threadRoot: msg,
                );
              },
            ),
            if (isOwnMessage)
              _ActionTile(
                icon: Icons.edit_outlined,
                label: 'edit',
                onTap: () {
                  Navigator.pop(ctx);
                  _handleEditAction(msg);
                },
              ),
            _ActionTile(
              icon: Icons.content_copy,
              label: 'copy text',
              onTap: () {
                Clipboard.setData(ClipboardData(text: msg.body));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            if (isOwnMessage)
              _ActionTile(
                icon: Icons.delete_outline,
                label: 'delete',
                color: context.gloam.danger,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(msg.eventId);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ChatHeader extends ConsumerWidget {
  const _ChatHeader({
    required this.roomName,
    required this.topic,
    required this.memberCount,
    required this.isEncrypted,
    this.isDirect = false,
    this.roomId,
    this.onInfoTap,
    this.onMembersTap,
    this.onSearchTap,
    this.hasUndecryptable = false,
  });

  final String roomName;
  final String topic;
  final int memberCount;
  final bool isEncrypted;
  final bool isDirect;
  final String? roomId;
  final VoidCallback? onInfoTap;
  final VoidCallback? onMembersTap;
  final VoidCallback? onSearchTap;
  final bool hasUndecryptable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: GloamSpacing.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.gloam.border),
        ),
      ),
      child: Row(
        children: [
          // Room info
          if (isEncrypted)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child:
                  Icon(Icons.lock, size: 14, color: context.gloam.accent),
            ),
          Text(
            isDirect ? '@' : '#',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 18, color: context.gloam.accent),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roomName,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.gloam.textPrimary,
                  ),
                ),
                if (topic.isNotEmpty)
                  Text(
                    topic,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: context.gloam.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Call buttons for DMs
          if (isDirect && roomId != null) ...[
            _HeaderAction(
              icon: Icons.call_outlined,
              onTap: () => _startCall(context, ref, roomId!, false),
            ),
            _HeaderAction(
              icon: Icons.videocam_outlined,
              onTap: () => _startCall(context, ref, roomId!, true),
            ),
          ],

          // Key icon — only show if there are undecryptable messages
          if (hasUndecryptable)
            Builder(
              builder: (ctx) => _HeaderAction(
                icon: Icons.key,
                onTap: () => showRecoveryKeyDialog(ctx),
              ),
            ),
          _HeaderAction(
              icon: Icons.search, onTap: onSearchTap ?? () {}),
          _HeaderAction(
              icon: Icons.people_outline, onTap: onMembersTap ?? () {}),
        ],
      ),
    );
  }

  void _startCall(BuildContext context, WidgetRef ref, String roomId, bool isVideo) {
    ref.read(callServiceProvider.notifier).startCall(
      roomId: roomId,
      isVideo: isVideo,
    );
    // Show outgoing call screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const OutgoingCallScreen(),
        fullscreenDialog: true,
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: context.gloam.textTertiary),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.gloam.textPrimary;
    return ListTile(
      leading: Icon(icon, size: 20, color: c),
      title: Text(
        label,
        style: GoogleFonts.inter(fontSize: 14, color: c),
      ),
      onTap: onTap,
      dense: true,
    );
  }
}

/// Collected thread metadata for a root message.
class _ThreadData {
  int replyCount = 0;
  final Map<String, ({String name, Uri? avatarUrl})> participants = {};
  DateTime? lastReplyTime;
}

/// Thread indicator shown below root messages that have thread replies.
/// Matches the Pencil prototype: overlapping avatars + reply count + last reply time.
class _ThreadIndicator extends StatelessWidget {
  const _ThreadIndicator({
    required this.data,
    required this.onTap,
  });

  final _ThreadData data;
  final VoidCallback onTap;

  String _formatTime(DateTime ts) {
    final h = ts.hour;
    final m = ts.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'pm' : 'am';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final replyWord = data.replyCount == 1 ? 'reply' : 'replies';
    final avatars = data.participants.values.take(5).toList();
    const avatarSize = 20.0;
    const overlap = 6.0;
    final avatarsWidth =
        avatarSize + (avatars.length - 1) * (avatarSize - overlap);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 48, top: 6, bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Overlapping participant avatars
            SizedBox(
              width: avatarsWidth,
              height: avatarSize,
              child: Stack(
                children: [
                  for (var i = 0; i < avatars.length; i++)
                    Positioned(
                      left: i * (avatarSize - overlap),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.gloam.bg,
                            width: 2,
                          ),
                        ),
                        child: GloamAvatar(
                          displayName: avatars[i].name,
                          mxcUrl: avatars[i].avatarUrl,
                          size: avatarSize - 4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${data.replyCount} $replyWord',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: context.gloam.accent,
              ),
            ),
            if (data.lastReplyTime != null) ...[
              const SizedBox(width: 8),
              Text(
                'last reply ${_formatTime(data.lastReplyTime!)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: context.gloam.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }
}

/// Zero state for rooms that are joined but waiting for the server
/// to deliver room state (e.g. restricted rooms pending full sync).
class _PendingRoomState extends StatelessWidget {
  const _PendingRoomState({
    required this.roomName,
    this.onLeave,
  });

  final String roomName;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 40,
                    color: colors.info,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Request sent',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for #$roomName to become available',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        _PendingStep(
                          icon: Icons.check_circle,
                          iconColor: colors.accent,
                          title: 'Join request sent',
                          subtitle: 'The server has received your request',
                        ),
                        const SizedBox(height: 12),
                        _PendingStep(
                          icon: Icons.sync,
                          iconColor: colors.info,
                          title: 'Waiting for room data',
                          subtitle:
                              'This can take a moment for restricted rooms. '
                              'You\'ll be able to chat once the room syncs.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.border),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule,
                  size: 14, color: colors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This room will appear when ready',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: colors.textTertiary,
                  ),
                ),
              ),
              if (onLeave != null)
                GestureDetector(
                  onTap: onLeave,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: colors.bgSurface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout,
                              size: 12, color: colors.textTertiary),
                          const SizedBox(width: 6),
                          Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PendingStep extends StatelessWidget {
  const _PendingStep({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: colors.textTertiary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
