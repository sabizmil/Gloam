import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app/theme/color_tokens.dart';

/// Deterministic avatar with letter fallback.
/// Colors are derived from the display name hash.
class GloamAvatar extends StatelessWidget {
  const GloamAvatar({
    super.key,
    required this.displayName,
    this.size = 36,
    this.borderRadius,
  });

  final String displayName;
  final double size;
  final double? borderRadius;

  static const _avatarColors = [
    Color(0xFF2A4A3A), // green
    Color(0xFF2A2A4A), // indigo
    Color(0xFF4A2A3A), // burgundy
    Color(0xFF3A2A1A), // amber
    Color(0xFF2A3A4A), // steel
    Color(0xFF1A3A2A), // forest
    Color(0xFF3A2A4A), // purple
    Color(0xFF2A4A4A), // teal
  ];

  static const _textColors = [
    GloamColors.accent,
    Color(0xFF9090B8),
    Color(0xFFC47070),
    Color(0xFFC4A35C),
    Color(0xFF5C8AC4),
    GloamColors.accentBright,
    Color(0xFF8A5CC4),
    Color(0xFF5CC4C4),
  ];

  @override
  Widget build(BuildContext context) {
    final hash = displayName.hashCode.abs();
    final colorIndex = hash % _avatarColors.length;
    final letter =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _avatarColors[colorIndex],
        borderRadius: BorderRadius.circular(borderRadius ?? size / 2),
      ),
      child: Center(
        child: Text(
          letter,
          style: GoogleFonts.inter(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w500,
            color: _textColors[colorIndex],
          ),
        ),
      ),
    );
  }
}
