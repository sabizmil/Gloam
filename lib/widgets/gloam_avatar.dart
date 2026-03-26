import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../app/theme/color_tokens.dart';
import '../services/matrix_service.dart';

/// Cache resolved avatar URLs to avoid re-resolving on every rebuild.
final _avatarUrlCache = <String, Uri>{};

/// Avatar widget that loads profile pictures from MXC URIs when available,
/// falling back to a deterministic colored letter circle.
class GloamAvatar extends ConsumerStatefulWidget {
  const GloamAvatar({
    super.key,
    required this.displayName,
    this.mxcUrl,
    this.size = 36,
    this.borderRadius,
  });

  final String displayName;
  final Uri? mxcUrl;
  final double size;
  final double? borderRadius;

  @override
  ConsumerState<GloamAvatar> createState() => _GloamAvatarState();
}

class _GloamAvatarState extends ConsumerState<GloamAvatar> {
  Uri? _resolvedUrl;
  bool _resolved = false;

  static const _avatarColors = [
    Color(0xFF2A4A3A),
    Color(0xFF2A2A4A),
    Color(0xFF4A2A3A),
    Color(0xFF3A2A1A),
    Color(0xFF2A3A4A),
    Color(0xFF1A3A2A),
    Color(0xFF3A2A4A),
    Color(0xFF2A4A4A),
  ];

  static const _textColors = [
    GloamColors.accent,
    Color(0xFF9090B8),
    Color(0xFFC47070),
    Color(0xFFC4A35C),
    Color(0xFF5C8AC4),
    GloamColors.accentBright,
    Color(0xFF8A5CC4),
    Color(0xFF5CC4C4),
  ];

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  @override
  void didUpdateWidget(GloamAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mxcUrl != widget.mxcUrl) {
      _resolved = false;
      _resolveUrl();
    }
  }

  Future<void> _resolveUrl() async {
    final mxc = widget.mxcUrl;
    if (mxc == null || !mxc.toString().startsWith('mxc://')) {
      setState(() => _resolved = true);
      return;
    }

    final cacheKey = mxc.toString();
    if (_avatarUrlCache.containsKey(cacheKey)) {
      _resolvedUrl = _avatarUrlCache[cacheKey];
      setState(() => _resolved = true);
      return;
    }

    final client = ref.read(matrixServiceProvider).client;
    if (client == null) {
      setState(() => _resolved = true);
      return;
    }

    try {
      final uri = await mxc.getThumbnailUri(
        client,
        width: (widget.size * 2).round(),
        height: (widget.size * 2).round(),
        method: ThumbnailMethod.crop,
      );
      _avatarUrlCache[cacheKey] = uri;
      if (mounted) {
        setState(() {
          _resolvedUrl = uri;
          _resolved = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _resolved = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? widget.size / 2;

    if (_resolved && _resolvedUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          _resolvedUrl.toString(),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          headers: _authHeaders,
          errorBuilder: (_, __, ___) => _letterFallback(radius),
        ),
      );
    }

    return _letterFallback(radius);
  }

  Map<String, String>? get _authHeaders {
    final client = ref.read(matrixServiceProvider).client;
    if (client?.accessToken == null) return null;
    return {'Authorization': 'Bearer ${client!.accessToken}'};
  }

  Widget _letterFallback(double radius) {
    final hash = widget.displayName.hashCode.abs();
    final colorIndex = hash % _avatarColors.length;
    final letter = widget.displayName.isNotEmpty
        ? widget.displayName[0].toUpperCase()
        : '?';

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: _avatarColors[colorIndex],
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Text(
          letter,
          style: GoogleFonts.inter(
            fontSize: widget.size * 0.4,
            fontWeight: FontWeight.w500,
            color: _textColors[colorIndex],
          ),
        ),
      ),
    );
  }
}
