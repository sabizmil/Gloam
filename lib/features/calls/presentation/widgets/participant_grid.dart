import 'package:flutter/material.dart';

import '../../domain/voice_participant.dart';
import 'participant_tile.dart';

/// Responsive grid of participant tiles for the voice channel view.
///
/// Adapts tile count per row based on the number of participants
/// and available width, matching the gallery grid pattern from the PRD.
class ParticipantGrid extends StatelessWidget {
  const ParticipantGrid({
    super.key,
    required this.participants,
  });

  final List<VoiceParticipant> participants;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _crossAxisCount(
          participants.length,
          constraints.maxWidth,
        );
        final spacing = 12.0;
        final availableWidth =
            constraints.maxWidth - (spacing * (crossAxisCount - 1));
        final tileWidth = (availableWidth / crossAxisCount)
            .clamp(100.0, 180.0);
        final tileHeight = tileWidth; // Square tiles

        return Center(
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            alignment: WrapAlignment.center,
            children: participants
                .map((p) => ParticipantTile(
                      participant: p,
                      width: tileWidth,
                      height: tileHeight,
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  int _crossAxisCount(int count, double maxWidth) {
    // Responsive: on narrow screens, fewer columns
    if (maxWidth < 400) {
      return count <= 2 ? count : 2;
    }
    if (count <= 1) return 1;
    if (count <= 4) return 2;
    if (count <= 9) return 3;
    return 4; // 10+ paginated eventually
  }
}
