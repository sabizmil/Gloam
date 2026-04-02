import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/download_service.dart';
import '../../data/media_embed_resolver.dart';

/// Shared wrapper for all media embeds. Shows the media content with
/// a domain bar at the bottom that opens the original URL externally.
class EmbedCard extends StatelessWidget {
  const EmbedCard({
    super.key,
    required this.info,
    required this.child,
  });

  final MediaEmbedInfo info;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: BoxConstraints(maxWidth: constraints.maxWidth.clamp(0.0, 400.0)),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Media content
          child,
          // Domain bar
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => launchUrl(
                Uri.parse(info.originalUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      info.providerName.toLowerCase(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: colors.textTertiary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.open_in_new,
                        size: 10, color: colors.textTertiary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}

/// Renders a direct image or GIF inline.
class ImageEmbed extends StatelessWidget {
  const ImageEmbed({super.key, required this.info});
  final MediaEmbedInfo info;

  Future<Uint8List?> _downloadBytes() async {
    try {
      final response = await Dio().get<List<int>>(
        info.mediaUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data!);
    } catch (_) {
      return null;
    }
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final colors = context.gloam;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final relPos = RelativeRect.fromLTRB(
      position.dx, position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    );

    showMenu<String>(
      context: context,
      position: relPos,
      color: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      items: [
        PopupMenuItem(
          value: 'copy',
          height: 36,
          child: Row(children: [
            Icon(Icons.copy, size: 16, color: colors.textPrimary),
            const SizedBox(width: 10),
            Text('Copy image',
                style: TextStyle(fontSize: 13, color: colors.textPrimary)),
          ]),
        ),
        PopupMenuItem(
          value: 'save',
          height: 36,
          child: Row(children: [
            Icon(Icons.download, size: 16, color: colors.textPrimary),
            const SizedBox(width: 10),
            Text('Save image',
                style: TextStyle(fontSize: 13, color: colors.textPrimary)),
          ]),
        ),
      ],
    ).then((value) async {
      if (value == null) return;
      final bytes = await _downloadBytes();
      if (bytes == null || !context.mounted) return;

      if (value == 'copy') {
        await Pasteboard.writeImage(bytes);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image copied to clipboard'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else if (value == 'save') {
        final uri = Uri.tryParse(info.mediaUrl);
        final filename = uri?.pathSegments.isNotEmpty == true
            ? uri!.pathSegments.last
            : 'image.png';
        await DownloadService.saveFile(bytes: bytes, filename: filename);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.clamp(0.0, 400.0);
        return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: EmbedCard(
        info: info,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: 300),
          child: Image.network(
            info.mediaUrl,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accentDim,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                ),
              );
            },
            errorBuilder: (_, __, ___) => _fallback(colors),
          ),
        ),
      ),
    );
      },
    );
  }

  Widget _fallback(GloamColorExtension colors) {
    return SizedBox(
      height: 60,
      child: Center(
        child: Text(
          '// failed to load media',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: colors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// Renders a YouTube video with inline playback via WebView on supported
/// platforms, falling back to thumbnail + open-in-browser elsewhere.
class YouTubeEmbed extends StatefulWidget {
  const YouTubeEmbed({super.key, required this.info});
  final MediaEmbedInfo info;

  @override
  State<YouTubeEmbed> createState() => _YouTubeEmbedState();
}

class _YouTubeEmbedState extends State<YouTubeEmbed> {
  bool _playing = false;
  WebViewController? _webController;

  String? get _videoId {
    final uri = Uri.tryParse(widget.info.originalUrl);
    if (uri == null) return null;
    // youtube.com/watch?v=ID
    if (uri.host.contains('youtube.com')) {
      return uri.queryParameters['v'];
    }
    // youtu.be/ID
    if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return null;
  }

  bool get _supportsWebView => Platform.isMacOS || Platform.isIOS;

  void _startPlaying() {
    final id = _videoId;
    if (id == null) return;

    if (_supportsWebView) {
      final html = '''
<!DOCTYPE html>
<html style="width:100%;height:100%;margin:0;padding:0;">
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="referrer" content="strict-origin-when-cross-origin">
</head>
<body style="width:100%;height:100%;margin:0;padding:0;background:#000;overflow:hidden;">
<iframe
  style="width:100%;height:100%;border:none;position:absolute;top:0;left:0;"
  src="https://www.youtube.com/embed/$id?autoplay=1&playsinline=1&rel=0&origin=https://gloam.chat"
  allow="autoplay; encrypted-media; picture-in-picture"
  referrerpolicy="strict-origin-when-cross-origin"
  allowfullscreen>
</iframe>
</body>
</html>
''';
      // Configure WKWebView for inline media playback
      late final PlatformWebViewControllerCreationParams params;
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }
      _webController = WebViewController.fromPlatformCreationParams(params)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadHtmlString(html, baseUrl: 'https://gloam.chat');
      setState(() => _playing = true);
    } else {
      // Fallback: open in browser
      launchUrl(
        Uri.parse(widget.info.originalUrl),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return EmbedCard(
      info: widget.info,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _playing && _webController != null
            ? WebViewWidget(controller: _webController!)
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _startPlaying,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.network(
                        widget.info.mediaUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: colors.bg,
                          child: Center(
                            child: Icon(Icons.play_circle_outline,
                                size: 48, color: colors.textTertiary),
                          ),
                        ),
                      ),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.play_arrow,
                            size: 32, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Renders a video as thumbnail + play overlay (opens externally).
class VideoEmbed extends StatelessWidget {
  const VideoEmbed({super.key, required this.info});
  final MediaEmbedInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return EmbedCard(
      info: info,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(info.originalUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: Container(
            height: 180,
            color: colors.bg,
            child: Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.bgElevated.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border),
                ),
                child: Icon(Icons.play_arrow,
                    size: 28, color: colors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
