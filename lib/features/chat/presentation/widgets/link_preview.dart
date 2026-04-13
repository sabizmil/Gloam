import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';
import '../../data/link_preview_meta.dart';
import '../../data/media_embed_resolver.dart';
import '../../domain/url_extraction.dart';
import '../providers/link_preview_provider.dart';
import 'embed_card.dart';

/// Detects URLs in a message body and renders rich link preview cards.
/// Rich embeds (YouTube, direct images, GIFs) are rendered synchronously.
/// Other URLs delegate to [linkPreviewProvider], which caches OG metadata
/// to disk with a TTL — widgets never fetch directly.
class LinkPreview extends StatelessWidget {
  const LinkPreview({super.key, required this.body});
  final String body;

  @override
  Widget build(BuildContext context) {
    final richEmbeds = <Widget>[];
    final ogUrls = <String>[];

    for (final url in extractUrls(body)) {
      final embedInfo = MediaEmbedResolver.resolve(url);
      if (embedInfo != null) {
        richEmbeds.add(switch (embedInfo.type) {
          MediaEmbedType.directImage ||
          MediaEmbedType.directGif =>
            ImageEmbed(info: embedInfo),
          MediaEmbedType.youtube => YouTubeEmbed(info: embedInfo),
          MediaEmbedType.directVideo => VideoEmbed(info: embedInfo),
          _ => const SizedBox.shrink(),
        });
      } else {
        ogUrls.add(url);
      }
    }

    if (richEmbeds.isEmpty && ogUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...richEmbeds,
        for (final url in ogUrls) _CachedPreviewCard(url: url),
      ],
    );
  }
}

class _CachedPreviewCard extends ConsumerWidget {
  const _CachedPreviewCard({required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(linkPreviewProvider(url));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (meta) {
        if (meta.failed) return const SizedBox.shrink();
        if (!meta.hasMetadata && meta.imageUrl == null) {
          return const SizedBox.shrink();
        }
        return _PreviewCard(preview: meta);
      },
    );
  }
}

class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.preview});
  final LinkPreviewMeta preview;

  static const _maxWidth = 400.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    final hasImage = preview.imageUrl != null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => launchUrl(
          Uri.parse(preview.url),
          mode: LaunchMode.externalApplication,
        ),
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
            border: Border.all(color: colors.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: colors.accentDim),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasImage)
                        _HeroImage(
                          imageUrl: preview.imageUrl!,
                          accessToken: ref
                              .read(matrixServiceProvider)
                              .client
                              ?.accessToken,
                        ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (preview.title != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  preview.title!,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (preview.description != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  preview.description!,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                    height: 1.4,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (!preview.hasMetadata)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  preview.url,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: colors.accent,
                                    decoration: TextDecoration.underline,
                                    decorationColor: colors.accentDim,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    preview.domain,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: colors.textTertiary,
                                      letterSpacing: 0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.open_in_new,
                                  size: 10,
                                  color: colors.textTertiary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.imageUrl, this.accessToken});
  final String imageUrl;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final needsAuth = imageUrl.contains('_matrix/');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: double.infinity,
        fit: BoxFit.cover,
        httpHeaders: needsAuth && accessToken != null
            ? {'Authorization': 'Bearer $accessToken'}
            : null,
        errorWidget: (_, _, _) => const SizedBox.shrink(),
        placeholder: (_, _) => Container(
          height: 120,
          color: colors.bgElevated,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.accentDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
