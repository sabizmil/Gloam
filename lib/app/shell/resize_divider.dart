import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/gloam_theme_ext.dart';

/// A draggable divider between panels.
/// Positioned via Stack at the panel edge so it overlaps
/// without creating a gap in the layout.
class ResizeDivider extends StatefulWidget {
  const ResizeDivider({
    super.key,
    required this.onDrag,
    this.onDragEnd,
  });

  final void Function(double dx) onDrag;
  final VoidCallback? onDragEnd;

  @override
  State<ResizeDivider> createState() => _ResizeDividerState();
}

class _ResizeDividerState extends State<ResizeDivider> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final active = _hovering || _dragging;
    final lineColor = _dragging ? colors.accent : colors.border;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          if (!_dragging) setState(() => _dragging = true);
          widget.onDrag(details.delta.dx);
        },
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        child: SizedBox(
          width: 12,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: active ? 2 : 0,
              color: active ? lineColor : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}
