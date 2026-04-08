import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../theme/gloam_theme_ext.dart';
import '../theme/spacing.dart';
import '../../features/explore/presentation/explore_modal.dart';
import '../../features/rooms/presentation/providers/room_list_provider.dart';
import '../../features/rooms/presentation/providers/space_hierarchy_provider.dart';
import '../../features/rooms/presentation/widgets/invite_dialog.dart';
import '../../features/settings/presentation/settings_modal.dart';
import '../../services/matrix_service.dart';
import '../../widgets/gloam_avatar.dart';
import 'space_management_modal.dart';

/// Currently selected space ID — null means "all / DMs".
final selectedSpaceProvider = StateProvider<String?>((ref) => null);

/// Provides the list of joined spaces.
final spacesProvider = StreamProvider<List<Room>>((ref) async* {
  final client = ref.watch(matrixServiceProvider).client;
  if (client == null) {
    yield [];
    return;
  }

  List<Room> getSpaces() => client.rooms
      .where((r) => r.isSpace && r.membership == Membership.join)
      .toList();

  yield getSpaces();

  await for (final _ in client.onSync.stream) {
    yield getSpaces();
  }
});

/// Provides the list of pending space invites.
final spaceInvitesProvider = StreamProvider<List<Room>>((ref) async* {
  final client = ref.watch(matrixServiceProvider).client;
  if (client == null) {
    yield [];
    return;
  }

  List<Room> getInvites() => client.rooms
      .where((r) => r.isSpace && r.membership == Membership.invite)
      .toList();

  yield getInvites();

  await for (final _ in client.onSync.stream) {
    yield getInvites();
  }
});

/// Vertical space rail — 64px wide, shows DMs button + space icons.
class SpaceRail extends ConsumerWidget {
  const SpaceRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacesAsync = ref.watch(spacesProvider);
    final invitesAsync = ref.watch(spaceInvitesProvider);
    final selectedSpace = ref.watch(selectedSpaceProvider);

    return Container(
      width: GloamSpacing.spaceRailWidth,
      decoration: BoxDecoration(
        color: context.gloam.bg,
        border: Border(
          right: BorderSide(color: context.gloam.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Gloam logo
          _SpaceIcon(
            child: Text(
              'G',
              style: GoogleFonts.spectral(
                fontSize: 20,
                fontWeight: FontWeight.w300,
                fontStyle: FontStyle.italic,
                color: context.gloam.accentBright,
              ),
            ),
            color: context.gloam.accentDim,
            isActive: false,
            tooltip: 'gloam',
            onTap: () {},
          ),
          const SizedBox(height: 4),

          // DMs / Home button (with invite badge)
          Consumer(builder: (context, ref, _) {
            final inviteCount = ref.watch(inviteCountProvider);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                _SpaceIcon(
                  child: Icon(Icons.chat_bubble_outline,
                      size: 20, color: context.gloam.textSecondary),
                  isActive: selectedSpace == null,
                  tooltip: 'Direct Messages',
                  onTap: () =>
                      ref.read(selectedSpaceProvider.notifier).state = null,
                ),
                if (inviteCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: context.gloam.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$inviteCount',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: context.gloam.bg,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 24,
              height: 1,
              color: context.gloam.border,
            ),
          ),

          // Space invites + joined spaces list
          Expanded(
            child: Builder(builder: (context) {
              final invites = invitesAsync.valueOrNull ?? [];
              final spaces = spacesAsync.valueOrNull ?? [];
              final totalCount = invites.length + spaces.length;

              if (totalCount == 0) return const SizedBox.shrink();

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: totalCount,
                itemBuilder: (context, index) {
                  // Invites first, then joined spaces
                  if (index < invites.length) {
                    final invite = invites[index];
                    final isActive = invite.id == selectedSpace;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _SpaceIcon(
                            child: GloamAvatar(
                              displayName: invite.getLocalizedDisplayname(),
                              size: 40,
                              borderRadius: isActive ? 12 : 20,
                            ),
                            isActive: isActive,
                            isDashed: true,
                            tooltip: '${invite.getLocalizedDisplayname()} (invite)',
                            onTap: () => ref
                                .read(selectedSpaceProvider.notifier)
                                .state = invite.id,
                          ),
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: context.gloam.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Joined spaces
                  final space = spaces[index - invites.length];
                  final isActive = space.id == selectedSpace;

                  // Count unread using hierarchy child IDs
                  final hierarchyAsync =
                      ref.watch(spaceHierarchyProvider(space.id));
                  final hierarchyIds = hierarchyAsync.whenOrNull(
                    data: (rooms) => rooms.map((r) => r.roomId).toSet(),
                  );
                  final unreadCount = _countSpaceUnread(
                      ref.read(matrixServiceProvider).client!,
                      space,
                      hierarchyIds);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: GestureDetector(
                      onSecondaryTapUp: (details) =>
                          _showSpaceContextMenu(
                            context, ref, space, details.globalPosition),
                      child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _SpaceIcon(
                          child: GloamAvatar(
                            displayName: space.getLocalizedDisplayname(),
                            size: 40,
                            borderRadius: isActive ? 12 : 20,
                          ),
                          isActive: isActive,
                          tooltip: space.getLocalizedDisplayname(),
                          onTap: () => ref
                              .read(selectedSpaceProvider.notifier)
                              .state = space.id,
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: 6,
                            top: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: context.gloam.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    ),
                  );
                },
              );
            }),
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 24,
              height: 1,
              color: context.gloam.border,
            ),
          ),

          // Add space button
          Builder(
            builder: (ctx) => _SpaceIcon(
              child: Icon(Icons.add, size: 16, color: context.gloam.textTertiary),
              isActive: false,
              isDashed: true,
              tooltip: 'Explore rooms & spaces',
              onTap: () => showExploreModal(ctx),
            ),
          ),
          const SizedBox(height: 8),

          // Settings button
          Builder(
            builder: (ctx) => _SpaceIcon(
              child: Icon(Icons.settings_outlined,
                  size: 18, color: context.gloam.textSecondary),
              isActive: false,
              tooltip: 'Settings',
              onTap: () => showSettingsModal(ctx),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  int _countSpaceUnread(
      Client client, Room space, Set<String>? hierarchyIds) {
    final childIds = hierarchyIds ??
        space.spaceChildren.map((c) => c.roomId).toSet();
    var total = 0;
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      if (childIds.contains(room.id)) {
        total += room.notificationCount;
      }
    }
    return total;
  }
}

class _SpaceIcon extends StatelessWidget {
  const _SpaceIcon({
    required this.child,
    this.color,
    required this.isActive,
    this.isDashed = false,
    required this.tooltip,
    required this.onTap,
  });

  final Widget child;
  final Color? color;
  final bool isActive;
  final bool isDashed;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Row(
        children: [
          // Active indicator pill
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 4,
            height: isActive ? 32 : 0,
            decoration: BoxDecoration(
              color: context.gloam.accent,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(4),
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color ?? (isActive ? context.gloam.bgElevated : context.gloam.bgSurface),
                borderRadius: BorderRadius.circular(isActive ? 12 : 20),
                border: isDashed
                    ? Border.all(color: context.gloam.border)
                    : (isActive
                        ? Border.all(color: context.gloam.accent, width: 2)
                        : null),
              ),
              child: Center(child: child),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

void _showSpaceContextMenu(
  BuildContext context,
  WidgetRef ref,
  Room space,
  Offset position,
) {
  final colors = context.gloam;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final relPos = RelativeRect.fromLTRB(
    position.dx, position.dy,
    overlay.size.width - position.dx,
    overlay.size.height - position.dy,
  );

  final canInvite = space.canInvite;
  final canManage = space.ownPowerLevel >= 50;

  showMenu<String>(
    context: context,
    position: relPos,
    color: colors.bgSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: colors.border),
    ),
    items: [
      if (canInvite)
        PopupMenuItem(
          value: 'invite',
          height: 36,
          child: Row(children: [
            Icon(Icons.person_add, size: 14, color: colors.accent),
            const SizedBox(width: 10),
            Text('Invite to space',
                style: TextStyle(fontSize: 13, color: colors.textPrimary)),
          ]),
        ),
      if (canManage)
        PopupMenuItem(
          value: 'settings',
          height: 36,
          child: Row(children: [
            Icon(Icons.settings, size: 14, color: colors.textPrimary),
            const SizedBox(width: 10),
            Text('Space info',
                style: TextStyle(fontSize: 13, color: colors.textPrimary)),
          ]),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'leave',
        height: 36,
        child: Row(children: [
          Icon(Icons.logout, size: 14, color: colors.danger),
          const SizedBox(width: 10),
          Text('Leave space',
              style: TextStyle(fontSize: 13, color: colors.danger)),
        ]),
      ),
    ],
  ).then((value) async {
    if (value == null) return;
    switch (value) {
      case 'invite':
        if (context.mounted) {
          showInviteDialog(context, space.id);
        }
      case 'settings':
        if (context.mounted) {
          showSpaceManagementModal(context, space.id);
        }
      case 'leave':
        if (context.mounted) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Leave ${space.getLocalizedDisplayname()}?'),
              content: const Text(
                  'You will lose access to all rooms in this space.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('leave'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await space.leave();
            ref.read(selectedSpaceProvider.notifier).state = null;
          }
        }
    }
  });
}
