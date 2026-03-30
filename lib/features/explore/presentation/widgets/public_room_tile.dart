import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../widgets/gloam_avatar.dart';

/// A single room card in the Explore directory.
///
/// Shows avatar, name, alias, topic, member count, and join/joined button.
class PublicRoomTile extends StatelessWidget {
  const PublicRoomTile({
    super.key,
    required this.room,
    required this.isJoined,
    required this.isJoining,
    required this.onJoin,
    this.onOpen,
  });

  final PublicRoomsChunk room;
  final bool isJoined;
  final bool isJoining;
  final VoidCallback onJoin;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final isSpace = room.roomType == 'm.space';
    final name = room.name ?? room.canonicalAlias ?? room.roomId;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.gloam.borderSubtle),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isJoined ? onOpen : onJoin,
          hoverColor: context.gloam.bgElevated,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
            child: Row(
              children: [
                // Avatar
                GloamAvatar(
                  displayName: name,
                  mxcUrl: room.avatarUrl,
                  size: 44,
                  borderRadius: 8,
                ),
                const SizedBox(width: 16),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isSpace)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(Icons.grid_view_rounded,
                                  size: 14, color: context.gloam.accent),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text('#',
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 14,
                                      color: context.gloam.textTertiary)),
                            ),
                          Flexible(
                            child: Text(
                              name,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.gloam.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (room.canonicalAlias != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                room.canonicalAlias!,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: context.gloam.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (room.topic != null && room.topic!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            room.topic!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: context.gloam.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Right: count + button
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatCount(room.numJoinedMembers),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: context.gloam.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _JoinButton(
                      isJoined: isJoined,
                      isJoining: isJoining,
                      onTap: isJoined ? onOpen : onJoin,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}k';
    }
    return '$count';
  }
}

class _JoinButton extends StatelessWidget {
  const _JoinButton({
    required this.isJoined,
    required this.isJoining,
    this.onTap,
  });

  final bool isJoined;
  final bool isJoining;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (isJoining) {
      return Container(
        height: 28,
        width: 64,
        decoration: BoxDecoration(
          color: context.gloam.accentDim,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        ),
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: context.gloam.accent),
          ),
        ),
      );
    }

    if (isJoined) {
      return Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.gloam.bgSurface,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
          border: Border.all(color: context.gloam.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 12, color: context.gloam.textTertiary),
            const SizedBox(width: 4),
            Text(
              'Joined',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: context.gloam.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.gloam.accentDim,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        ),
        child: Center(
          child: Text(
            'Join',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.gloam.accent,
            ),
          ),
        ),
      ),
    );
  }
}
