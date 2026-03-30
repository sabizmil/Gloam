import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/timeline_provider.dart';
import 'delivery_indicator.dart';
import 'file_message.dart';
import 'hover_toolbar.dart';
import 'image_message.dart';
import 'reply_pill.dart';
import 'link_preview.dart';
import 'markdown_body.dart';
import '../../data/media_embed_resolver.dart';
import 'voice_message.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isGrouped,
    this.roomId,
    this.isOwnMessage = false,
    this.onAvatarTap,
    this.onReply,
    this.onEdit,
    this.onReact,
    this.onDelete,
    this.onThread,
    this.onCopy,
    this.onReplyTap,
  });

  final TimelineMessage message;
  final String? roomId;
  final bool isOwnMessage;
  final VoidCallback? onAvatarTap;

  /// True if this message is from the same sender as the previous one
  /// within the grouping window (no avatar/name shown).
  final bool isGrouped;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final void Function(String emoji)? onReact;
  final VoidCallback? onDelete;
  final VoidCallback? onThread;
  final VoidCallback? onCopy;
  final VoidCallback? onReplyTap;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _isHovered = false;

  String _formatTime(DateTime ts) {
    final h = ts.hour;
    final m = ts.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'pm' : 'am';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final message = widget.message;
    final isGrouped = widget.isGrouped;

    if (message.isRedacted) {
      return _RedactedMessage(isGrouped: isGrouped);
    }

    final opacity = message.sendState == MessageSendState.sending ? 0.6 : 1.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Opacity(
      opacity: opacity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
        padding: EdgeInsets.only(
          left: 0,
          right: 0,
          top: isGrouped ? 1 : 8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            if (!isGrouped)
              MouseRegion(
                cursor: widget.onAvatarTap != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  onTap: widget.onAvatarTap,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _HoverableAvatar(
                      displayName: message.senderName,
                      mxcUrl: message.senderAvatarUrl,
                      size: 36,
                    ),
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
                          MouseRegion(
                            cursor: widget.onAvatarTap != null
                                ? SystemMouseCursors.click
                                : SystemMouseCursors.basic,
                            child: GestureDetector(
                              onTap: widget.onAvatarTap,
                              child: Text(
                                message.senderName,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _senderColor(colors, message.senderName),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(message.timestamp),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: colors.textTertiary,
                            ),
                          ),
                          if (message.isEdited) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(edited)',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: colors.textTertiary,
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

                  // Reply preview pill
                  if (message.replyToBody != null)
                    ReplyPill(
                      senderName: message.replyToSenderName ?? '',
                      senderAvatarUrl: message.replyToSenderAvatarUrl,
                      body: message.replyToBody!,
                      onTap: widget.onReplyTap,
                    ),

                  // Message body
                  _MessageContent(message: message, roomId: widget.roomId),

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
                                  onTap: () => widget.onReact?.call(r.emoji),
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
          // Hover toolbar — positioned top-right
          if (_isHovered)
            Positioned(
              top: -4,
              right: 0,
              child: HoverToolbar(
                isOwnMessage: widget.isOwnMessage,
                messageBody: message.body,
                myReactions: message.reactions.values
                    .where((r) => r.includesMe)
                    .map((r) => r.emoji)
                    .toSet(),
                onReact: (emoji) => widget.onReact?.call(emoji),
                onReply: () => widget.onReply?.call(),
                onEdit: widget.isOwnMessage ? () => widget.onEdit?.call() : null,
                onDelete: widget.isOwnMessage ? () => widget.onDelete?.call() : null,
                onThread: () => widget.onThread?.call(),
                onCopy: () => widget.onCopy?.call(),
              ),
            ),
        ],
      ),
      ),
    );
  }

  static Color _senderColor(GloamColorExtension colors, String name) {
    final palette = [
      colors.accent,
      const Color(0xFF9090B8),
      const Color(0xFFC47070),
      const Color(0xFFC4A35C),
      const Color(0xFF5C8AC4),
      colors.accentBright,
      const Color(0xFF8A5CC4),
      const Color(0xFF5CC4C4),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.message, this.roomId});
  final TimelineMessage message;
  final String? roomId;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return switch (message.type) {
      'm.emote' => Text(
          '* ${message.senderName} ${message.body}',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: colors.textPrimary,
            height: 1.5,
          ),
        ),
      'm.notice' => Text(
          message.body,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
      'm.image' => ImageMessage(message: message, roomId: roomId),
      'm.video' => VideoMessage(message: message),
      'm.file' => FileMessage(message: message, roomId: roomId),
      'm.audio' => VoiceMessage(message: message),
      'm.bad_encrypted' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 14, color: colors.textTertiary),
            const SizedBox(width: 6),
            Text(
              'Unable to decrypt',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      _ => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hide the body text when the message is just a URL
            // that resolves to a rich media embed (image, GIF, YouTube, etc.)
            if (!_isMediaEmbedOnly(message.body))
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

/// True when the message body is nothing but a single URL that resolves
/// to a rich media embed (image, GIF, YouTube, etc.).
bool _isMediaEmbedOnly(String text) {
  final trimmed = text.trim();
  final match = RegExp(r'^https?://[^\s<>\[\]()]+$', caseSensitive: false)
      .firstMatch(trimmed);
  if (match == null) return false;
  return MediaEmbedResolver.resolve(trimmed) != null;
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({required this.reaction, this.onTap});
  final ReactionGroup reaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: reaction.includesMe
              ? colors.accentDim.withValues(alpha: 0.3)
              : colors.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: reaction.includesMe
                ? colors.accentDim
                : colors.border,
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
                    ? colors.accent
                    : colors.textSecondary,
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
          color: context.gloam.textTertiary,
        ),
      ),
    );
  }
}

/// Avatar with a subtle glow on hover.
class _HoverableAvatar extends StatefulWidget {
  const _HoverableAvatar({
    required this.displayName,
    this.mxcUrl,
    this.size = 36,
  });

  final String displayName;
  final Uri? mxcUrl;
  final double size;

  @override
  State<_HoverableAvatar> createState() => _HoverableAvatarState();
}

class _HoverableAvatarState extends State<_HoverableAvatar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: context.gloam.accent.withAlpha(40),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: GloamAvatar(
          displayName: widget.displayName,
          mxcUrl: widget.mxcUrl,
          size: widget.size,
        ),
      ),
    );
  }
}
