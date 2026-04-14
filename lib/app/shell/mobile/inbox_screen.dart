import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../theme/gloam_theme_ext.dart';
import '../../theme/spacing.dart';
import '../../../features/chat/presentation/providers/timeline_provider.dart';
import '../../../services/matrix_service.dart';
import '../../../widgets/gloam_avatar.dart';

/// Mobile `inbox` tab — "things that need your attention":
///   - Invites (room + space) at the top — actionable
///   - Mentions (rooms with highlightCount > 0) below
///
/// Threads-I'm-in section is intentionally deferred; see brainstorm.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixServiceProvider).client;

    // Rebuild on each sync so counts + invites stay fresh.
    ref.watch(_inboxTickProvider);

    final rooms = client?.rooms ?? const <Room>[];
    final invites =
        rooms.where((r) => r.membership == Membership.invite).toList();
    final mentions = rooms
        .where((r) =>
            r.membership == Membership.join && r.highlightCount > 0)
        .toList();

    return Column(
      children: [
        _Header(),
        Expanded(
          child: (invites.isEmpty && mentions.isEmpty)
              ? _EmptyState()
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (invites.isNotEmpty) ...[
                      _SectionHeader(label: 'invites', count: invites.length),
                      for (final room in invites)
                        _InviteTile(room: room),
                      const SizedBox(height: 12),
                    ],
                    if (mentions.isNotEmpty) ...[
                      _SectionHeader(
                          label: 'mentions',
                          count: mentions.fold<int>(
                              0, (sum, r) => sum + r.highlightCount)),
                      for (final room in mentions)
                        _MentionTile(room: room),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// Rebuilds inbox when the client syncs. Watched by [InboxScreen].
final _inboxTickProvider = StreamProvider<int>((ref) async* {
  final client = ref.watch(matrixServiceProvider).client;
  if (client == null) {
    yield 0;
    return;
  }
  var tick = 0;
  yield tick;
  await for (final _ in client.onSync.stream) {
    yield ++tick;
  }
});

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, size: 22, color: colors.accent),
          const SizedBox(width: 10),
          Text(
            'inbox',
            style: GoogleFonts.spectral(
              fontSize: 20,
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
              color: colors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: colors.textTertiary),
          const SizedBox(height: 12),
          Text(
            'all caught up',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '// no invites or mentions',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: colors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(
            '// $label',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: colors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.bgElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteTile extends ConsumerWidget {
  const _InviteTile({required this.room});
  final Room room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    final name = room.getLocalizedDisplayname();
    final subtitle = room.isSpace
        ? 'space invite'
        : (room.isDirectChat ? 'direct message' : 'room invite');

    return InkWell(
      onTap: () {
        // Open the room so user can accept/decline via existing room UI.
        ref.read(selectedRoomProvider.notifier).state = room.id;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            GloamAvatar(
              displayName: name,
              mxcUrl: room.avatar,
              size: 40,
              borderRadius: room.isSpace ? 8 : 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: colors.accent,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _MentionTile extends ConsumerWidget {
  const _MentionTile({required this.room});
  final Room room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    final name = room.getLocalizedDisplayname();
    final count = room.highlightCount;
    final lastBody = room.lastEvent?.body ?? '';
    final lastSender =
        room.lastEvent?.senderFromMemoryOrFallback.calcDisplayname() ?? '';

    return InkWell(
      onTap: () {
        ref.read(selectedRoomProvider.notifier).state = room.id;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            GloamAvatar(
              displayName: name,
              mxcUrl: room.avatar,
              size: 40,
              borderRadius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.danger,
                          borderRadius:
                              BorderRadius.circular(GloamSpacing.radiusSm),
                        ),
                        child: Text(
                          '@$count',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lastSender.isNotEmpty ? '$lastSender: $lastBody' : lastBody,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: colors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
