import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/following_provider.dart';

/// Presence strip below the chat header showing who's following
/// the conversation (their read receipt matches the latest event).
class FollowingBar extends ConsumerWidget {
  const FollowingBar({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followers = ref.watch(followingProvider(roomId));
    if (followers.isEmpty) return const SizedBox.shrink();

    final first = followers.first;
    final othersCount = followers.length - 1;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: context.gloam.bgSurface,
          border: Border(
            bottom: BorderSide(color: context.gloam.border),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: context.gloam.online,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            GloamAvatar(
              displayName: first.displayName,
              mxcUrl: first.avatarUrl,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: first.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.gloam.textSecondary,
                      ),
                    ),
                    if (othersCount > 0)
                      TextSpan(
                        text: ' and $othersCount ${othersCount == 1 ? 'other' : 'others'}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: context.gloam.textTertiary,
                        ),
                      ),
                    TextSpan(
                      text: othersCount > 0
                          ? ' are following the conversation'
                          : ' is following the conversation',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: context.gloam.textTertiary,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '·',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: context.gloam.textTertiary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'last read ${_relativeTime(first.lastReadTs)}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: context.gloam.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
