import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';
import '../providers/timeline_provider.dart';
import '../widgets/date_separator.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import '../widgets/typing_indicator.dart';
import '../../../../app/shell/right_panel.dart';
import '../../../settings/presentation/recovery_key_dialog.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  ComposerState _composerState = ComposerState.normal;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
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

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
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
    final messages = ref.watch(timelineProvider(widget.roomId));
    final client = ref.watch(matrixServiceProvider).client;
    final room = client?.getRoomById(widget.roomId);
    final roomName = room?.getLocalizedDisplayname() ?? '';
    final topic = room?.topic ?? '';
    final memberCount = room?.summary.mJoinedMemberCount ?? 0;
    final myUserId = client?.userID;

    return Column(
      children: [
        // Header
        _ChatHeader(
          roomName: roomName,
          topic: topic,
          memberCount: memberCount,
          isEncrypted: room?.encrypted ?? false,
          onInfoTap: () => ref.read(rightPanelProvider.notifier).state =
              const RightPanelState(view: RightPanelView.roomInfo),
          onMembersTap: () => ref.read(rightPanelProvider.notifier).state =
              const RightPanelState(view: RightPanelView.members),
        ),

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
                    children: [
                      if (showDateSep)
                        DateSeparator(date: msg.timestamp),
                      GestureDetector(
                        onLongPress: () => _showMessageActions(context, msg,
                            isOwnMessage: msg.senderId == myUserId),
                        onSecondaryTap: () => _showMessageActions(
                            context, msg,
                            isOwnMessage: msg.senderId == myUserId),
                        child: MessageBubble(
                          message: msg,
                          isGrouped: isGrouped,
                          onReply: () => _handleReplyAction(msg),
                          onEdit: () => _handleEditAction(msg),
                          onReact: (emoji) => ref
                              .read(
                                  timelineProvider(widget.roomId).notifier)
                              .react(msg.eventId, emoji),
                          onDelete: () => ref
                              .read(
                                  timelineProvider(widget.roomId).notifier)
                              .redactMessage(msg.eventId),
                        ),
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
          onEdit: (text, eventId) => ref
              .read(timelineProvider(widget.roomId).notifier)
              .editMessage(eventId, text),
          onTyping: (isTyping) => ref
              .read(timelineProvider(widget.roomId).notifier)
              .setTyping(isTyping),
          onCancelAction: () =>
              setState(() => _composerState = ComposerState.normal),
        ),
      ],
    );
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
                Navigator.pop(ctx);
              },
            ),
            if (isOwnMessage)
              _ActionTile(
                icon: Icons.delete_outline,
                label: 'delete',
                color: GloamColors.danger,
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(timelineProvider(widget.roomId).notifier)
                      .redactMessage(msg.eventId);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.roomName,
    required this.topic,
    required this.memberCount,
    required this.isEncrypted,
    this.onInfoTap,
    this.onMembersTap,
  });

  final String roomName;
  final String topic;
  final int memberCount;
  final bool isEncrypted;
  final VoidCallback? onInfoTap;
  final VoidCallback? onMembersTap;

  @override
  Widget build(BuildContext context) {
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
            '#',
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

          // Header actions
          if (isEncrypted)
            Builder(
              builder: (ctx) => _HeaderAction(
                icon: Icons.key,
                onTap: () => showRecoveryKeyDialog(ctx),
              ),
            ),
          _HeaderAction(icon: Icons.search, onTap: () {}),
          _HeaderAction(
              icon: Icons.push_pin_outlined, onTap: onInfoTap ?? () {}),
          _HeaderAction(
              icon: Icons.people_outline, onTap: onMembersTap ?? () {}),
        ],
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
