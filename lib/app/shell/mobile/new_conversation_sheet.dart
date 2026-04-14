import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/gloam_theme_ext.dart';
import '../../../features/explore/presentation/explore_modal.dart';
import '../../../features/rooms/presentation/widgets/create_room_dialog.dart';

/// Bottom sheet triggered by the FAB in the `chats` tab.
/// Space creation is intentionally desktop-only for now — shown as disabled
/// with a hint.
void showNewConversationSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.gloam.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _NewConversationSheet(),
  );
}

class _NewConversationSheet extends StatelessWidget {
  const _NewConversationSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _SheetOption(
              icon: Icons.person_add_outlined,
              label: 'New DM',
              sublabel: 'Start a direct message',
              onTap: () {
                Navigator.pop(context);
                showExploreModal(context);
              },
            ),
            _SheetOption(
              icon: Icons.chat_outlined,
              label: 'New room',
              sublabel: 'Create a channel or group',
              onTap: () {
                Navigator.pop(context);
                showCreateRoomDialog(context);
              },
            ),
            _SheetOption(
              icon: Icons.grid_view_outlined,
              label: 'New space',
              sublabel: 'Create on desktop for now',
              disabled: true,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.bgElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 20,
                color: disabled ? colors.textTertiary : colors.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color:
                          disabled ? colors.textTertiary : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
