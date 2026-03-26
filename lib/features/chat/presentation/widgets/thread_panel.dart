import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/timeline_provider.dart';
import 'message_bubble.dart';

/// Right panel for viewing a message thread.
class ThreadPanel extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final allMessages = ref.watch(timelineProvider(roomId));

    // Filter thread replies — messages that reply to the root
    final threadReplies = allMessages
        .where((m) => m.replyToEventId == rootMessage.eventId)
        .toList();

    return Container(
      width: GloamSpacing.threadPanelWidth,
      decoration: const BoxDecoration(
        color: GloamColors.bgSurface,
        border: Border(
          left: BorderSide(color: GloamColors.border),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: GloamSpacing.headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: GloamColors.border),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline,
                    size: 16, color: GloamColors.accent),
                const SizedBox(width: 8),
                Text(
                  'thread',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: GloamColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close,
                      size: 16, color: GloamColors.textTertiary),
                ),
              ],
            ),
          ),

          // Root message
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: GloamColors.border),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GloamAvatar(
                    displayName: rootMessage.senderName, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            rootMessage.senderName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: GloamColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(rootMessage.timestamp),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: GloamColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rootMessage.body,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: GloamColors.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Reply count
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              '${threadReplies.length} ${threadReplies.length == 1 ? 'reply' : 'replies'}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: GloamColors.textTertiary,
                letterSpacing: 1,
              ),
            ),
          ),

          // Thread replies
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: threadReplies.length,
              itemBuilder: (context, index) {
                final msg = threadReplies[index];
                final prevMsg = index > 0 ? threadReplies[index - 1] : null;
                final isGrouped = prevMsg != null &&
                    prevMsg.senderId == msg.senderId &&
                    msg.timestamp.difference(prevMsg.timestamp).inMinutes < 3;

                return MessageBubble(
                  message: msg,
                  isGrouped: isGrouped,
                );
              },
            ),
          ),

          // Thread composer
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: GloamColors.border),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: GloamColors.bg,
                      borderRadius:
                          BorderRadius.circular(GloamSpacing.radiusSm),
                      border: Border.all(color: GloamColors.border),
                    ),
                    alignment: Alignment.centerLeft,
                    child: TextField(
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: GloamColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'reply in thread...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: GloamColors.textTertiary,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onSubmitted: (text) {
                        if (text.trim().isEmpty) return;
                        ref
                            .read(timelineProvider(roomId).notifier)
                            .sendReply(text, rootMessage.eventId);
                      },
                    ),
                  ),
                ),
              ],
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
