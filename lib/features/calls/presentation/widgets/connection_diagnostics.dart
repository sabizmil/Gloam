import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/voice_service.dart';
import '../../domain/voice_connection_quality.dart';
import '../../domain/voice_participant.dart';

/// Connection diagnostics overlay — shown when tapping the quality dot
/// in the voice bar or active call screen.
///
/// Displays ping, packet loss, codec, and per-participant quality.
class ConnectionDiagnostics extends ConsumerWidget {
  const ConnectionDiagnostics({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceState = ref.watch(voiceServiceProvider);
    final participants = voiceState is VoiceStateConnected
        ? voiceState.participants
        : <VoiceParticipant>[];

    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GloamColors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        border: Border.all(color: GloamColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection section
          Text(
            '// connection',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: GloamColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          _DiagRow(label: 'Status', value: 'Connected', color: GloamColors.accent),
          _DiagRow(label: 'Codec', value: 'Opus'),
          _DiagRow(label: 'Transport', value: 'LiveKit SFU'),
          // Note: actual ping/packet loss values would come from
          // LiveKit room stats — showing placeholder structure
          _DiagRow(label: 'Ping', value: '—'),
          _DiagRow(label: 'Packet Loss', value: '—'),

          if (participants.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '// participants',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: GloamColors.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            ...participants.map((p) => _DiagRow(
                  label: p.isSelf ? 'you' : p.displayName,
                  value: _qualityLabel(p.connectionQuality),
                  color: _qualityColor(p.connectionQuality),
                )),
          ],
        ],
      ),
    );
  }

  String _qualityLabel(VoiceConnectionQuality q) => switch (q) {
        VoiceConnectionQuality.good => 'Good',
        VoiceConnectionQuality.fair => 'Fair',
        VoiceConnectionQuality.poor => 'Poor',
        VoiceConnectionQuality.unknown => '—',
      };

  Color _qualityColor(VoiceConnectionQuality q) => switch (q) {
        VoiceConnectionQuality.good => GloamColors.accent,
        VoiceConnectionQuality.fair => GloamColors.warning,
        VoiceConnectionQuality.poor => GloamColors.danger,
        VoiceConnectionQuality.unknown => GloamColors.textTertiary,
      };
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.label,
    required this.value,
    this.color = GloamColors.textSecondary,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: GloamColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Show the diagnostics overlay as a popup anchored to the quality dot.
void showConnectionDiagnostics(BuildContext context, Offset anchor) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (ctx) => Stack(
      children: [
        // Dismiss on tap outside
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => entry.remove(),
            child: const SizedBox.expand(),
          ),
        ),
        // Diagnostics panel
        Positioned(
          left: anchor.dx - 140,
          bottom: MediaQuery.sizeOf(ctx).height - anchor.dy + 8,
          child: const ConnectionDiagnostics(),
        ),
      ],
    ),
  );

  overlay.insert(entry);
}
