import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/debug_server.dart';
import '../../../../services/matrix_service.dart';
import '../providers/timeline_provider.dart';  // TimelineMessage, MessageSendState

/// Cache decrypted image bytes to avoid re-downloading.
final _imageCache = <String, Uint8List>{};

/// Renders an image message. For encrypted rooms, downloads and decrypts
/// the attachment via the SDK. For unencrypted rooms, uses Image.network.
class ImageMessage extends ConsumerStatefulWidget {
  const ImageMessage({super.key, required this.message, this.roomId});
  final TimelineMessage message;
  final String? roomId;

  @override
  ConsumerState<ImageMessage> createState() => _ImageMessageState();
}

class _ImageMessageState extends ConsumerState<ImageMessage> {
  Uint8List? _imageBytes;
  Uri? _httpUrl;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    DebugServer.logs.add('[ImageMessage] init: id=${widget.message.eventId} '
        'send=${widget.message.sendState} local=${widget.message.isLocalEcho} '
        'fileStatus=${widget.message.fileSendingStatus} '
        'url=${widget.message.mediaUrl} type=${widget.message.type}');
    _loadImage();
  }

  @override
  void didUpdateWidget(ImageMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload when the event updates (e.g., local echo replaced by server echo
    // with a real MXC URL after upload completes)
    DebugServer.logs.add('[ImageMessage] didUpdate: id=${widget.message.eventId} '
        'send=${widget.message.sendState} local=${widget.message.isLocalEcho} '
        'fileStatus=${widget.message.fileSendingStatus} '
        'url=${widget.message.mediaUrl}');
    if (oldWidget.message.eventId != widget.message.eventId ||
        oldWidget.message.mediaUrl != widget.message.mediaUrl ||
        oldWidget.message.sendState != widget.message.sendState) {
      _imageBytes = null;
      _httpUrl = null;
      _loading = true;
      _error = false;
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final eventId = widget.message.eventId;

    // Check cache first
    if (_imageCache.containsKey(eventId)) {
      setState(() {
        _imageBytes = _imageCache[eventId];
        _loading = false;
      });
      return;
    }

    final client = ref.read(matrixServiceProvider).client;
    if (client == null || widget.message.mediaUrl == null) {
      setState(() { _loading = false; _error = true; });
      return;
    }

    try {
      // Try to get the event from the room to use SDK's download+decrypt
      final roomId = widget.roomId;
      if (roomId != null) {
        final room = client.getRoomById(roomId);
        if (room != null) {
          final event = await room.getEventById(eventId);
          if (event != null && event.isAttachmentEncrypted) {
            // Encrypted: download + decrypt via SDK
            final matrixFile = await event.downloadAndDecryptAttachment();
            _imageCache[eventId] = matrixFile.bytes;
            if (mounted) {
              setState(() { _imageBytes = matrixFile.bytes; _loading = false; });
            }
            return;
          }
        }
      }

      // Unencrypted: resolve MXC to HTTP URL
      final httpUri = await widget.message.mediaUrl!.getDownloadUri(client);
      if (mounted) {
        setState(() { _httpUrl = httpUri; _loading = false; });
      }
    } catch (e) {
      Logs().e('Image load failed', e);
      if (mounted) {
        setState(() { _loading = false; _error = true; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return GestureDetector(
      onTap: (_imageBytes != null || _httpUrl != null) ? () => _openFullscreen(context) : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
        decoration: BoxDecoration(
          color: colors.bgElevated,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          border: Border.all(color: colors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final colors = context.gloam;
    // Uploading state — show progress with stage label
    final sendState = widget.message.sendState;
    final fileSendingStatus = widget.message.fileSendingStatus;
    if (sendState == MessageSendState.sending && widget.message.mediaUrl == null) {
      final label = switch (fileSendingStatus) {
        'generatingThumbnail' => 'Generating thumbnail...',
        'encrypting' => 'Encrypting...',
        'uploading' => 'Uploading...',
        _ => 'Sending...',
      };
      return SizedBox(
        width: 240,
        height: 160,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent.withAlpha(180),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: colors.textTertiary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return SizedBox(
        width: 240, height: 160,
        child: Center(
          child: SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: colors.accentDim),
          ),
        ),
      );
    }

    if (_error) return _errorWidget();

    // Decrypted bytes (encrypted rooms)
    if (_imageBytes != null) {
      return Image.memory(
        _imageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _errorWidget(),
      );
    }

    // HTTP URL (unencrypted rooms)
    if (_httpUrl != null) {
      return Image.network(
        _httpUrl.toString(),
        fit: BoxFit.cover,
        headers: _authHeaders,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: 240, height: 160,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2, color: colors.accentDim,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _errorWidget(),
      );
    }

    return _errorWidget();
  }

  Widget _errorWidget() {
    final colors = context.gloam;
    return SizedBox(
      width: 200, height: 80,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 24, color: colors.textTertiary),
            const SizedBox(height: 4),
            Text(widget.message.body,
              style: GoogleFonts.inter(fontSize: 11, color: colors.textTertiary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Map<String, String>? get _authHeaders {
    final client = ref.read(matrixServiceProvider).client;
    if (client?.accessToken == null) return null;
    return {'Authorization': 'Bearer ${client!.accessToken}'};
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _FullscreenImageView(
          bytes: _imageBytes,
          url: _httpUrl,
          filename: widget.message.body,
          authHeaders: _authHeaders,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

class _FullscreenImageView extends StatelessWidget {
  const _FullscreenImageView({this.bytes, this.url, required this.filename, this.authHeaders});
  final Uint8List? bytes;
  final Uri? url;
  final String filename;
  final Map<String, String>? authHeaders;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
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
            title: Text(filename,
              style: GoogleFonts.inter(fontSize: 13, color: colors.textSecondary)),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: bytes != null
                  ? Image.memory(bytes!)
                  : (url != null ? Image.network(url.toString(), headers: authHeaders) : const SizedBox()),
            ),
          ),
        ),
      ),
    );
  }
}
