import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../services/matrix_service.dart';

/// Displays "[User] is typing..." with animated dots.
class TypingIndicator extends ConsumerWidget {
  const TypingIndicator({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixServiceProvider).client;
    if (client == null) return const SizedBox.shrink();

    final room = client.getRoomById(roomId);
    if (room == null) return const SizedBox.shrink();

    return StreamBuilder<List<User>>(
      stream: client.onSync.stream.map((_) {
        return room.typingUsers
            .where((u) => u.id != client.userID)
            .toList();
      }),
      builder: (context, snapshot) {
        final typingUsers = snapshot.data ?? [];
        if (typingUsers.isEmpty) return const SizedBox.shrink();

        final text = _buildTypingText(typingUsers);

        return Padding(
          padding: const EdgeInsets.fromLTRB(68, 0, 20, 4),
          child: Row(
            children: [
              Text(
                text,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: GloamColors.textTertiary,
                ),
              ),
              const SizedBox(width: 2),
              const _AnimatedDots(),
            ],
          ),
        );
      },
    );
  }

  String _buildTypingText(List<User> users) {
    if (users.length == 1) {
      return '${users.first.calcDisplayname()} is typing';
    } else if (users.length == 2) {
      return '${users[0].calcDisplayname()} and ${users[1].calcDisplayname()} are typing';
    } else {
      return 'several people are typing';
    }
  }
}

class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots();

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
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
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = (_controller.value - delay).clamp(0.0, 1.0);
            final opacity = 0.3 + 0.7 * (0.5 + 0.5 * _bounce(t));
            return Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Opacity(
                opacity: opacity,
                child: Text(
                  '.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: GloamColors.textTertiary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  double _bounce(double t) {
    // Simple sine bounce for dot animation
    return (t * 3.14159 * 2).clamp(0, 6.28).toDouble();
  }
}
