import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../widgets/gloam_avatar.dart';

/// Compact pill/chip that previews the message being replied to.
///
/// Shows: reply icon · mini avatar · sender name · truncated body.
/// Tapping scrolls the timeline to the original message.
class ReplyPill extends StatefulWidget {
  const ReplyPill({
    super.key,
    required this.senderName,
    this.senderAvatarUrl,
    required this.body,
    this.onTap,
  });

  final String senderName;
  final Uri? senderAvatarUrl;
  final String body;
  final VoidCallback? onTap;

  @override
  State<ReplyPill> createState() => _ReplyPillState();
}

class _ReplyPillState extends State<ReplyPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _isHovered ? context.gloam.bgSurface : context.gloam.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? context.gloam.accent.withValues(alpha: 0.4) : context.gloam.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.reply_rounded,
                size: 12,
                color: context.gloam.textTertiary,
              ),
              const SizedBox(width: 6),
              GloamAvatar(
                displayName: widget.senderName,
                mxcUrl: widget.senderAvatarUrl,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                widget.senderName,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.gloam.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.body,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: context.gloam.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
