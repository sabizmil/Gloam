import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/presentation/providers/timeline_provider.dart';
import '../../features/chat/presentation/widgets/thread_panel.dart';
import 'room_info_panel.dart';

/// What's currently shown in the right panel.
enum RightPanelView { none, thread, roomInfo, members }

/// State for the right panel.
class RightPanelState {
  final RightPanelView view;
  final TimelineMessage? threadRoot;

  const RightPanelState({
    this.view = RightPanelView.none,
    this.threadRoot,
  });

  static const closed = RightPanelState();
}

final rightPanelProvider = StateProvider<RightPanelState>((ref) {
  return RightPanelState.closed;
});

/// Renders the appropriate right panel based on state.
class RightPanel extends ConsumerWidget {
  const RightPanel({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panelState = ref.watch(rightPanelProvider);

    return switch (panelState.view) {
      RightPanelView.none => const SizedBox.shrink(),
      RightPanelView.thread => panelState.threadRoot != null
          ? ThreadPanel(
              roomId: roomId,
              rootMessage: panelState.threadRoot!,
              onClose: () => ref.read(rightPanelProvider.notifier).state =
                  RightPanelState.closed,
            )
          : const SizedBox.shrink(),
      RightPanelView.roomInfo => RoomInfoPanel(
          roomId: roomId,
          onClose: () => ref.read(rightPanelProvider.notifier).state =
              RightPanelState.closed,
        ),
      RightPanelView.members => RoomInfoPanel(
          roomId: roomId,
          onClose: () => ref.read(rightPanelProvider.notifier).state =
              RightPanelState.closed,
        ),
    };
  }
}
