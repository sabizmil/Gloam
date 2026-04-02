import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' show EventTypes;

import '../theme/gloam_theme_ext.dart';
import '../theme/spacing.dart';
import '../../features/calls/presentation/screens/voice_channel_screen.dart';
import '../../features/chat/presentation/providers/timeline_provider.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../services/matrix_service.dart';
import 'panel_layout.dart';
import 'resize_divider.dart';
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
/// Room list and right panel are resizable with snap behavior.
class _DesktopShell extends ConsumerWidget {
  const _DesktopShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRoom = ref.watch(selectedRoomProvider);
    final panelState = ref.watch(rightPanelProvider);
    final showPanel =
        panelState.view != RightPanelView.none && selectedRoom != null;
    final layout = ref.watch(panelLayoutProvider);
    final layoutNotifier = ref.read(panelLayoutProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final spaceRailWidth = GloamSpacing.spaceRailWidth;
        final available =
            constraints.maxWidth - spaceRailWidth - layout.roomListWidth;

        // Clamp room list
        final roomListWidth = layout.roomListWidth.clamp(
          PanelLayout.minRoomListWidth,
          PanelLayout.maxRoomListWidth,
        );

        return Row(
          children: [
            const SpaceRail(),

            // Room list with resize handle on right edge
            SizedBox(
              width: roomListWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(child: RoomListPanel()),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: -6,
                    child: ResizeDivider(
                      onDrag: (dx) => layoutNotifier.setRoomListWidth(
                        layout.roomListWidth + dx,
                      ),
                      onDragEnd: () => layoutNotifier.save(),
                    ),
                  ),
                ],
              ),
            ),

            // Chat + right panel area
            Expanded(
              child: showPanel
                  ? _buildSplitArea(
                      context, ref, selectedRoom!, available, layout,
                      layoutNotifier)
                  : (selectedRoom != null
                      ? _buildContentArea(selectedRoom, ref)
                      : const _EmptyState()),
            ),
          ],
        );
      },
    );
  }
}

/// Builds the chat + right panel split area with snap behavior.
/// Shared between desktop and tablet layouts.
Widget _buildSplitArea(
  BuildContext context,
  WidgetRef ref,
  String roomId,
  double availableWidth,
  PanelLayout layout,
  PanelLayoutNotifier layoutNotifier,
) {
  // Full-width mode: panel covers the entire area
  if (layout.rightPanelFullWidth) {
    return Stack(
      children: [
        // Chat underneath (hidden but stays mounted)
        Positioned.fill(child: _buildContentArea(roomId, ref)),
        // Panel on top with resize handle on left edge
        Positioned.fill(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  color: context.gloam.bg,
                  child: RightPanel(roomId: roomId),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: -6,
                child: ResizeDivider(
                  onDrag: (dx) {
                    if (dx > 0) {
                      // Dragging right = exit full mode, set panel width
                      layoutNotifier.setRightPanelFullWidth(false);
                      layoutNotifier.setRightPanelWidth(
                        availableWidth - PanelLayout.minChatWidth,
                        availableWidth: availableWidth,
                      );
                    }
                  },
                  onDragEnd: () => layoutNotifier.snapRightPanel(
                    availableWidth: availableWidth,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Split mode: chat and panel side by side
  final maxRight = availableWidth - PanelLayout.minChatWidth;
  final rightWidth = layout.rightPanelWidth.clamp(
    PanelLayout.snapCloseThreshold,
    maxRight.clamp(PanelLayout.snapCloseThreshold, availableWidth),
  );

  return Row(
    children: [
      // Chat area
      Expanded(child: _buildContentArea(roomId, ref)),

      // Right panel with resize handle
      SizedBox(
        width: rightWidth,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: RightPanel(roomId: roomId)),
            Positioned(
              top: 0,
              bottom: 0,
              left: -6,
              child: ResizeDivider(
                onDrag: (dx) => layoutNotifier.setRightPanelWidth(
                  layout.rightPanelWidth - dx,
                  availableWidth: availableWidth,
                ),
                onDragEnd: () {
                  // Snap logic
                  final chatWidth = availableWidth - layout.rightPanelWidth;
                  if (layout.rightPanelWidth < PanelLayout.snapCloseThreshold) {
                    // Snap closed
                    ref.read(rightPanelProvider.notifier).state =
                        RightPanelState.closed;
                    layoutNotifier.resetRightPanelWidth();
                  } else if (chatWidth < PanelLayout.snapFullThreshold) {
                    // Snap to full
                    layoutNotifier.setRightPanelFullWidth(true);
                  } else {
                    layoutNotifier.save();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    ],
  );
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

/// Tablet: space rail + room list + chat area with snappable right panel.
/// If the available width is too narrow for side-by-side, the right panel
/// is a full-width overlay that can be dragged to dismiss.
class _TabletShell extends ConsumerWidget {
  const _TabletShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRoom = ref.watch(selectedRoomProvider);
    final panelState = ref.watch(rightPanelProvider);
    final showPanel =
        panelState.view != RightPanelView.none && selectedRoom != null;
    final layout = ref.watch(panelLayoutProvider);
    final layoutNotifier = ref.read(panelLayoutProvider.notifier);

    final roomListWidth = layout.roomListWidth.clamp(
      PanelLayout.minRoomListWidth,
      PanelLayout.maxRoomListWidth,
    );

    return Row(
      children: [
        const SpaceRail(),
        SizedBox(
          width: roomListWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(child: RoomListPanel()),
              Positioned(
                top: 0,
                bottom: 0,
                right: -6,
                child: ResizeDivider(
                  onDrag: (dx) => layoutNotifier.setRoomListWidth(
                    layout.roomListWidth + dx,
                  ),
                  onDragEnd: () => layoutNotifier.save(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth;
              final canSplit = available >=
                  PanelLayout.minChatWidth + PanelLayout.snapCloseThreshold;

              if (!showPanel || selectedRoom == null) {
                return selectedRoom != null
                    ? _buildContentArea(selectedRoom, ref)
                    : const _EmptyState();
              }

              // If there's enough room, use the full split area with snap
              if (canSplit) {
                final layout = ref.watch(panelLayoutProvider);
                final layoutNotifier =
                    ref.read(panelLayoutProvider.notifier);
                return _buildSplitArea(
                  context, ref, selectedRoom, available,
                  layout, layoutNotifier,
                );
              }

              // Not enough room — full-width overlay with drag-to-dismiss
              return Stack(
                children: [
                  Positioned.fill(
                    child: _buildContentArea(selectedRoom, ref),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      onHorizontalDragEnd: (details) {
                        // Swipe right to dismiss
                        if (details.primaryVelocity != null &&
                            details.primaryVelocity! > 200) {
                          ref.read(rightPanelProvider.notifier).state =
                              RightPanelState.closed;
                        }
                      },
                      child: Container(
                        color: context.gloam.bg,
                        child: RightPanel(roomId: selectedRoom),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
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
