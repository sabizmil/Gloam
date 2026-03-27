import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/call_provider.dart';

/// Outgoing call screen — shown while ringing the recipient.
///
/// Centered card on desktop, full-screen on mobile.
class OutgoingCallScreen extends ConsumerWidget {
  const OutgoingCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callServiceProvider);
    final outgoing =
        callState is CallStateRingingOutgoing ? callState : null;

    if (outgoing == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D1A10), Color(0xFF080F0A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar
                  GloamAvatar(
                    displayName: outgoing.peer.displayName,
                    mxcUrl: outgoing.peer.avatarUrl,
                    size: 96,
                  ),
                  const SizedBox(height: 24),

                  // Name
                  Text(
                    outgoing.peer.displayName,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: GloamColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Status
                  Text(
                    'calling...',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      color: GloamColors.accent,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pulse dots
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dot(0.3),
                      const SizedBox(width: 6),
                      _dot(0.6),
                      const SizedBox(width: 6),
                      _dot(1.0),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // Controls
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CircleButton(
                        icon: Icons.mic_rounded,
                        onTap: () {},
                      ),
                      const SizedBox(width: 16),
                      _CircleButton(
                        icon: Icons.videocam_rounded,
                        color: GloamColors.textTertiary,
                        onTap: () {},
                      ),
                      const SizedBox(width: 16),
                      _CircleButton(
                        icon: Icons.call_end_rounded,
                        backgroundColor: GloamColors.danger,
                        color: Colors.white,
                        size: 64,
                        iconSize: 24,
                        onTap: () {
                          ref.read(callServiceProvider.notifier).endCall();
                          Navigator.of(context).maybePop();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Call type label
                  Text(
                    outgoing.isVideo ? 'video call' : 'voice call',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: GloamColors.textTertiary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dot(double opacity) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: GloamColors.accent.withAlpha((opacity * 255).toInt()),
        ),
      );
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.color = GloamColors.textPrimary,
    this.backgroundColor = GloamColors.bgSurface,
    this.size = 52,
    this.iconSize = 22,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color backgroundColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
  }
}
