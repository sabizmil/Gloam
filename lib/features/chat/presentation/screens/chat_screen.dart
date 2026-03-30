import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../../../../services/upload_service.dart';
import '../providers/timeline_provider.dart';
import '../widgets/date_separator.dart';
import '../widgets/drop_overlay.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import '../widgets/syncing_zero_state.dart';
import '../widgets/typing_indicator.dart';
import '../../../../app/shell/right_panel.dart';
import '../../../calls/presentation/providers/call_provider.dart';
import '../../../calls/presentation/screens/outgoing_call_screen.dart';
import '../../../profile/presentation/user_profile_modal.dart';
import '../../../settings/presentation/recovery_key_dialog.dart';

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
  final _messageKeys = <String, GlobalKey>{};
  ComposerState _composerState = ComposerState.normal;
  bool _showScrollToBottom = false;
  String? _highlightEventId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Mark room as actively viewed — auto-sends read receipts
    // on init and whenever new messages arrive
    Future.microtask(() {
      ref.read(timelineProvider(widget.roomId).notifier).setActive(true);
    });
  }

  @override
  void dispose() {
    ref.read(timelineProvider(widget.roomId).notifier).setActive(false);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final showBtn = _scrollController.hasClients &&
        _scrollController.position.pixels > 200;
    if (showBtn != _showScrollToBottom) {
      setState(() => _showScrollToBottom = showBtn);
    }

    // Load more when near the top (reversed list = near max scroll extent)
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      ref.read(timelineProvider(widget.roomId).notifier).loadMore();
    }
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Scroll to a specific message and briefly highlight it.
  void _scrollToMessage(String eventId) {
    final key = _messageKeys[eventId];
    final ctx = key?.currentContext;
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
          SnackBar(content: Text(sizeError), backgroundColor: GloamColors.danger),
        );
        return;
      }

      final matrixFile = await UploadService.fromPath(picked.path!);
      ref.read(timelineProvider(widget.roomId).notifier).sendFileMessage(matrixFile);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('upload failed: $e'), backgroundColor: GloamColors.danger),
        );
      }
    }
  }

  Future<void> _handleDroppedFiles(List<DropDoneDetails> detailsList) async {
    for (final details in detailsList) {
      for (final xFile in details.files) {
        try {
          final bytes = await xFile.readAsBytes();

          final sizeError = UploadService.validateFileSize(bytes.length);
          if (sizeError != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(sizeError), backgroundColor: GloamColors.danger),
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
              SnackBar(content: Text('upload failed: $e'), backgroundColor: GloamColors.danger),
            );
          }
        }
      }
    }
  }

  void _confirmDelete(String eventId) {
    showDialog(
      context: context,
      barrierColor: GloamColors.overlay,
      builder: (ctx) => AlertDialog(
        backgroundColor: GloamColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: GloamColors.border),
        ),
        title: Text(
          'delete message?',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: GloamColors.textPrimary,
          ),
        ),
        content: Text(
          'this can\'t be undone.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: GloamColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: GloamColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: GloamColors.danger),
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
                        backgroundColor: GloamColors.danger),
                  );
                }
              }
            },
            child: Text('delete',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: GloamColors.textPrimary)),
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
    final roomName = room?.getLocalizedDisplayname() ?? '';
    final topic = room?.topic ?? '';
    final memberCount = room?.summary.mJoinedMemberCount ?? 0;
    final myUserId = client?.userID;

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

    return FileDropZone(
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

        // Syncing zero state: joined but no messages yet
        if (messages.isEmpty && room?.lastEvent == null && !widget.compact)
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

                  return Column(
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
                          key: _messageKeys.putIfAbsent(
                            msg.eventId,
                            () => GlobalKey(),
                          ),
                          duration: const Duration(milliseconds: 500),
                          decoration: BoxDecoration(
                            color: _highlightEventId == msg.eventId
                                ? GloamColors.bgElevated
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
                                ? () => _scrollToMessage(msg.replyToEventId!)
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

              // Scroll-to-bottom FAB
              if (_showScrollToBottom)
                Positioned(
                  right: 20,
                  bottom: 12,
                  child: Material(
                    color: GloamColors.bgElevated,
                    shape: const CircleBorder(
                      side: BorderSide(color: GloamColors.border),
                    ),
                    elevation: 0,
                    child: InkWell(
                      onTap: _scrollToBottom,
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.keyboard_arrow_down,
                            size: 20, color: GloamColors.textSecondary),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Typing indicator
        TypingIndicator(roomId: widget.roomId),

        // Composer
        MessageComposer(
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
                      backgroundColor: GloamColors.danger),
                );
              }
            }
          },
          onEditLastMessage: _editLastMessage,
          onTyping: (isTyping) => ref
              .read(timelineProvider(widget.roomId).notifier)
              .setTyping(isTyping),
          onAttach: () => _pickAndUploadFile(),
          onCancelAction: () =>
              setState(() => _composerState = ComposerState.normal),
        ),
        ], // end else (has messages)
      ],
    ));
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
      backgroundColor: GloamColors.bgSurface,
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
            const Divider(color: GloamColors.border, height: 1),
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
                color: GloamColors.danger,
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
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: GloamColors.border),
        ),
      ),
      child: Row(
        children: [
          // Room info
          if (isEncrypted)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child:
                  Icon(Icons.lock, size: 14, color: GloamColors.accent),
            ),
          Text(
            isDirect ? '@' : '#',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 18, color: GloamColors.accent),
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
                    color: GloamColors.textPrimary,
                  ),
                ),
                if (topic.isNotEmpty)
                  Text(
                    topic,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: GloamColors.textTertiary,
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
      icon: Icon(icon, size: 18, color: GloamColors.textTertiary),
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
    final c = color ?? GloamColors.textPrimary;
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
                            color: GloamColors.bg,
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
                color: GloamColors.accent,
              ),
            ),
            if (data.lastReplyTime != null) ...[
              const SizedBox(width: 8),
              Text(
                'last reply ${_formatTime(data.lastReplyTime!)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: GloamColors.textTertiary,
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
