import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../services/voice_service.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../../domain/voice_participant.dart';
import '../../domain/voice_permissions.dart';
import 'participant_context_menu.dart';

/// A single participant card in the voice channel participant grid.
///
/// Shows avatar (with animated speaking ring), display name, and
/// status indicator (speaking, muted, deafened, server muted).
class ParticipantTile extends ConsumerWidget {
  const ParticipantTile({
    super.key,
    required this.participant,
    this.width = 140,
    this.height = 140,
  });

  final VoiceParticipant participant;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onSecondaryTapDown: (details) => _showMenu(context, ref, details.globalPosition),
      onLongPressStart: (details) => _showMenu(context, ref, details.globalPosition),
      child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: GloamColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Avatar with speaking ring
          _SpeakingAvatar(participant: participant),

          const SizedBox(height: 8),

          // Name
          Text(
            participant.displayName,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: GloamColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 2),

          // Status indicator
          _StatusIndicator(participant: participant),
        ],
      ),
    ),
    );
  }

  void _showMenu(BuildContext context, WidgetRef ref, Offset position) {
    final voiceState = ref.read(voiceServiceProvider);
    final permissions = voiceState is VoiceStateConnected
        ? voiceState.permissions
        : const VoicePermissions();

    showParticipantContextMenu(
      context: context,
      ref: ref,
      participant: participant,
      permissions: permissions,
      position: position,
    );
  }
}

class _SpeakingAvatar extends StatelessWidget {
  const _SpeakingAvatar({required this.participant});

  final VoiceParticipant participant;

  @override
  Widget build(BuildContext context) {
    final isSpeaking = participant.isSpeaking;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSpeaking
              ? GloamColors.accent
                  .withAlpha((participant.audioLevel.clamp(0.3, 1.0) * 255).toInt())
              : Colors.transparent,
          width: isSpeaking ? 3.0 : 0.0,
        ),
      ),
      child: GloamAvatar(
        displayName: participant.displayName,
        mxcUrl: participant.avatarUrl,
        size: 48,
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.participant});

  final VoiceParticipant participant;

  @override
  Widget build(BuildContext context) {
    if (participant.isServerMuted) {
      return _buildStatus(
        icon: Icons.mic_off_rounded,
        label: 'server muted',
        color: GloamColors.danger,
      );
    }

    if (participant.isSpeaking) {
      return _buildStatus(label: 'speaking', color: GloamColors.accent);
    }

    if (participant.isDeafened) {
      return _buildStatus(
        icon: Icons.headset_off_rounded,
        label: 'deafened',
        color: GloamColors.warning,
      );
    }

    if (participant.isMuted) {
      return _buildStatus(
        icon: Icons.mic_off_rounded,
        label: 'muted',
        color: GloamColors.textTertiary,
      );
    }

    // No special status
    return const SizedBox(height: 12);
  }

  Widget _buildStatus({
    IconData? icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            color: color,
          ),
        ),
      ],
    );
  }
}
