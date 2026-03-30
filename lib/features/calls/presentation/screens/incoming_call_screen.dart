import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../providers/call_provider.dart';

/// Full-screen incoming call overlay.
///
/// Shows caller avatar, name, accept/decline buttons.
/// On mobile this is a full-screen route; on desktop a modal dialog.
class IncomingCallScreen extends ConsumerWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callServiceProvider);
    final incoming = callState is CallStateRingingIncoming ? callState : null;

    if (incoming == null) {
      // Call was answered/declined elsewhere, dismiss
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
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Avatar
              GloamAvatar(
                displayName: incoming.caller.displayName,
                mxcUrl: incoming.caller.avatarUrl,
                size: 120,
              ),
              const SizedBox(height: 24),

              // Name
              Text(
                incoming.caller.displayName,
                style: GoogleFonts.inter(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: context.gloam.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // Status
              Text(
                incoming.isVideo
                    ? 'incoming video call...'
                    : 'incoming voice call...',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  color: context.gloam.accent,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),

              // Pulse dots
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PulseDot(opacity: 0.3),
                  const SizedBox(width: 8),
                  _PulseDot(opacity: 0.6),
                  const SizedBox(width: 8),
                  _PulseDot(opacity: 1.0),
                ],
              ),

              const Spacer(flex: 3),

              // Accept / Decline buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallActionButton(
                    icon: Icons.call_end_rounded,
                    label: 'decline',
                    color: context.gloam.danger,
                    onTap: () {
                      ref.read(callServiceProvider.notifier).declineCall();
                      Navigator.of(context).maybePop();
                    },
                  ),
                  const SizedBox(width: 48),
                  _CallActionButton(
                    icon: Icons.call_rounded,
                    label: 'accept',
                    color: context.gloam.accent,
                    onTap: () {
                      ref.read(callServiceProvider.notifier).acceptCall();
                      // Stay on screen — it will transition to active call
                    },
                  ),
                ],
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, size: 28, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: context.gloam.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.opacity});
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.gloam.accent.withAlpha((opacity * 255).toInt()),
      ),
    );
  }
}
