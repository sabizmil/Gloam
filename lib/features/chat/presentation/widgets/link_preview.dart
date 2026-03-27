import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';
import '../../data/media_embed_resolver.dart';
import 'embed_card.dart';

/// Detects the first URL in a message body and renders a link preview card
/// using the homeserver's /preview_url endpoint.
class LinkPreview extends ConsumerStatefulWidget {
  const LinkPreview({super.key, required this.body});
  final String body;

  @override
  ConsumerState<LinkPreview> createState() => _LinkPreviewState();
}

class _LinkPreviewState extends ConsumerState<LinkPreview> {
  bool _loading = true;
  String? _url;

  static final _urlRegex = RegExp(
    r'https?://[^\s<>\[\]()]+',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _fetchPreview();
  }

  @override
  void didUpdateWidget(LinkPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) {
      _loading = true;
      _url = null;
      _fetchPreview();
    }
  }

  Future<void> _fetchPreview() async {
    final match = _urlRegex.firstMatch(widget.body);
    if (match == null) {
      setState(() => _loading = false);
      return;
    }

    _url = match.group(0);
    final client = ref.read(matrixServiceProvider).client;
    if (client == null || _url == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      // Attempt to fetch OG preview from homeserver
      await client.getUrlPreview(Uri.parse(_url!));
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _url == null) return const SizedBox.shrink();

    // Check for rich media embed (GIF, image, YouTube, etc.)
    final embedInfo = MediaEmbedResolver.resolve(_url!);
    if (embedInfo != null) {
      return switch (embedInfo.type) {
        MediaEmbedType.directImage || MediaEmbedType.directGif =>
          ImageEmbed(info: embedInfo),
        MediaEmbedType.youtube => YouTubeEmbed(info: embedInfo),
        MediaEmbedType.directVideo => VideoEmbed(info: embedInfo),
        _ => _buildPlainPreview(), // Fallback for unsupported types
      };
    }

    return _buildPlainPreview();
  }

  Widget _buildPlainPreview() {
    // Show a minimal link card for non-media URLs
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication),
        child: Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GloamColors.bg,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        border: Border.all(color: GloamColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: GloamColors.accentDim,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _extractDomain(_url!),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: GloamColors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _url!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: GloamColors.accent,
                    decoration: TextDecoration.underline,
                    decorationColor: GloamColors.accentDim,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.open_in_new,
            size: 14,
            color: GloamColors.textTertiary,
          ),
        ],
      ),
    )));
  }

  String _extractDomain(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }
}
