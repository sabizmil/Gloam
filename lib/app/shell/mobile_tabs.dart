import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/gloam_theme_ext.dart';
import '../../features/calls/presentation/widgets/persistent_voice_bar.dart';
import '../../services/voice_service.dart';
import 'mobile/chats_tab.dart';
import 'mobile/inbox_screen.dart';
import 'mobile/me_screen.dart';

/// Mobile tab bar — `chats` | `inbox` | `me`.
/// Spaces are accessed via the horizontal rail in [ChatsTab].
/// Calls live in the persistent voice bar when a call is active.
/// Settings live inside the Me tab.
class MobileTabs extends ConsumerStatefulWidget {
  const MobileTabs({super.key});

  @override
  ConsumerState<MobileTabs> createState() => _MobileTabsState();
}

class _MobileTabsState extends ConsumerState<MobileTabs> {
  int _currentTab = 0;

  static const _tabs = [
    (
      icon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
      label: 'chats',
    ),
    (
      icon: Icons.inbox_outlined,
      activeIcon: Icons.inbox,
      label: 'inbox',
    ),
    (
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'me',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gloam.bg,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _currentTab,
          children: const [
            ChatsTab(),
            InboxScreen(),
            MeScreen(),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Voice bar (when connected)
          Builder(builder: (context) {
            final voiceState = ref.watch(voiceServiceProvider);
            if (voiceState is VoiceStateConnected) {
              return PersistentVoiceBar(state: voiceState, compact: true);
            }
            return const SizedBox.shrink();
          }),
          // Tab bar
          Container(
            decoration: BoxDecoration(
              color: context.gloam.bg,
              border: Border(
                top: BorderSide(color: context.gloam.border),
              ),
            ),
            child: SafeArea(
              child: SizedBox(
                height: 56,
                child: Row(
                  children: List.generate(_tabs.length, (i) {
                    final tab = _tabs[i];
                    final isActive = i == _currentTab;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _currentTab = i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isActive ? tab.activeIcon : tab.icon,
                              size: 22,
                              color: isActive
                                  ? context.gloam.accent
                                  : context.gloam.textTertiary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tab.label,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: isActive
                                    ? context.gloam.accent
                                    : context.gloam.textTertiary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
