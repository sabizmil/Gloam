import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../../../profile/presentation/user_profile_modal.dart';
import '../providers/following_provider.dart';

/// Presence strip below the chat header showing who's following
/// the conversation (their read receipt matches the latest event).
/// Shows up to 3 overlapping avatars and names.
class FollowingBar extends ConsumerWidget {
  const FollowingBar({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followers = ref.watch(followingProvider(roomId));
    if (followers.isEmpty) return const SizedBox.shrink();

    final shown = followers.take(3).toList();
    final othersCount = followers.length - shown.length;
    final isPlural = followers.length > 1;

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
            // Online dot
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: context.gloam.online,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),

            // Overlapping avatar stack
            _AvatarStack(
              followers: shown,
              roomId: roomId,
            ),
            const SizedBox(width: 8),

            // Names text
            Expanded(
              child: Text.rich(
                TextSpan(children: _buildNameSpans(context, shown, othersCount, isPlural)),
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
              'last read ${_relativeTime(followers.first.lastReadTs)}',
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

  List<InlineSpan> _buildNameSpans(
    BuildContext context,
    List<FollowingUser> shown,
    int othersCount,
    bool isPlural,
  ) {
    final bold = GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: context.gloam.textSecondary,
    );
    final normal = GoogleFonts.inter(
      fontSize: 11,
      color: context.gloam.textTertiary,
    );

    final spans = <InlineSpan>[];

    if (shown.length == 1 && othersCount == 0) {
      // "Name is following..."
      spans.add(TextSpan(text: shown[0].displayName, style: bold));
    } else if (shown.length == 2 && othersCount == 0) {
      // "Name and Name are following..."
      spans.add(TextSpan(text: shown[0].displayName, style: bold));
      spans.add(TextSpan(text: ' and ', style: normal));
      spans.add(TextSpan(text: shown[1].displayName, style: bold));
    } else if (shown.length == 3 && othersCount == 0) {
      // "Name, Name, and Name are following..."
      spans.add(TextSpan(text: shown[0].displayName, style: bold));
      spans.add(TextSpan(text: ', ', style: normal));
      spans.add(TextSpan(text: shown[1].displayName, style: bold));
      spans.add(TextSpan(text: ', and ', style: normal));
      spans.add(TextSpan(text: shown[2].displayName, style: bold));
    } else {
      // "Name, Name, Name, and N others are following..."
      for (var i = 0; i < shown.length; i++) {
        if (i > 0) spans.add(TextSpan(text: ', ', style: normal));
        spans.add(TextSpan(text: shown[i].displayName, style: bold));
      }
      spans.add(TextSpan(
        text: ', and $othersCount ${othersCount == 1 ? 'other' : 'others'}',
        style: normal,
      ));
    }

    spans.add(TextSpan(
      text: isPlural
          ? ' are following the conversation'
          : ' is following the conversation',
      style: normal,
    ));

    return spans;
  }

  String _relativeTime(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Overlapping avatar stack — up to 3 avatars with border separation.
class _AvatarStack extends ConsumerWidget {
  const _AvatarStack({required this.followers, required this.roomId});

  final List<FollowingUser> followers;
  final String roomId;

  static const double _size = 20.0;
  static const double _overlap = 6.0;
  static const double _border = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalWidth = _size + (followers.length - 1) * (_size - _overlap);

    return SizedBox(
      width: totalWidth,
      height: _size + _border * 2,
      child: Stack(
        children: [
          for (var i = 0; i < followers.length; i++)
            Positioned(
              left: i * (_size - _overlap),
              child: Tooltip(
                message: followers[i].displayName,
                waitDuration: const Duration(milliseconds: 300),
                child: GestureDetector(
                  onTap: () => showUserProfile(
                    context, ref,
                    userId: followers[i].userId,
                    roomId: roomId,
                  ),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.gloam.bgSurface,
                          width: _border,
                        ),
                      ),
                      child: GloamAvatar(
                        displayName: followers[i].displayName,
                        mxcUrl: followers[i].avatarUrl,
                        size: _size,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
