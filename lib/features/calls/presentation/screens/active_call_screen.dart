import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../services/voice_service.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/call_provider.dart';

/// Active call screen — shown during a connected DM call.
///
/// Voice mode: large avatar with speaking ring, name, quality, controls.
/// Video mode: remote video fill, self-view PiP, floating controls.
class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => _updateElapsed());
  }

  void _updateElapsed() {
    final callState = ref.read(callServiceProvider);
    if (callState is CallStateActive) {
      setState(() {
        _elapsed = DateTime.now().difference(callState.startedAt);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callServiceProvider);
    final active = callState is CallStateActive ? callState : null;

    // Also handle connecting state
    final connecting = callState is CallStateConnecting ? callState : null;

    if (active == null && connecting == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    if (connecting != null) {
      return _ConnectingView();
    }

    return Scaffold(
      backgroundColor: context.gloam.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D1A10), Color(0xFF080F0A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar: connection status + timer
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.gloam.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'connected',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: context.gloam.accent,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatElapsed(_elapsed),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        color: context.gloam.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Avatar with speaking indicator
              _CallAvatar(peer: active!.peer),

              const SizedBox(height: 20),

              // Name
              Text(
                active.peer.displayName,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: context.gloam.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              // Quality indicator
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.signal_cellular_alt_rounded,
                      size: 14, color: context.gloam.accent),
                  const SizedBox(width: 6),
                  Text(
                    '12ms',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: context.gloam.textSecondary,
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 2),

              // Control bar
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ControlButton(
                      icon: Icons.mic_rounded,
                      label: 'mute',
                      onTap: () =>
                          ref.read(voiceServiceProvider.notifier).toggleMute(),
                    ),
                    const SizedBox(width: 16),
                    _ControlButton(
                      icon: Icons.videocam_off_rounded,
                      label: 'camera',
                      color: context.gloam.textTertiary,
                      onTap: () {
                        // Toggle video
                      },
                    ),
                    const SizedBox(width: 16),
                    _ControlButton(
                      icon: Icons.volume_up_rounded,
                      label: 'speaker',
                      isActive: true,
                      onTap: () {
                        // Toggle speaker
                      },
                    ),
                    const SizedBox(width: 16),
                    _ControlButton(
                      icon: Icons.call_end_rounded,
                      label: 'end',
                      backgroundColor: context.gloam.danger,
                      color: Colors.white,
                      size: 72,
                      onTap: () {
                        ref.read(callServiceProvider.notifier).endCall();
                        Navigator.of(context).maybePop();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _CallAvatar extends ConsumerWidget {
  const _CallAvatar({required this.peer});

  final CallPeerInfo peer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceState = ref.watch(voiceServiceProvider);
    final isSpeaking = voiceState is VoiceStateConnected &&
        voiceState.participants.any(
            (p) => !p.isSelf && p.isSpeaking);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSpeaking ? context.gloam.accent : Colors.transparent,
          width: isSpeaking ? 3.0 : 0.0,
        ),
      ),
      child: GloamAvatar(
        displayName: peer.displayName,
        mxcUrl: peer.avatarUrl,
        size: 100,
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.backgroundColor,
    this.isActive = false,
    this.size = 56,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Color? backgroundColor;
  final bool isActive;
  final double size;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.gloam.textPrimary;
    final effectiveBg = backgroundColor ?? context.gloam.bgSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isActive ? context.gloam.accentDim : effectiveBg,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon,
                  size: 24,
                  color: isActive ? context.gloam.accentBright : effectiveColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gloam.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: context.gloam.accent,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'connecting...',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: context.gloam.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
