import 'package:flutter/material.dart';

import '../../../../app/theme/color_tokens.dart';
import '../providers/timeline_provider.dart';

/// Small delivery state icon next to the message timestamp.
///
/// Sending → pulsing dot
/// Sent → single check (muted)
/// Error → warning icon (danger)
class DeliveryIndicator extends StatelessWidget {
  const DeliveryIndicator({
    super.key,
    required this.state,
    this.size = 14,
  });

  final MessageSendState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      MessageSendState.sending => _SendingDot(size: size),
      MessageSendState.sent => Icon(
          Icons.check,
          size: size,
          color: GloamColors.textTertiary,
        ),
      MessageSendState.error => Icon(
          Icons.error_outline,
          size: size,
          color: GloamColors.danger,
        ),
    };
  }
}

class _SendingDot extends StatefulWidget {
  const _SendingDot({required this.size});
  final double size;

  @override
  State<_SendingDot> createState() => _SendingDotState();
}

class _SendingDotState extends State<_SendingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
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
      builder: (context, child) => Opacity(
        opacity: 0.3 + 0.7 * _controller.value,
        child: Icon(
          Icons.schedule,
          size: widget.size,
          color: GloamColors.textTertiary,
        ),
      ),
    );
  }
}
