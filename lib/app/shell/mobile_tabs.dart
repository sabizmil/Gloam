import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/color_tokens.dart';
import 'room_list_panel.dart';

/// Mobile tab bar layout — Chats, Spaces, Calls, Settings.
class MobileTabs extends StatefulWidget {
  const MobileTabs({super.key});

  @override
  State<MobileTabs> createState() => _MobileTabsState();
}

class _MobileTabsState extends State<MobileTabs> {
  int _currentTab = 0;

  static const _tabs = [
    (icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'chats'),
    (icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view, label: 'spaces'),
    (icon: Icons.phone_outlined, activeIcon: Icons.phone, label: 'calls'),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GloamColors.bg,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _currentTab,
          children: [
            // Chats tab
            Column(
              children: [
                _MobileHeader(title: 'gloam'),
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: RoomListPanel(),
                  ),
                ),
              ],
            ),
            // Spaces tab (placeholder)
            _PlaceholderTab(label: 'spaces'),
            // Calls tab (placeholder)
            _PlaceholderTab(label: 'calls'),
            // Settings tab (placeholder)
            _PlaceholderTab(label: 'settings'),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: GloamColors.bg,
          border: Border(
            top: BorderSide(color: GloamColors.border),
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
                              ? GloamColors.accent
                              : GloamColors.textTertiary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.label,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: isActive
                                ? GloamColors.accent
                                : GloamColors.textTertiary,
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
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: GloamColors.accentDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                'G',
                style: GoogleFonts.spectral(
                  fontSize: 15,
                  fontWeight: FontWeight.w300,
                  fontStyle: FontStyle.italic,
                  color: GloamColors.accentBright,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.spectral(
              fontSize: 20,
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
              color: GloamColors.accent,
            ),
          ),
          const Spacer(),
          const Icon(Icons.search, size: 22, color: GloamColors.textSecondary),
          const SizedBox(width: 16),
          const Icon(Icons.edit_outlined,
              size: 22, color: GloamColors.textSecondary),
        ],
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '// $label — coming soon',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          color: GloamColors.textTertiary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
