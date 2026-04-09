import 'package:flutter/material.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';

/// Renders a Matrix spoiler (`data-mx-spoiler`).
///
/// Initially shows a dark box with a "Spoiler" label. Tapping reveals the
/// child content.  Tapping again re-hides it.
class SpoilerWidget extends StatefulWidget {
  const SpoilerWidget({
    super.key,
    required this.child,
    this.reason,
  });

  /// The hidden content.
  final Widget child;

  /// Optional spoiler reason shown in the label (e.g. "Book ending").
  final String? reason;

  @override
  State<SpoilerWidget> createState() => _SpoilerWidgetState();
}

class _SpoilerWidgetState extends State<SpoilerWidget> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;

    if (_revealed) {
      return GestureDetector(
        onTap: () => setState(() => _revealed = false),
        child: widget.child,
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _revealed = true),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: GloamSpacing.sm,
          vertical: GloamSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        ),
        child: Text(
          widget.reason?.isNotEmpty == true
              ? 'Spoiler: ${widget.reason}'
              : 'Spoiler',
          style: TextStyle(
            fontSize: 13,
            color: colors.textTertiary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
