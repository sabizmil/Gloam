import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../services/voice_service.dart';
import '../../domain/voice_participant.dart';
import '../../domain/voice_permissions.dart';

/// Context menu for a voice participant — per-user volume, local mute,
/// and moderator actions (server mute, disconnect).
///
/// Shown on right-click (desktop) or long-press (mobile) on a participant tile.
void showParticipantContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required VoiceParticipant participant,
  required VoicePermissions permissions,
  required Offset position,
}) {
  if (participant.isSelf) return; // No context menu for self

  showMenu<void>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    ),
    color: GloamColors.bgElevated,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: GloamColors.border),
    ),
    items: [
      // Header: participant name
      PopupMenuItem<void>(
        enabled: false,
        height: 32,
        child: Text(
          participant.displayName,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: GloamColors.textPrimary,
          ),
        ),
      ),

      const PopupMenuDivider(height: 1),

      // Per-user volume slider
      PopupMenuItem<void>(
        enabled: false,
        height: 48,
        child: _VolumeSliderItem(
          participantId: participant.id,
          ref: ref,
        ),
      ),

      // Mute for me (local-only)
      PopupMenuItem<void>(
        height: 36,
        onTap: () {
          final adapter = ref.read(voiceServiceProvider.notifier).adapter;
          adapter?.localMedia.setUserVolume(participant.id, 0.0);
        },
        child: Row(
          children: [
            const Icon(Icons.volume_off_rounded,
                size: 16, color: GloamColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Mute for me',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: GloamColors.textPrimary,
              ),
            ),
          ],
        ),
      ),

      // Moderator actions
      if (permissions.canMuteOthers || permissions.canDisconnectOthers) ...[
        const PopupMenuDivider(height: 1),

        if (permissions.canMuteOthers)
          PopupMenuItem<void>(
            height: 36,
            onTap: () {
              // TODO: server mute via custom state event
            },
            child: Row(
              children: [
                Icon(
                  participant.isServerMuted
                      ? Icons.mic_rounded
                      : Icons.mic_off_rounded,
                  size: 16,
                  color: GloamColors.warning,
                ),
                const SizedBox(width: 8),
                Text(
                  participant.isServerMuted ? 'Unmute' : 'Server Mute',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: GloamColors.warning,
                  ),
                ),
              ],
            ),
          ),

        if (permissions.canDisconnectOthers)
          PopupMenuItem<void>(
            height: 36,
            onTap: () {
              // TODO: disconnect member via clearing m.rtc.member event
            },
            child: Row(
              children: [
                const Icon(Icons.logout_rounded,
                    size: 16, color: GloamColors.danger),
                const SizedBox(width: 8),
                Text(
                  'Disconnect',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: GloamColors.danger,
                  ),
                ),
              ],
            ),
          ),
      ],
    ],
  );
}

class _VolumeSliderItem extends StatefulWidget {
  const _VolumeSliderItem({
    required this.participantId,
    required this.ref,
  });

  final String participantId;
  final WidgetRef ref;

  @override
  State<_VolumeSliderItem> createState() => _VolumeSliderItemState();
}

class _VolumeSliderItemState extends State<_VolumeSliderItem> {
  double _volume = 1.0; // 0.0 to 2.0, default 1.0

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.volume_up_rounded,
            size: 14, color: GloamColors.textTertiary),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: GloamColors.accent,
              inactiveTrackColor: GloamColors.border,
              thumbColor: GloamColors.accent,
              overlayColor: GloamColors.accent.withAlpha(30),
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: _volume,
              min: 0.0,
              max: 2.0,
              onChanged: (v) {
                setState(() => _volume = v);
                final adapter =
                    widget.ref.read(voiceServiceProvider.notifier).adapter;
                adapter?.localMedia
                    .setUserVolume(widget.participantId, v);
              },
            ),
          ),
        ),
        Text(
          '${(_volume * 100).round()}%',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: GloamColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
