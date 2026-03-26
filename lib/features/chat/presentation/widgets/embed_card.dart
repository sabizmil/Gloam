import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';
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
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: GloamColors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        border: Border.all(color: GloamColors.borderSubtle),
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
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: GloamColors.borderSubtle),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      info.providerName.toLowerCase(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: GloamColors.textTertiary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.open_in_new,
                        size: 10, color: GloamColors.textTertiary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a direct image or GIF inline.
class ImageEmbed extends StatelessWidget {
  const ImageEmbed({super.key, required this.info});
  final MediaEmbedInfo info;

  @override
  Widget build(BuildContext context) {
    return EmbedCard(
      info: info,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: Image.network(
          info.mediaUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              height: 150,
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
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      ),
    );
  }

  Widget _fallback() {
    return SizedBox(
      height: 60,
      child: Center(
        child: Text(
          '// failed to load media',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: GloamColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// Renders a YouTube video as thumbnail + play button overlay.
class YouTubeEmbed extends StatelessWidget {
  const YouTubeEmbed({super.key, required this.info});
  final MediaEmbedInfo info;

  @override
  Widget build(BuildContext context) {
    return EmbedCard(
      info: info,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(info.originalUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Thumbnail
              Image.network(
                info.mediaUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 225,
                errorBuilder: (_, __, ___) => Container(
                  height: 225,
                  color: GloamColors.bg,
                  child: const Center(
                    child: Icon(Icons.play_circle_outline,
                        size: 48, color: GloamColors.textTertiary),
                  ),
                ),
              ),
              // Play button overlay
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
    );
  }
}

/// Renders a video as thumbnail + play overlay (opens externally).
class VideoEmbed extends StatelessWidget {
  const VideoEmbed({super.key, required this.info});
  final MediaEmbedInfo info;

  @override
  Widget build(BuildContext context) {
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
            color: GloamColors.bg,
            child: Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: GloamColors.bgElevated.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: GloamColors.border),
                ),
                child: const Icon(Icons.play_arrow,
                    size: 28, color: GloamColors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
