import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/room_list_provider.dart';

class RoomListTile extends StatelessWidget {
  const RoomListTile({
    super.key,
    required this.room,
    this.isActive = false,
    this.onTap,
  });

  final RoomListItem room;
  final bool isActive;
  final VoidCallback? onTap;

  String _formatTimestamp(DateTime? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${ts.month}/${ts.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${room.displayName}. ${room.unreadCount > 0 ? '${room.unreadCount} unread.' : ''} ${room.lastMessagePreview ?? ''}',
      child: Material(
      color: isActive ? context.gloam.bgElevated : Colors.transparent,
      borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        hoverColor: context.gloam.bgElevated,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // Avatar
              GloamAvatar(
                displayName: room.displayName,
                mxcUrl: room.avatarUrl,
                size: 36,
                borderRadius: room.isDirect ? null : 8,
              ),
              const SizedBox(width: 10),

              // Name + preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      room.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: room.unreadCount > 0 || isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isActive
                            ? context.gloam.textPrimary
                            : room.unreadCount > 0
                                ? context.gloam.textPrimary
                                : context.gloam.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (room.lastMessagePreview != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        room.isDirect
                            ? room.lastMessagePreview!
                            : '${room.lastMessageSender ?? ''}: ${room.lastMessagePreview!}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isActive
                              ? context.gloam.textSecondary
                              : context.gloam.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Timestamp + badge + muted indicator
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (room.isMuted)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.notifications_off,
                              size: 11, color: context.gloam.textTertiary),
                        ),
                      Text(
                        _formatTimestamp(room.lastMessageTimestamp),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: room.unreadCount > 0 && !room.isMuted
                              ? context.gloam.accent
                              : context.gloam.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  if (room.unreadCount > 0 && !room.isMuted) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: room.mentionCount > 0
                            ? context.gloam.accent
                            : context.gloam.accentDim,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        room.unreadCount > 99
                            ? '99+'
                            : '${room.unreadCount}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: room.mentionCount > 0
                              ? context.gloam.bg
                              : context.gloam.accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
