import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/timeline_provider.dart';
import 'delivery_indicator.dart';
import 'file_message.dart';
import 'image_message.dart';
import 'link_preview.dart';
import 'markdown_body.dart';
import 'voice_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isGrouped,
    this.roomId,
    this.onReply,
    this.onEdit,
    this.onReact,
    this.onDelete,
  });

  final TimelineMessage message;
  final String? roomId;

  /// True if this message is from the same sender as the previous one
  /// within the grouping window (no avatar/name shown).
  final bool isGrouped;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final void Function(String emoji)? onReact;
  final VoidCallback? onDelete;

  String _formatTime(DateTime ts) {
    final h = ts.hour;
    final m = ts.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'pm' : 'am';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    if (message.isRedacted) {
      return _RedactedMessage(isGrouped: isGrouped);
    }

    final opacity = message.sendState == MessageSendState.sending ? 0.6 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: EdgeInsets.only(
          left: 0,
          right: 0,
          top: isGrouped ? 1 : 8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar — Align prevents Row from stretching it vertically
            if (!isGrouped)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: GloamAvatar(
                    displayName: message.senderName,
                    mxcUrl: message.senderAvatarUrl,
                    size: 36,
                  ),
                ),
              )
            else
              const SizedBox(width: 48),

            // Content column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender + timestamp
                  if (!isGrouped)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Text(
                            message.senderName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _senderColor(message.senderName),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(message.timestamp),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: GloamColors.textTertiary,
                            ),
                          ),
                          if (message.isEdited) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(edited)',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: GloamColors.textTertiary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          if (message.sendState != MessageSendState.sent) ...[
                            const SizedBox(width: 4),
                            DeliveryIndicator(state: message.sendState),
                          ],
                        ],
                      ),
                    ),

                  // Reply preview
                  if (message.replyToBody != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(
                              color: GloamColors.accent, width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.replyToSenderName ?? '',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: GloamColors.textSecondary,
                            ),
                          ),
                          Text(
                            message.replyToBody!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: GloamColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                  // Message body
                  _MessageContent(message: message, roomId: roomId),

                  // Reactions
                  if (message.reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: message.reactions.values
                            .map((r) => _ReactionPill(
                                  reaction: r,
                                  onTap: () => onReact?.call(r.emoji),
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _senderColor(String name) {
    final colors = [
      GloamColors.accent,
      const Color(0xFF9090B8),
      const Color(0xFFC47070),
      const Color(0xFFC4A35C),
      const Color(0xFF5C8AC4),
      GloamColors.accentBright,
      const Color(0xFF8A5CC4),
      const Color(0xFF5CC4C4),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.message, this.roomId});
  final TimelineMessage message;
  final String? roomId;

  @override
  Widget build(BuildContext context) {
    return switch (message.type) {
      'm.emote' => Text(
          '* ${message.senderName} ${message.body}',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: GloamColors.textPrimary,
            height: 1.5,
          ),
        ),
      'm.notice' => Text(
          message.body,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: GloamColors.textSecondary,
            height: 1.5,
          ),
        ),
      'm.image' => ImageMessage(message: message, roomId: roomId),
      'm.video' => VideoMessage(message: message),
      'm.file' => FileMessage(message: message),
      'm.audio' => VoiceMessage(message: message),
      _ => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              text: message.body,
              formattedBody: message.formattedBody,
            ),
            if (_hasUrl(message.body))
              LinkPreview(body: message.body),
          ],
        ),
    };
  }
}

bool _hasUrl(String text) =>
    RegExp(r'https?://[^\s<>\[\]()]+', caseSensitive: false).hasMatch(text);

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({required this.reaction, this.onTap});
  final ReactionGroup reaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: reaction.includesMe
              ? GloamColors.accentDim.withValues(alpha: 0.3)
              : GloamColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: reaction.includesMe
                ? GloamColors.accentDim
                : GloamColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reaction.emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              '${reaction.count}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: reaction.includesMe
                    ? GloamColors.accent
                    : GloamColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RedactedMessage extends StatelessWidget {
  const _RedactedMessage({required this.isGrouped});
  final bool isGrouped;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 48, top: isGrouped ? 1 : 8),
      child: Text(
        '[message deleted]',
        style: GoogleFonts.inter(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: GloamColors.textTertiary,
        ),
      ),
    );
  }
}
