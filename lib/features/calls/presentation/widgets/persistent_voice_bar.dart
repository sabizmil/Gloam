import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../services/voice_service.dart';
import '../../domain/voice_connection_quality.dart';
import '../../domain/voice_participant.dart';

/// The persistent voice bar shown at the bottom of the app while
/// connected to a voice channel.
///
/// Visible on every screen — room list, chat views, settings.
/// Shows channel name, timer, quality indicator, and mute/deafen/disconnect.
class PersistentVoiceBar extends ConsumerStatefulWidget {
  const PersistentVoiceBar({
    super.key,
    required this.state,
    this.compact = false,
  });

  final VoiceStateConnected state;

  /// Compact mode for mobile (taller, larger touch targets).
  final bool compact;

  @override
  ConsumerState<PersistentVoiceBar> createState() =>
      _PersistentVoiceBarState();
}

class _PersistentVoiceBarState extends ConsumerState<PersistentVoiceBar> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateElapsed();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateElapsed());
  }

  void _updateElapsed() {
    if (!mounted) return;
    setState(() {
      _elapsed = DateTime.now().difference(widget.state.connectedAt);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voiceService = ref.read(voiceServiceProvider.notifier);
    final height = widget.compact ? 64.0 : 52.0;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: context.gloam.bgElevated,
        border: Border(
          top: BorderSide(color: context.gloam.accentDim, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Left: channel info
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // TODO: navigate to voice channel view
              },
              child: Row(
                children: [
                  Icon(Icons.volume_up_rounded,
                      size: 18, color: context.gloam.accent),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.state.channelName} · ${widget.state.protocolName}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.gloam.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _participantSummary(widget.state.participants),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
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
            ),
          ),

          // Center: timer + quality dot
          Text(
            _formatElapsed(_elapsed),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: context.gloam.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          _ConnectionQualityDot(
            quality: _worstQuality(widget.state.participants),
          ),

          const SizedBox(width: 16),

          // Right: controls
          _BarIconButton(
            icon: Icons.mic_rounded,
            tooltip: 'Mute',
            onTap: () => voiceService.toggleMute(),
          ),
          const SizedBox(width: 4),
          _BarIconButton(
            icon: Icons.headphones_rounded,
            tooltip: 'Deafen',
            onTap: () => voiceService.toggleDeafen(),
          ),
          const SizedBox(width: 4),
          _BarIconButton(
            icon: Icons.call_end_rounded,
            color: context.gloam.danger,
            backgroundColor: const Color(0xFF3A1A1A),
            tooltip: 'Disconnect',
            onTap: () => voiceService.disconnect(),
          ),
        ],
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _participantSummary(List<VoiceParticipant> participants) {
    if (participants.isEmpty) return 'no one connected';
    final names = participants
        .where((p) => !p.isSelf)
        .take(3)
        .map((p) => p.displayName)
        .toList();
    final others = participants.length - 1 - names.length;
    final joined = names.join(', ');
    if (others > 0) return '$joined +$others others';
    return joined.isEmpty ? 'you' : joined;
  }

  VoiceConnectionQuality _worstQuality(List<VoiceParticipant> participants) {
    if (participants.isEmpty) return VoiceConnectionQuality.unknown;
    var worst = VoiceConnectionQuality.good;
    for (final p in participants) {
      if (p.connectionQuality.index > worst.index) {
        worst = p.connectionQuality;
      }
    }
    return worst;
  }
}

class _ConnectionQualityDot extends StatelessWidget {
  const _ConnectionQualityDot({required this.quality});

  final VoiceConnectionQuality quality;

  @override
  Widget build(BuildContext context) {
    final color = switch (quality) {
      VoiceConnectionQuality.good => context.gloam.online,
      VoiceConnectionQuality.fair => context.gloam.warning,
      VoiceConnectionQuality.poor => context.gloam.danger,
      VoiceConnectionQuality.unknown => context.gloam.textTertiary,
    };

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.backgroundColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor ?? context.gloam.bgSurface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: color ?? context.gloam.textPrimary),
          ),
        ),
      ),
    );
  }
}
