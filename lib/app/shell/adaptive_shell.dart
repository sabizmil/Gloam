import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' show EventTypes;

import '../theme/gloam_theme_ext.dart';
import '../theme/spacing.dart';
import '../../features/calls/presentation/screens/voice_channel_screen.dart';
import '../../features/chat/presentation/providers/timeline_provider.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../services/matrix_service.dart';
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
              ? _buildContentArea(selectedRoom, ref)
              : const _EmptyState(),
        ),
        if (showPanel && selectedRoom != null)
          RightPanel(roomId: selectedRoom),
      ],
    );
  }
}

/// Returns either a VoiceChannelScreen or ChatScreen based on room type.
Widget _buildContentArea(String roomId, WidgetRef ref) {
  final client = ref.read(matrixServiceProvider).client;
  if (client != null) {
    final room = client.getRoomById(roomId);
    if (room != null) {
      final createEvent = room.getState(EventTypes.RoomCreate);
      final roomType = createEvent?.content['type'];
      if (roomType == 'im.gloam.voice_channel' ||
          roomType == 'org.matrix.msc3417.call' ||
          room.tags.containsKey('im.gloam.voice_channel')) {
        return VoiceChannelScreen(key: ValueKey('vc_$roomId'), roomId: roomId);
      }
    }
  }
  return ChatScreen(key: ValueKey(roomId), roomId: roomId);
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
              ? _buildContentArea(selectedRoom, ref)
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
      color: context.gloam.bg,
      child: Center(
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
                color: context.gloam.accentDim,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '// select a conversation',
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                color: context.gloam.textTertiary,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
