import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/gloam_theme_ext.dart';
import '../../../features/chat/presentation/providers/timeline_provider.dart';
import '../../../features/search/presentation/search_screen.dart';

/// Mobile full-screen wrapper for [SearchScreen]. Selecting a result
/// routes to the relevant room via [selectedRoomProvider] — the adaptive
/// shell (and mobile route) will show that room.
class MobileSearchScreen extends ConsumerWidget {
  const MobileSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.gloam.bg,
      body: SafeArea(
        child: SearchScreen(
          onClose: () => Navigator.of(context).pop(),
          onSelectResult: (roomId, _) {
            ref.read(selectedRoomProvider.notifier).state = roomId;
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}

void showMobileSearch(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const MobileSearchScreen(),
      fullscreenDialog: true,
    ),
  );
}
