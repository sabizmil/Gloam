import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing.dart';
import '../../features/settings/presentation/settings_modal.dart';
import '../../services/matrix_service.dart';
import '../../widgets/gloam_avatar.dart';

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

/// Vertical space rail — 64px wide, shows DMs button + space icons.
class SpaceRail extends ConsumerWidget {
  const SpaceRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacesAsync = ref.watch(spacesProvider);
    final selectedSpace = ref.watch(selectedSpaceProvider);

    return Container(
      width: GloamSpacing.spaceRailWidth,
      decoration: const BoxDecoration(
        color: GloamColors.bg,
        border: Border(
          right: BorderSide(color: GloamColors.borderSubtle),
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
                color: GloamColors.accentBright,
              ),
            ),
            color: GloamColors.accentDim,
            isActive: false,
            tooltip: 'gloam',
            onTap: () {},
          ),
          const SizedBox(height: 4),

          // DMs / Home button
          _SpaceIcon(
            child: const Icon(Icons.chat_bubble_outline,
                size: 20, color: GloamColors.textSecondary),
            isActive: selectedSpace == null,
            tooltip: 'Direct Messages',
            onTap: () =>
                ref.read(selectedSpaceProvider.notifier).state = null,
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 24,
              height: 1,
              color: GloamColors.border,
            ),
          ),

          // Spaces list
          Expanded(
            child: spacesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, s) => const SizedBox.shrink(),
              data: (spaces) => ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: spaces.length,
                itemBuilder: (context, index) {
                  final space = spaces[index];
                  final isActive = space.id == selectedSpace;

                  // Count unread across space children
                  final unreadCount = _countSpaceUnread(
                      ref.read(matrixServiceProvider).client!, space);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
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
                              decoration: const BoxDecoration(
                                color: GloamColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 24,
              height: 1,
              color: GloamColors.border,
            ),
          ),

          // Add space button
          _SpaceIcon(
            child: const Icon(Icons.add, size: 16, color: GloamColors.textTertiary),
            isActive: false,
            isDashed: true,
            tooltip: 'Join or create space',
            onTap: () {},
          ),
          const SizedBox(height: 8),

          // Settings button
          Builder(
            builder: (ctx) => _SpaceIcon(
              child: const Icon(Icons.settings_outlined,
                  size: 18, color: GloamColors.textSecondary),
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

  int _countSpaceUnread(Client client, Room space) {
    var total = 0;
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      // Check if room is a child of this space
      if (space.spaceChildren.any((c) => c.roomId == room.id)) {
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
              color: GloamColors.accent,
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
                color: color ?? (isActive ? GloamColors.bgElevated : GloamColors.bgSurface),
                borderRadius: BorderRadius.circular(isActive ? 12 : 20),
                border: isDashed
                    ? Border.all(color: GloamColors.border)
                    : (isActive
                        ? Border.all(color: GloamColors.accent, width: 2)
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
