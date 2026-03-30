import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/timeline_provider.dart';
import 'message_bubble.dart';

/// Right panel for viewing a message thread.
class ThreadPanel extends ConsumerStatefulWidget {
  const ThreadPanel({
    super.key,
    required this.roomId,
    required this.rootMessage,
    required this.onClose,
  });

  final String roomId;
  final TimelineMessage rootMessage;
  final VoidCallback onClose;

  @override
  ConsumerState<ThreadPanel> createState() => _ThreadPanelState();
}

class _ThreadPanelState extends ConsumerState<ThreadPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref
        .read(timelineProvider(widget.roomId).notifier)
        .sendThreadReply(text, widget.rootMessage.eventId);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final allMessages = ref.watch(timelineProvider(widget.roomId));

    // Filter thread replies — m.thread relation OR legacy m.in_reply_to
    final threadReplies = allMessages
        .where((m) =>
            m.threadRootEventId == widget.rootMessage.eventId ||
            (!m.isThreadReply &&
                m.replyToEventId == widget.rootMessage.eventId))
        .toList();

    // Extract unique participants
    final participants = <String, ({String name, Uri? avatarUrl})>{};
    for (final reply in threadReplies) {
      participants.putIfAbsent(
        reply.senderId,
        () => (name: reply.senderName, avatarUrl: reply.senderAvatarUrl),
      );
    }

    return Container(
      width: GloamSpacing.threadPanelWidth,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border(
          left: BorderSide(color: colors.border),
        ),
      ),
      child: Column(
        children: [
          // ── Header ──
          _buildHeader(),

          // ── Root message ──
          _buildRootMessage(),

          // ── Metadata: reply count · participants ──
          _buildMetadata(threadReplies, participants),

          // ── Thread replies ──
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              itemCount: threadReplies.length,
              itemBuilder: (context, index) {
                final msg = threadReplies[index];
                final prevMsg =
                    index > 0 ? threadReplies[index - 1] : null;
                final isGrouped = prevMsg != null &&
                    prevMsg.senderId == msg.senderId &&
                    msg.timestamp.difference(prevMsg.timestamp).inMinutes <
                        3;

                return MessageBubble(
                  message: msg,
                  isGrouped: isGrouped,
                );
              },
            ),
          ),

          // ── Composer ──
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final colors = context.gloam;
    return Container(
      height: GloamSpacing.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 16, color: colors.accent),
          const SizedBox(width: 8),
          Text(
            'Thread',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: widget.onClose,
            child: Icon(Icons.close,
                size: 16, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildRootMessage() {
    final colors = context.gloam;
    final root = widget.rootMessage;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GloamAvatar(
            displayName: root.senderName,
            mxcUrl: root.senderAvatarUrl,
            size: 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      root.senderName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(root.timestamp),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  root.body,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: colors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadata(
    List<TimelineMessage> replies,
    Map<String, ({String name, Uri? avatarUrl})> participants,
  ) {
    if (replies.isEmpty) return const SizedBox.shrink();

    final colors = context.gloam;
    final replyWord = replies.length == 1 ? 'reply' : 'replies';
    final partWord =
        participants.length == 1 ? 'participant' : 'participants';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: Row(
        children: [
          // Reply count · participant count
          Expanded(
            child: Row(
              children: [
                Text(
                  '${replies.length} $replyWord',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
                Container(
                  width: 3,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: colors.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  '${participants.length} $partWord',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),

          // Overlapping participant avatars
          SizedBox(
            height: 22,
            child: _buildParticipantAvatars(participants),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantAvatars(
    Map<String, ({String name, Uri? avatarUrl})> participants,
  ) {
    final colors = context.gloam;
    final entries = participants.values.take(5).toList();
    const size = 22.0;
    const overlap = 6.0;
    final totalWidth = size + (entries.length - 1) * (size - overlap);

    return SizedBox(
      width: totalWidth,
      child: Stack(
        children: [
          for (var i = 0; i < entries.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.bgSurface,
                    width: 2,
                  ),
                ),
                child: GloamAvatar(
                  displayName: entries[i].name,
                  mxcUrl: entries[i].avatarUrl,
                  size: size - 4, // account for border
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final colors = context.gloam;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius:
                    BorderRadius.circular(GloamSpacing.radiusSm),
                border: Border.all(color: colors.border),
              ),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: _controller,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Reply in thread...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 13,
                    color: colors.textTertiary,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colors.accentDim,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                size: 16,
                color: colors.accentBright,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime ts) {
    final h = ts.hour;
    final m = ts.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'pm' : 'am';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:$m $period';
  }
}
