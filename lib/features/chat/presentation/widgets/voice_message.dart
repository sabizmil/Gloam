import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../providers/timeline_provider.dart';

/// Renders a voice message with waveform visualization and playback controls.
class VoiceMessage extends StatefulWidget {
  const VoiceMessage({super.key, required this.message});
  final TimelineMessage message;

  @override
  State<VoiceMessage> createState() => _VoiceMessageState();
}

class _VoiceMessageState extends State<VoiceMessage> {
  bool _playing = false;
  double _progress = 0.0;

  String _formatDuration(int? bytes) {
    // Estimate duration from file size (rough: opus ~16kbps)
    if (bytes == null) return '0:00';
    final seconds = (bytes / 2000).clamp(1, 600).toInt();
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/pause button
          GestureDetector(
            onTap: () => setState(() => _playing = !_playing),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.accentDim,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause : Icons.play_arrow,
                size: 20,
                color: colors.accentBright,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Waveform
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 28,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      progress: _progress,
                      seed: widget.message.eventId.hashCode,
                      activeColor: colors.accent,
                      inactiveColor: colors.textTertiary,
                    ),
                    size: const Size(double.infinity, 28),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDuration(widget.message.mediaSizeBytes),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws a waveform visualization. Uses a seeded random for consistent
/// bar heights per message.
class _WaveformPainter extends CustomPainter {
  final double progress;
  final int seed;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.progress,
    required this.seed,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final barWidth = 2.5;
    final gap = 1.5;
    final barCount = (size.width / (barWidth + gap)).floor();
    final progressBars = (barCount * progress).floor();

    for (var i = 0; i < barCount; i++) {
      final height = 4.0 + rng.nextDouble() * (size.height - 8);
      final x = i * (barWidth + gap);
      final y = (size.height - height) / 2;

      final paint = Paint()
        ..color = i < progressBars
            ? activeColor
            : inactiveColor.withValues(alpha: 0.3)
        ..strokeCap = StrokeCap.round;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, height),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor;
}
