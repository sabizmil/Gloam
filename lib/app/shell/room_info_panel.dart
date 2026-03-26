import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing.dart';
import '../../services/matrix_service.dart';
import '../../widgets/gloam_avatar.dart';

/// Right panel showing room details, members, and settings links.
class RoomInfoPanel extends ConsumerWidget {
  const RoomInfoPanel({
    super.key,
    required this.roomId,
    required this.onClose,
  });

  final String roomId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixServiceProvider).client;
    final room = client?.getRoomById(roomId);
    if (room == null) return const SizedBox.shrink();

    final members = room.getParticipants();
    final name = room.getLocalizedDisplayname();
    final topic = room.topic;

    return Container(
      width: GloamSpacing.rightPanelWidth,
      decoration: const BoxDecoration(
        color: GloamColors.bgSurface,
        border: Border(
          left: BorderSide(color: GloamColors.border),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: GloamSpacing.headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: GloamColors.border),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'room info',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: GloamColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close,
                      size: 16, color: GloamColors.textTertiary),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Room avatar + name
                Center(
                  child: Column(
                    children: [
                      GloamAvatar(
                        displayName: name,
                        size: 64,
                        borderRadius: 16,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: GloamColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (topic.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          topic,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: GloamColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Details section
                Text(
                  '// details',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: GloamColors.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  label: 'encryption',
                  value: room.encrypted ? 'enabled' : 'disabled',
                  valueColor:
                      room.encrypted ? GloamColors.accent : GloamColors.textSecondary,
                  icon: room.encrypted ? Icons.lock : Icons.lock_open,
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'notifications',
                  value: 'mentions only',
                ),
                const SizedBox(height: 24),

                // Members section
                Text(
                  '// members \u2014 ${members.length}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: GloamColors.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                ...members.take(20).map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          GloamAvatar(
                            displayName: m.calcDisplayname(),
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.calcDisplayname(),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: GloamColors.textPrimary,
                                  ),
                                ),
                                if (m.powerLevel >= 100)
                                  Text(
                                    'admin',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: GloamColors.accent,
                                    ),
                                  )
                                else if (m.powerLevel >= 50)
                                  Text(
                                    'moderator',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: GloamColors.textTertiary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: GloamColors.textSecondary,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: valueColor ?? GloamColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: valueColor ?? GloamColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
