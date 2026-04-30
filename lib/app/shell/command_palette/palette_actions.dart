import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../theme/theme_preferences.dart';
import '../../theme/theme_variants.dart';
import '../../../features/chat/presentation/providers/timeline_provider.dart';
import '../../../features/explore/presentation/explore_modal.dart';
import '../../../features/rooms/presentation/widgets/create_room_dialog.dart';
import '../../../features/settings/presentation/settings_modal.dart';
import '../../../services/matrix_service.dart';
import '../shortcut_help_overlay.dart';

/// A single command-palette action — a non-navigation verb the user can fire.
class PaletteAction {
  const PaletteAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.run,
    this.shortcut,
    this.requiresActiveRoom = false,
    this.section = PaletteActionSection.action,
    this.settingsTarget,
  });

  final String id;
  final String label;
  final IconData icon;
  final String? shortcut;

  /// If true, the action is hidden when no room is selected.
  final bool requiresActiveRoom;

  /// Visual grouping in the palette.
  final PaletteActionSection section;

  /// For settings deep-links — the section to open. Null for non-settings actions.
  final SettingsSection? settingsTarget;

  final FutureOr<void> Function(BuildContext context, WidgetRef ref) run;
}

enum PaletteActionSection { action, theme, settings }

/// Static action registry. Order is preserved within each section.
final List<PaletteAction> paletteActions = [
  // ── App actions ──
  PaletteAction(
    id: 'new-room',
    label: 'New room',
    icon: Icons.add_circle_outline,
    shortcut: '⌘N',
    run: (context, ref) async {
      final roomId = await showCreateRoomDialog(context);
      if (roomId != null) {
        ref.read(selectedRoomProvider.notifier).state = roomId;
      }
    },
  ),
  PaletteAction(
    id: 'mark-all-read',
    label: 'Mark all as read',
    icon: Icons.done_all,
    run: (context, ref) async {
      final client = ref.read(matrixServiceProvider).client;
      if (client == null) return;
      for (final room in client.rooms) {
        if (room.membership != Membership.join) continue;
        final last = room.lastEvent;
        if (last == null) continue;
        // ignore: unawaited_futures
        room.setReadMarker(last.eventId, mRead: last.eventId);
      }
    },
  ),
  PaletteAction(
    id: 'mark-room-read',
    label: 'Mark current room as read',
    icon: Icons.check,
    shortcut: '⇧⌘R',
    requiresActiveRoom: true,
    run: (context, ref) async {
      final roomId = ref.read(selectedRoomProvider);
      if (roomId == null) return;
      final client = ref.read(matrixServiceProvider).client;
      final room = client?.getRoomById(roomId);
      final last = room?.lastEvent;
      if (room != null && last != null) {
        await room.setReadMarker(last.eventId, mRead: last.eventId);
      }
    },
  ),
  PaletteAction(
    id: 'leave-room',
    label: 'Leave current room',
    icon: Icons.logout,
    requiresActiveRoom: true,
    run: (context, ref) async {
      final roomId = ref.read(selectedRoomProvider);
      if (roomId == null) return;
      final client = ref.read(matrixServiceProvider).client;
      final room = client?.getRoomById(roomId);
      if (room == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Leave ${room.getLocalizedDisplayname()}?'),
          content: const Text('You will need to be re-invited to rejoin.'),
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
        await room.leave();
        ref.read(selectedRoomProvider.notifier).state = null;
      }
    },
  ),
  PaletteAction(
    id: 'toggle-theme',
    label: 'Cycle theme variant',
    icon: Icons.brightness_6_outlined,
    run: (context, ref) async {
      final next =
          ref.read(themePreferencesProvider.notifier).cycleVariant();
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('theme: ${_variantLabel(next)}'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
    },
  ),
  PaletteAction(
    id: 'explore-rooms',
    label: 'Explore rooms & spaces',
    icon: Icons.explore_outlined,
    shortcut: '⇧⌘J',
    run: (context, ref) async => showExploreModal(context),
  ),
  PaletteAction(
    id: 'open-settings',
    label: 'Open Settings',
    icon: Icons.settings_outlined,
    shortcut: '⌘,',
    run: (context, ref) async => showSettingsModal(context),
  ),
  PaletteAction(
    id: 'show-shortcuts',
    label: 'Keyboard shortcuts',
    icon: Icons.keyboard_outlined,
    shortcut: '⌘/',
    run: (context, ref) async => showShortcutHelp(context),
  ),

  // ── Theme variants (selectable by name, e.g. type "dusk") ──
  for (final variant in ThemeVariant.values)
    PaletteAction(
      id: 'theme-${variant.name}',
      label: 'Theme: ${_variantLabel(variant)}',
      icon: Icons.palette_outlined,
      section: PaletteActionSection.theme,
      run: (context, ref) async {
        ref.read(themePreferencesProvider.notifier).setVariant(variant);
      },
    ),

  // ── Settings deep-links ──
  for (final section in SettingsSection.values)
    PaletteAction(
      id: 'settings-${section.name}',
      label: 'Settings · ${section.label}',
      icon: section.icon,
      section: PaletteActionSection.settings,
      settingsTarget: section,
      run: (context, ref) async =>
          showSettingsModal(context, initialSection: section),
    ),
];

String _variantLabel(ThemeVariant v) {
  // Convert e.g. ThemeVariant.gloamDark → "gloam dark"
  final raw = v.name;
  return raw
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}')
      .trim();
}
