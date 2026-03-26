import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';
import '../providers/timeline_provider.dart';

/// Renders a file attachment with icon, name, size, and download action.
class FileMessage extends StatelessWidget {
  const FileMessage({super.key, required this.message});
  final TimelineMessage message;

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
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GloamColors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        border: Border.all(color: GloamColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: GloamColors.accentDim.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _iconForMime(message.mimeType),
              size: 20,
              color: GloamColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.body,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: GloamColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatBytes(message.mediaSizeBytes),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: GloamColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.download_outlined,
            size: 18,
            color: GloamColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Renders a video message as a thumbnail with play overlay.
class VideoMessage extends StatelessWidget {
  const VideoMessage({super.key, required this.message});
  final TimelineMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 260),
      decoration: BoxDecoration(
        color: GloamColors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        border: Border.all(color: GloamColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Placeholder — will be replaced with actual thumbnail
          SizedBox(
            width: 300,
            height: 180,
            child: Center(
              child: Icon(
                Icons.videocam_outlined,
                size: 32,
                color: GloamColors.textTertiary,
              ),
            ),
          ),
          // Play button overlay
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: GloamColors.bg.withValues(alpha: 0.7),
              shape: BoxShape.circle,
              border: Border.all(color: GloamColors.border),
            ),
            child: const Icon(
              Icons.play_arrow,
              size: 28,
              color: GloamColors.textPrimary,
            ),
          ),
          // Duration badge
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: GloamColors.bg.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                message.body,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: GloamColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
