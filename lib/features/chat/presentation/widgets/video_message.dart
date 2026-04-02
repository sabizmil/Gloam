import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../services/debug_server.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/download_service.dart';
import '../../../../services/matrix_service.dart';
import '../providers/timeline_provider.dart';

/// Renders a video message with inline playback.
/// Tap the play button to start, tap the video to toggle play/pause.
/// Tap the expand button to open fullscreen viewer.
class VideoMessage extends ConsumerStatefulWidget {
  const VideoMessage({super.key, required this.message, this.roomId});
  final TimelineMessage message;
  final String? roomId;

  @override
  ConsumerState<VideoMessage> createState() => _VideoMessageState();
}

class _VideoMessageState extends ConsumerState<VideoMessage> {
  Player? _player;
  VideoController? _videoController;
  bool _loading = false;
  bool _playing = false;
  bool _error = false;
  String? _localPath;
  Uint8List? _thumbnailBytes;
  String? _thumbnailHttpUrl;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null || widget.roomId == null) return;

    final room = client.getRoomById(widget.roomId!);
    if (room == null) return;

    // Load server-provided thumbnail if available
    try {
      final event = await room.getEventById(widget.message.eventId);
      if (event != null && event.hasThumbnail) {
        if (room.encrypted) {
          final thumbFile =
              await event.downloadAndDecryptAttachment(getThumbnail: true);
          if (mounted) setState(() => _thumbnailBytes = thumbFile.bytes);
        } else {
          final mxcUrl = event.thumbnailMxcUrl;
          if (mxcUrl != null) {
            final httpUrl = mxcUrl.toString().replaceFirst(
              'mxc://',
              '${client.homeserver}/_matrix/media/v3/download/',
            );
            if (mounted) setState(() => _thumbnailHttpUrl = httpUrl);
          }
        }
      }
    } catch (_) {}
  }

  Map<String, String>? get _authHeaders {
    final client = ref.read(matrixServiceProvider).client;
    if (client?.accessToken == null) return null;
    return {'Authorization': 'Bearer ${client!.accessToken}'};
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    if (_player != null) return;
    setState(() => _loading = true);

    try {
      final client = ref.read(matrixServiceProvider).client;
      if (client == null) throw Exception('No client');

      String? videoPath;

      // For encrypted rooms, download and decrypt to a temp file
      if (widget.roomId != null) {
        final room = client.getRoomById(widget.roomId!);
        if (room != null && room.encrypted) {
          final event = await room.getEventById(widget.message.eventId);
          if (event != null) {
            final matrixFile = await event.downloadAndDecryptAttachment();
            final dir = await getTemporaryDirectory();
            final file = File('${dir.path}/${widget.message.body}');
            await file.writeAsBytes(matrixFile.bytes);
            videoPath = file.path;
          }
        }
      }

      // For unencrypted, use the HTTP URL directly
      if (videoPath == null && widget.message.mediaUrl != null) {
        final httpUrl = widget.message.mediaUrl!.toString();
        if (httpUrl.startsWith('http')) {
          videoPath = httpUrl;
        } else {
          // mxc:// URL — resolve to HTTP
          final resolved = client.homeserver != null
              ? httpUrl.replaceFirst(
                  'mxc://',
                  '${client.homeserver}/_matrix/media/v3/download/',
                )
              : httpUrl;
          videoPath = resolved;
        }
      }

      if (videoPath == null) throw Exception('No video source');

      _localPath = videoPath;
      _player = Player();
      _videoController = VideoController(_player!);

      await _player!.open(Media(videoPath), play: true);
      _player!.stream.playing.listen((playing) {
        if (mounted) setState(() => _playing = playing);
      });

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  Size _stableSize(double availableWidth) {
    final maxW = availableWidth.clamp(0.0, 400.0);
    const maxH = 260.0;
    final w = widget.message.imageWidth;
    final h = widget.message.imageHeight;
    if (w != null && h != null && w > 0 && h > 0) {
      final scale = (maxW / w).clamp(0.0, 1.0).clamp(0.0, maxH / h);
      return Size(w * scale, h * scale);
    }
    return Size(maxW.clamp(0.0, 300.0), 180);
  }

  void _openFullscreen() {
    if (_player == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _FullscreenVideoView(
          player: _player!,
          controller: _videoController!,
          filename: widget.message.body,
          localPath: _localPath,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _stableSize(constraints.maxWidth);
        return GestureDetector(
      onTap: _player != null ? () {
        if (_playing) {
          _player!.pause();
        } else {
          _player!.play();
        }
      } : _initPlayer,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: colors.bgElevated,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          border: Border.all(color: colors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video, thumbnail, or placeholder
            if (_videoController != null)
              Positioned.fill(
                child: Video(
                  controller: _videoController!,
                  controls: NoVideoControls,
                ),
              )
            else if (_thumbnailBytes != null)
              Positioned.fill(
                child: Image.memory(
                  _thumbnailBytes!,
                  fit: BoxFit.cover,
                ),
              )
            else if (_thumbnailHttpUrl != null)
              Positioned.fill(
                child: Image.network(
                  _thumbnailHttpUrl!,
                  fit: BoxFit.cover,
                  headers: _authHeaders,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(Icons.videocam_outlined,
                        size: 32, color: colors.textTertiary),
                  ),
                ),
              )
            else
              Center(
                child: Icon(
                  Icons.videocam_outlined,
                  size: 32,
                  color: colors.textTertiary,
                ),
              ),

            // Play/pause overlay
            if (!_playing)
              GestureDetector(
                onTap: _player != null ? () => _player!.play() : _initPlayer,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.bg.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border),
                  ),
                  child: _loading
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.accent,
                          ),
                        )
                      : Icon(
                          Icons.play_arrow,
                          size: 28,
                          color: colors.textPrimary,
                        ),
                ),
              ),

            // Filename label
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.bg.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.message.body,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Fullscreen button
            if (_player != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: _openFullscreen,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: colors.bg.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.border),
                      ),
                      child: Icon(
                        Icons.fullscreen,
                        size: 18,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
      },
    );
  }
}

// ── Fullscreen Video Viewer ──

class _FullscreenVideoView extends StatelessWidget {
  const _FullscreenVideoView({
    required this.player,
    required this.controller,
    required this.filename,
    this.localPath,
  });

  final Player player;
  final VideoController controller;
  final String filename;
  final String? localPath;

  void _saveVideo(BuildContext context) async {
    if (localPath == null) return;
    try {
      final file = File(localPath!);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await DownloadService.saveFile(bytes: bytes, filename: filename);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (player.state.playing) {
            player.pause();
          } else {
            player.play();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black87,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.close, color: colors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              filename,
              style: GoogleFonts.inter(
                  fontSize: 13, color: colors.textSecondary),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.download, color: colors.textSecondary),
                tooltip: 'Save video',
                onPressed: () => _saveVideo(context),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Center(
            child: Video(
              controller: controller,
              controls: MaterialVideoControls,
            ),
          ),
        ),
      ),
    );
  }
}
