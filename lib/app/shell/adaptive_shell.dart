import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing.dart';
import '../../features/chat/presentation/providers/timeline_provider.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import 'space_rail.dart';
import 'room_list_panel.dart';
import 'mobile_tabs.dart';
import 'right_panel.dart';

/// Top-level adaptive layout — switches between desktop (3-col),
/// tablet (2-col), and mobile (tab bar) based on viewport width.
class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= GloamSpacing.breakpointTablet) {
          return const _DesktopShell();
        } else if (constraints.maxWidth >= GloamSpacing.breakpointPhone) {
          return const _TabletShell();
        } else {
          return const MobileTabs();
        }
      },
    );
  }
}

/// Desktop: space rail + room list + chat area + right panel.
class _DesktopShell extends ConsumerWidget {
  const _DesktopShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRoom = ref.watch(selectedRoomProvider);
    final panelState = ref.watch(rightPanelProvider);
    final showPanel = panelState.view != RightPanelView.none;

    return Row(
      children: [
        const SpaceRail(),
        const RoomListPanel(),
        Expanded(
          child: selectedRoom != null
              ? ChatScreen(roomId: selectedRoom)
              : const _EmptyState(),
        ),
        if (showPanel && selectedRoom != null)
          RightPanel(roomId: selectedRoom),
      ],
    );
  }
}

/// Tablet: room list + chat area (space rail in drawer).
class _TabletShell extends ConsumerWidget {
  const _TabletShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRoom = ref.watch(selectedRoomProvider);

    return Row(
      children: [
        const SizedBox(width: 280, child: RoomListPanel()),
        Expanded(
          child: selectedRoom != null
              ? ChatScreen(roomId: selectedRoom)
              : const _EmptyState(),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GloamColors.bg,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'gloam',
              style: TextStyle(
                fontFamily: 'Spectral',
                fontSize: 22,
                fontWeight: FontWeight.w300,
                fontStyle: FontStyle.italic,
                color: GloamColors.accentDim,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '// select a conversation',
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                color: GloamColors.textTertiary,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
