import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/download_service.dart';
import '../../../../services/matrix_service.dart';
import '../providers/timeline_provider.dart';

enum _DownloadState { idle, downloading, complete, error }

/// Renders a file attachment with icon, name, size, and interactive download.
class FileMessage extends ConsumerStatefulWidget {
  const FileMessage({
    super.key,
    required this.message,
    this.roomId,
  });

  final TimelineMessage message;
  final String? roomId;

  @override
  ConsumerState<FileMessage> createState() => _FileMessageState();
}

class _FileMessageState extends ConsumerState<FileMessage> {
  _DownloadState _state = _DownloadState.idle;
  String? _savedPath;

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

  Future<void> _onDownload() async {
    final client = ref.read(matrixServiceProvider).client;
    final roomId = widget.roomId;
    if (client == null || roomId == null) return;

    setState(() => _state = _DownloadState.downloading);

    try {
      final matrixFile = await DownloadService.downloadAttachment(
        client,
        roomId,
        widget.message.eventId,
      );

      final savedPath = await DownloadService.saveFile(
        bytes: matrixFile.bytes,
        filename: matrixFile.name,
      );

      if (savedPath == null) {
        // User cancelled save dialog
        if (mounted) setState(() => _state = _DownloadState.idle);
        return;
      }

      if (mounted) {
        setState(() {
          _state = _DownloadState.complete;
          _savedPath = savedPath;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = _DownloadState.error);
      }
    }
  }

  void _onOpen() {
    if (_savedPath != null) {
      DownloadService.openFile(_savedPath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.accentDim.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _iconForMime(widget.message.mimeType),
              size: 20,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.message.displayFilename,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatBytes(widget.message.mediaSizeBytes),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildAction(),
        ],
      ),
    );
  }

  Widget _buildAction() {
    final colors = context.gloam;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (_state) {
        _DownloadState.idle => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _onDownload,
              child: Icon(
                Icons.download_outlined,
                key: const ValueKey('download'),
                size: 18,
                color: colors.textSecondary,
              ),
            ),
          ),
        _DownloadState.downloading => SizedBox(
            key: const ValueKey('loading'),
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          ),
        _DownloadState.complete => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _onOpen,
              child: Icon(
                Icons.check_circle_outlined,
                key: const ValueKey('complete'),
                size: 18,
                color: colors.accent,
              ),
            ),
          ),
        _DownloadState.error => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _onDownload,
              child: Icon(
                Icons.error_outline,
                key: const ValueKey('error'),
                size: 18,
                color: colors.danger,
              ),
            ),
          ),
      },
    );
  }
}

/// Renders a video message as a thumbnail with play overlay.
class VideoMessage extends StatelessWidget {
  const VideoMessage({super.key, required this.message});
  final TimelineMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 260),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 300,
            height: 180,
            child: Center(
              child: Icon(
                Icons.videocam_outlined,
                size: 32,
                color: colors.textTertiary,
              ),
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.bg.withValues(alpha: 0.7),
              shape: BoxShape.circle,
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              Icons.play_arrow,
              size: 28,
              color: colors.textPrimary,
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.bg.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                message.displayFilename,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
