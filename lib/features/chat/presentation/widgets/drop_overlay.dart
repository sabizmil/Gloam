import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';

/// Wraps a child in a drag-and-drop zone that accepts files from the OS.
/// Shows a visual overlay when files are hovering.
class FileDropZone extends StatefulWidget {
  const FileDropZone({
    super.key,
    required this.child,
    required this.onFilesDropped,
  });

  final Widget child;
  final void Function(List<DropDoneDetails> details) onFilesDropped;

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        widget.onFilesDropped([details]);
      },
      child: Stack(
        children: [
          widget.child,
          if (_isDragging)
            Positioned.fill(
              child: Container(
                color: GloamColors.accentDim.withValues(alpha: 0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 24),
                    decoration: BoxDecoration(
                      color: GloamColors.bgSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: GloamColors.accent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: GloamColors.accentDim.withValues(alpha: 0.4),
                          blurRadius: 40,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_upload_outlined,
                            size: 36, color: GloamColors.accent),
                        const SizedBox(height: 12),
                        Text(
                          'drop files to upload',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: GloamColors.accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'images, videos, and files',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: GloamColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
