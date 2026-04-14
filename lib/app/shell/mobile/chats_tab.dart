import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/gloam_theme_ext.dart';
import '../room_list_panel.dart';
import 'mobile_search_screen.dart';
import 'new_conversation_sheet.dart';
import 'space_switcher_rail.dart';

/// Mobile `chats` tab — logo header with search, horizontal space switcher,
/// room list below, FAB bottom-right for new conversations.
class ChatsTab extends ConsumerWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    return Stack(
      children: [
        Column(
          children: [
            const _ChatsHeader(),
            const SpaceSwitcherRail(),
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: RoomListPanel(),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            backgroundColor: colors.accent,
            foregroundColor: colors.bg,
            onPressed: () => showNewConversationSheet(context),
            child: const Icon(Icons.add, size: 24),
          ),
        ),
      ],
    );
  }
}

class _ChatsHeader extends StatelessWidget {
  const _ChatsHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.accentDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                'G',
                style: GoogleFonts.spectral(
                  fontSize: 15,
                  fontWeight: FontWeight.w300,
                  fontStyle: FontStyle.italic,
                  color: colors.accentBright,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'gloam',
            style: GoogleFonts.spectral(
              fontSize: 20,
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
              color: colors.accent,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => showMobileSearch(context),
            icon: Icon(Icons.search, size: 22, color: colors.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}
