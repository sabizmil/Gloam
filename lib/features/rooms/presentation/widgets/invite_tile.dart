import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/room_list_provider.dart';

/// A visually distinct invite card with Accept/Decline buttons.
///
/// Shows in the `// invites` section at the top of the room list.
/// Differentiates between DM invites (circular avatar, "wants to chat")
/// and room invites (square avatar, "invited you").
class InviteTile extends ConsumerStatefulWidget {
  const InviteTile({super.key, required this.invite});

  final RoomListItem invite;

  @override
  ConsumerState<InviteTile> createState() => _InviteTileState();
}

class _InviteTileState extends ConsumerState<InviteTile> {
  bool _accepting = false;
  bool _declining = false;

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      final client = ref.read(matrixServiceProvider).client;
      final room = client?.getRoomById(widget.invite.roomId);
      await room?.join();
    } catch (_) {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _declining = true);
    try {
      final client = ref.read(matrixServiceProvider).client;
      final room = client?.getRoomById(widget.invite.roomId);
      await room?.leave();
    } catch (_) {
      if (mounted) setState(() => _declining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invite;
    final isDm = inv.isDirect;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.gloam.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        border: Border.all(color: context.gloam.accentDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: avatar + info
          Row(
            children: [
              GloamAvatar(
                displayName: inv.displayName,
                mxcUrl: inv.avatarUrl,
                size: 36,
                borderRadius: isDm ? 18 : 8,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inv.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.gloam.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      isDm
                          ? 'wants to chat with you'
                          : inv.inviterName != null
                              ? '${inv.inviterName} invited you'
                              : inv.inviterId ?? 'invited you',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: context.gloam.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Decline
              GestureDetector(
                onTap: _declining ? null : _decline,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: context.gloam.bgSurface,
                    borderRadius:
                        BorderRadius.circular(GloamSpacing.radiusSm),
                    border: Border.all(color: context.gloam.border),
                  ),
                  child: Center(
                    child: _declining
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.gloam.textTertiary,
                            ),
                          )
                        : Text(
                            'Decline',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: context.gloam.textSecondary,
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Accept
              GestureDetector(
                onTap: _accepting ? null : _accept,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: context.gloam.accentDim,
                    borderRadius:
                        BorderRadius.circular(GloamSpacing.radiusSm),
                  ),
                  child: Center(
                    child: _accepting
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.gloam.accent,
                            ),
                          )
                        : Text(
                            'Accept',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: context.gloam.accent,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
