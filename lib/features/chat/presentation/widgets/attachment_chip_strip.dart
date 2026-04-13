import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../data/staged_attachment.dart';

const _chipSize = 64.0;

class AttachmentChipStrip extends StatelessWidget {
  const AttachmentChipStrip({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  final List<StagedAttachment> attachments;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: GloamSpacing.xl,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final attachment in attachments)
            _AttachmentChip(
              key: ValueKey(attachment.id),
              attachment: attachment,
              onRemove: () => onRemove(attachment.id),
              onPreview: () => _previewAttachment(context, attachment),
            ),
        ],
      ),
    );
  }

  void _previewAttachment(BuildContext context, StagedAttachment attachment) {
    final file = attachment.file;
    if (file is MatrixImageFile) {
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          pageBuilder: (_, _, _) => _StagedImagePreview(file: file),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }
    // Non-image files don't get a preview modal — the chip is preview enough.
  }
}

class _AttachmentChip extends StatefulWidget {
  const _AttachmentChip({
    super.key,
    required this.attachment,
    required this.onRemove,
    required this.onPreview,
  });

  final StagedAttachment attachment;
  final VoidCallback onRemove;
  final VoidCallback onPreview;

  @override
  State<_AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<_AttachmentChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final file = widget.attachment.file;
    final isImage = file is MatrixImageFile;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPreview,
        child: SizedBox(
          width: isImage ? _chipSize : 200,
          height: _chipSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: isImage
                    ? _ImageChipBody(file: file)
                    : _FileChipBody(file: file),
              ),
              if (_hovered)
                Positioned(
                  top: -6,
                  right: -6,
                  child: _RemoveButton(
                    onTap: widget.onRemove,
                    foreground: colors.textPrimary,
                    background: colors.bgSurface,
                    border: colors.border,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageChipBody extends StatelessWidget {
  const _ImageChipBody({required this.file});
  final MatrixImageFile file;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.memory(
        file.bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Center(
          child: Icon(Icons.broken_image_outlined,
              size: 20, color: colors.textTertiary),
        ),
      ),
    );
  }
}

class _FileChipBody extends StatelessWidget {
  const _FileChipBody({required this.file});
  final MatrixFile file;

  IconData _iconForMime(String? mime) {
    if (mime == null) return Icons.insert_drive_file_outlined;
    if (mime.startsWith('application/pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.startsWith('application/zip') || mime.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    if (mime.startsWith('text/')) return Icons.description_outlined;
    if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (mime.startsWith('video/')) return Icons.videocam_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.accentDim.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              _iconForMime(file.mimeType),
              size: 18,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatBytes(file.bytes.length),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({
    required this.onTap,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final VoidCallback onTap;
  final Color foreground;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(color: border),
        ),
        child: Icon(Icons.close, size: 12, color: foreground),
      ),
    );
  }
}

/// Fullscreen preview for a staged image — reads directly from the
/// in-memory bytes. Mirrors the non-interactive parts of the timeline's
/// fullscreen viewer; doesn't offer save/copy since the file isn't sent yet.
class _StagedImagePreview extends StatelessWidget {
  const _StagedImagePreview({required this.file});
  final MatrixImageFile file;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          file.name,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: colors.textSecondary,
          ),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(file.bytes),
        ),
      ),
    );
  }
}
