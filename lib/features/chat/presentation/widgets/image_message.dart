import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';
import '../providers/timeline_provider.dart';

/// Renders an image message — resolves MXC URI to HTTP URL for display.
class ImageMessage extends ConsumerStatefulWidget {
  const ImageMessage({super.key, required this.message});
  final TimelineMessage message;

  @override
  ConsumerState<ImageMessage> createState() => _ImageMessageState();
}

class _ImageMessageState extends ConsumerState<ImageMessage> {
  Uri? _httpUrl;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  Future<void> _resolveUrl() async {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null || widget.message.mediaUrl == null) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }

    try {
      final httpUri =
          await widget.message.mediaUrl!.getDownloadUri(client);
      if (mounted) {
        setState(() {
          _httpUrl = httpUri;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = 400.0;
    final maxHeight = 300.0;

    return GestureDetector(
      onTap: _httpUrl != null ? () => _openFullscreen(context) : null,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: GloamColors.bgElevated,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          border: Border.all(color: GloamColors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const SizedBox(
        width: 240,
        height: 160,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: GloamColors.accentDim,
            ),
          ),
        ),
      );
    }

    if (_error || _httpUrl == null) {
      return SizedBox(
        width: 200,
        height: 80,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined,
                  size: 24, color: GloamColors.textTertiary),
              const SizedBox(height: 4),
              Text(
                widget.message.body,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: GloamColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    return Image.network(
      _httpUrl.toString(),
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: 240,
          height: 160,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: GloamColors.accentDim,
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (_, e, s) => SizedBox(
        width: 200,
        height: 80,
        child: Center(
          child: Text(
            widget.message.body,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: GloamColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    if (_httpUrl == null) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, e, s) => _FullscreenImageView(
          url: _httpUrl!,
          filename: widget.message.body,
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

class _FullscreenImageView extends StatelessWidget {
  const _FullscreenImageView({
    required this.url,
    required this.filename,
  });

  final Uri url;
  final String filename;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: GloamColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          filename,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: GloamColors.textSecondary,
          ),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(url.toString()),
        ),
      ),
    );
  }
}
