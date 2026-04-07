import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../services/connection_status_provider.dart';

/// Slim status bar showing connection state. Hidden when online.
class ConnectionStatusBar extends ConsumerWidget {
  const ConnectionStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider);
    if (status == ConnectionStatus.online) return const SizedBox.shrink();

    final colors = context.gloam;
    final (color, text) = switch (status) {
      ConnectionStatus.connecting => (colors.accent, 'Connecting...'),
      ConnectionStatus.reconnecting => (colors.warning, 'Reconnecting...'),
      ConnectionStatus.disconnected => (
          colors.danger,
          'Disconnected — check your connection'
        ),
      ConnectionStatus.online => (colors.accent, ''), // unreachable
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: color.withAlpha(30),
        child: Row(
          children: [
            _PulsingDot(
              color: color,
              animate: status == ConnectionStatus.reconnecting ||
                  status == ConnectionStatus.connecting,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: GoogleFonts.inter(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.animate});
  final Color color;
  final bool animate;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.animate) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withAlpha(
            widget.animate ? (100 + (_controller.value * 155)).round() : 255,
          ),
        ),
      ),
    );
  }
}
