import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../theme/gloam_theme_ext.dart';
import '../../../widgets/gloam_avatar.dart';
import '../space_rail.dart'; // selectedSpaceProvider, spacesProvider

/// Horizontal rail of space avatars below the mobile header.
/// Leftmost pill is "All rooms" (selectedSpace = null). Tap a space to scope
/// the room list to that space's rooms + voice channels.
class SpaceSwitcherRail extends ConsumerWidget {
  const SpaceSwitcherRail({super.key});

  static const double _height = 72;
  static const double _itemSize = 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacesAsync = ref.watch(spacesProvider);
    final selected = ref.watch(selectedSpaceProvider);
    final colors = context.gloam;

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: spacesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (spaces) => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          children: [
            _AllRoomsPill(
              selected: selected == null,
              onTap: () =>
                  ref.read(selectedSpaceProvider.notifier).state = null,
            ),
            const SizedBox(width: 8),
            for (final space in spaces) ...[
              _SpaceItem(
                space: space,
                selected: selected == space.id,
                onTap: () => ref.read(selectedSpaceProvider.notifier).state =
                    space.id,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _AllRoomsPill extends StatelessWidget {
  const _AllRoomsPill({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: SpaceSwitcherRail._itemSize,
        height: SpaceSwitcherRail._itemSize,
        decoration: BoxDecoration(
          color: selected ? colors.accentDim : colors.bgElevated,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.accent : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            'all',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: selected ? colors.accentBright : colors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpaceItem extends StatelessWidget {
  const _SpaceItem({
    required this.space,
    required this.selected,
    required this.onTap,
  });
  final Room space;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: GloamAvatar(
          displayName: space.getLocalizedDisplayname(),
          mxcUrl: space.avatar,
          size: SpaceSwitcherRail._itemSize - 4,
          borderRadius: (SpaceSwitcherRail._itemSize - 4) / 2,
        ),
      ),
    );
  }
}
