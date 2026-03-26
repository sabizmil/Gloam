import 'package:flutter/material.dart';

import '../app/theme/color_tokens.dart';

/// Small presence indicator dot overlaid on avatars.
class PresenceDot extends StatelessWidget {
  const PresenceDot({
    super.key,
    required this.isOnline,
    this.size = 10,
  });

  final bool isOnline;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isOnline ? GloamColors.online : GloamColors.textTertiary,
        shape: BoxShape.circle,
        border: Border.all(
          color: GloamColors.bgSurface,
          width: 2,
        ),
      ),
    );
  }
}
