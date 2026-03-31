import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import 'emoji_picker.dart';

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
    this.onPinChanged,
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
  /// Called to pin/unpin the toolbar (keeps it visible while emoji picker is open).
  final void Function(bool pinned)? onPinChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Material(
      color: colors.bgElevated,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Container(
      height: 32,
      decoration: BoxDecoration(
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

          // More emoji picker
          _IconButton(
            icon: Icons.add,
            tooltip: 'More emoji',
            onTap: () => _openEmojiPicker(context),
          ),

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

          // Thread
          if (onThread != null)
            _IconButton(
              icon: Icons.chat_bubble_outline,
              tooltip: 'Thread',
              onTap: onThread,
            ),

          // Edit (own messages only)
          if (isOwnMessage)
            _IconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit',
              onTap: onEdit,
            ),

          // Copy
          _IconButton(
            icon: Icons.content_copy,
            tooltip: 'Copy',
            onTap: () {
              Clipboard.setData(ClipboardData(text: messageBody));
              onCopy?.call();
            },
          ),

          // Delete (own messages only)
          if (isOwnMessage)
            _IconButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              onTap: onDelete,
              iconColor: context.gloam.danger,
            ),
        ],
      ),
      ),
    );
  }

  void _openEmojiPicker(BuildContext context) async {
    onPinChanged?.call(true);

    final RenderBox box = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero, ancestor: overlay);

    const pickerHeight = 420.0;
    final spaceAbove = pos.dy;
    final rightPos = overlay.size.width - (pos.dx + box.size.width);

    final String? emoji;
    if (spaceAbove >= pickerHeight + 8) {
      // Enough room above — open upward (default)
      emoji = await showEmojiPickerAt(
        context,
        bottom: overlay.size.height - pos.dy + 4,
        right: rightPos,
      );
    } else {
      // Not enough room above — flip to open below the toolbar
      emoji = await showEmojiPickerAt(
        context,
        top: pos.dy + box.size.height + 4,
        right: rightPos,
      );
    }

    onPinChanged?.call(false);
    if (emoji != null) onReact(emoji);
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
      mouseCursor: SystemMouseCursors.click,
      hoverColor: context.gloam.border.withValues(alpha: 0.8),
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
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        hoverColor: context.gloam.border.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Icon(icon, size: 15, color: iconColor ?? context.gloam.textSecondary),
          ),
        ),
      ),
    );
  }
}
