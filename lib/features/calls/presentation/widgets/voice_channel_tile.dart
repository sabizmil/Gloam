import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../../domain/voice_channel.dart';

/// A voice channel entry in the room list sidebar.
///
/// Shows a speaker icon, channel name, and connected participant avatars
/// with speaking indicators for the active channel.
class VoiceChannelTile extends StatelessWidget {
  const VoiceChannelTile({
    super.key,
    required this.channel,
    required this.isConnected,
    required this.onTap,
  });

  final VoiceChannel channel;
  final bool isConnected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasParticipants = channel.connectedParticipants.isNotEmpty;

    return Material(
      color: isConnected ? context.gloam.bgElevated : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: context.gloam.bgElevated,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, hasParticipants ? 6 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Channel name row
              Row(
                children: [
                  Icon(
                    Icons.volume_up_rounded,
                    size: 16,
                    color: isConnected
                        ? context.gloam.accent
                        : context.gloam.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      channel.name,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight:
                            isConnected ? FontWeight.w500 : FontWeight.w400,
                        color: isConnected
                            ? context.gloam.accent
                            : context.gloam.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // Participant avatar row
              if (hasParticipants) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: _ParticipantList(
                    participants: channel.connectedParticipants,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantList extends StatelessWidget {
  const _ParticipantList({required this.participants});

  final List<VoiceChannelParticipantSummary> participants;

  @override
  Widget build(BuildContext context) {
    final visible = participants.take(5).toList();
    final overflow = participants.length - 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...visible.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  _MiniAvatar(participant: p),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      p.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: p.isSpeaking
                            ? context.gloam.accent
                            : context.gloam.textSecondary,
                        fontWeight: p.isSpeaking
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (p.isMuted)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.mic_off,
                          size: 10, color: context.gloam.textTertiary),
                    ),
                ],
              ),
            )),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              '+$overflow more',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: context.gloam.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.participant});

  final VoiceChannelParticipantSummary participant;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: participant.isSpeaking
              ? context.gloam.accent
              : Colors.transparent,
          width: participant.isSpeaking ? 2.0 : 0.0,
        ),
      ),
      child: GloamAvatar(
        displayName: participant.displayName,
        mxcUrl: participant.avatarUrl,
        size: 18,
      ),
    );
  }
}
