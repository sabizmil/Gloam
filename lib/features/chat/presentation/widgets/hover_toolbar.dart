import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';

/// Floating action toolbar that appears on message hover.
/// Quick-react emoji + reply/edit/overflow, positioned top-right.
class HoverToolbar extends StatelessWidget {
  const HoverToolbar({
    super.key,
    required this.isOwnMessage,
    required this.messageBody,
    required this.onReact,
    required this.onReply,
    this.onEdit,
    this.onDelete,
    this.onCopy,
    this.onThread,
    this.myReactions = const {},
  });

  final bool isOwnMessage;
  final String messageBody;
  final void Function(String emoji) onReact;
  final VoidCallback onReply;
  /// Set of emoji that the current user has already reacted with.
  final Set<String> myReactions;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onThread;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF080F0A).withValues(alpha: 0.6),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick-react emoji (highlighted if already reacted)
          _EmojiButton(emoji: '👍', isActive: myReactions.contains('👍'), onTap: () => onReact('👍')),
          _EmojiButton(emoji: '❤️', isActive: myReactions.contains('❤️'), onTap: () => onReact('❤️')),
          _EmojiButton(emoji: '😂', isActive: myReactions.contains('😂'), onTap: () => onReact('😂')),

          // Divider
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: colors.border,
          ),

          // Reply
          _IconButton(
            icon: Icons.reply,
            tooltip: 'Reply',
            onTap: onReply,
          ),

          // Edit (own messages only)
          if (isOwnMessage)
            _IconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit',
              onTap: onEdit,
            ),

          // Overflow → context menu
          _IconButton(
            icon: Icons.more_horiz,
            tooltip: 'More',
            onTap: () => _showOverflow(context),
          ),
        ],
      ),
    );
  }

  void _showOverflow(BuildContext context) {
    final colors = context.gloam;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      items: [
        _menuItem(colors, 'copy', Icons.content_copy, 'Copy text'),
        if (onThread != null)
          _menuItem(colors, 'thread', Icons.chat_bubble_outline, 'Thread'),
        if (isOwnMessage)
          _menuItem(colors, 'delete', Icons.delete_outline, 'Delete',
              danger: true),
      ],
    ).then((value) {
      switch (value) {
        case 'copy':
          Clipboard.setData(ClipboardData(text: messageBody));
          onCopy?.call();
        case 'thread':
          onThread?.call();
        case 'delete':
          onDelete?.call();
      }
    });
  }

  PopupMenuItem<String> _menuItem(
    GloamColorExtension colors,
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final color = danger ? colors.danger : colors.textPrimary;
    return PopupMenuItem(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label,
              style: GoogleFonts.inter(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.emoji, required this.onTap, this.isActive = false});
  final String emoji;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        decoration: isActive
            ? BoxDecoration(
                color: context.gloam.accentDim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 15))),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Icon(icon, size: 15, color: context.gloam.textSecondary),
          ),
        ),
      ),
    );
  }
}
