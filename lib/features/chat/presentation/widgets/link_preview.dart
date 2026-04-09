import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';
import '../../data/media_embed_resolver.dart';
import 'embed_card.dart';

/// Data from the homeserver's /preview_url endpoint.
class _UrlPreviewData {
  const _UrlPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUri,
  });

  final String url;
  final String? title;
  final String? description;

  /// Resolved HTTP URI for the OG image (already converted from MXC if needed).
  final Uri? imageUri;

  String get domain {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  /// True if there's anything richer than just the URL itself.
  bool get hasMetadata => title != null || description != null;
}

/// Detects URLs in a message body and renders rich link preview cards
/// using OG metadata from the homeserver's /preview_url endpoint.
class LinkPreview extends ConsumerStatefulWidget {
  const LinkPreview({super.key, required this.body});
  final String body;

  @override
  ConsumerState<LinkPreview> createState() => _LinkPreviewState();
}

class _LinkPreviewState extends ConsumerState<LinkPreview> {
  final List<_UrlPreviewData> _previews = [];
  bool _loading = true;

  static final _urlRegex = RegExp(
    r'https?://[^\s<>\[\]()]+',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _fetchPreviews();
  }

  @override
  void didUpdateWidget(LinkPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) {
      _previews.clear();
      _loading = true;
      _fetchPreviews();
    }
  }

  Future<void> _fetchPreviews() async {
    final matches = _urlRegex.allMatches(widget.body).toList();
    if (matches.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final client = ref.read(matrixServiceProvider).client;
    if (client == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    for (final match in matches) {
      final url = match.group(0)!;

      // Skip URLs that resolve to rich media embeds (YouTube, images, GIFs…)
      if (MediaEmbedResolver.resolve(url) != null) continue;

      try {
        final preview = await _fetchUrlPreview(client, url);
        if (mounted) _previews.add(preview);
      } catch (_) {
        // Graceful degradation — show a basic card with just the URL
        if (mounted) _previews.add(_UrlPreviewData(url: url));
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  static final _dio = Dio(BaseOptions(
    // Don't throw on non-200 — we handle status codes ourselves
    validateStatus: (_) => true,
  ));

  /// Fetches full OG metadata from the homeserver's preview_url endpoint.
  /// The SDK's PreviewForUrl only captures og:image — we need the raw JSON
  /// for og:title and og:description.
  Future<_UrlPreviewData> _fetchUrlPreview(Client client, String url) async {
    final homeserver = client.homeserver;
    final accessToken = client.accessToken;
    if (homeserver == null || accessToken == null) {
      return _UrlPreviewData(url: url);
    }

    // Try authenticated endpoint first, fall back to legacy
    final paths = [
      '_matrix/client/v1/media/preview_url',
      '_matrix/media/v3/preview_url',
    ];

    Map<String, dynamic>? json;
    for (final path in paths) {
      try {
        // Build URI exactly like the SDK does — using resolveUri
        final requestUri = homeserver.resolveUri(Uri(
          path: path,
          queryParameters: {'url': url},
        ));

        final response = await _dio.getUri<Map<String, dynamic>>(
          requestUri,
          options: Options(
            headers: {'Authorization': 'Bearer $accessToken'},
          ),
        );
        if (response.statusCode == 200 && response.data != null) {
          json = response.data!;
          break;
        }
      } catch (_) {
        continue;
      }
    }

    if (json != null) {
      // Resolve og:image — may be an MXC URI that needs conversion
      Uri? imageUri;
      final ogImage = json['og:image'] as String?;
      if (ogImage != null && ogImage.isNotEmpty) {
        if (ogImage.startsWith('mxc://')) {
          try {
            imageUri = await Uri.parse(ogImage).getThumbnailUri(
              client,
              width: 160,
              height: 160,
              method: ThumbnailMethod.crop,
            );
          } catch (_) {
            // Skip thumbnail if resolution fails
          }
        } else {
          imageUri = Uri.tryParse(ogImage);
        }
      }

      return _UrlPreviewData(
        url: url,
        title: json['og:title'] as String?,
        description: json['og:description'] as String?,
        imageUri: imageUri,
      );
    }

    // Fallback: fetch OG metadata client-side (streaming)
    return _fetchOgClientSide(url);
  }

  /// Regex matchers for OG meta tags — split into separate patterns so
  /// apostrophes in content values don't break matching.
  static final _ogMetaRegex = RegExp(
    r'<meta\s[^>]*?property\s*=\s*"og:[^>]*?>',
    caseSensitive: false,
  );
  static final _ogPropertyRegex = RegExp(
    r'property\s*=\s*"og:(\w+)"',
    caseSensitive: false,
  );
  static final _contentRegex = RegExp(
    r'content\s*=\s*"([^"]*)"',
    caseSensitive: false,
  );
  static final _titleTagRegex = RegExp(
    r'<title[^>]*>([^<]+)</title>',
    caseSensitive: false,
  );

  /// Fetches the URL directly and parses OG meta tags from the HTML.
  /// Uses streaming to stop downloading once all metadata is found.
  Future<_UrlPreviewData> _fetchOgClientSide(String url) async {
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'User-Agent': 'Gloam/1.0 (Link Preview)'},
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final stream = response.data?.stream;
      if (stream == null) return _UrlPreviewData(url: url);

      // Accumulate raw bytes and decode as UTF-8
      final bytes = BytesBuilder(copy: false);
      String? title;
      String? description;
      Uri? imageUri;

      await for (final chunk in stream) {
        bytes.add(chunk);

        final text = utf8.decode(bytes.toBytes(), allowMalformed: true);

        // Try to extract OG tags from what we have so far
        for (final match in _ogMetaRegex.allMatches(text)) {
          final tag = match.group(0)!;
          final propMatch = _ogPropertyRegex.firstMatch(tag);
          final contentMatch = _contentRegex.firstMatch(tag);
          if (propMatch == null || contentMatch == null) continue;

          final prop = propMatch.group(1)!;
          final content = contentMatch.group(1)!;

          switch (prop) {
            case 'title':
              title ??= _decodeHtmlEntities(content);
            case 'description':
              description ??= _decodeHtmlEntities(content);
            case 'image':
              if (imageUri == null) {
                var imgUrl = content;
                if (imgUrl.startsWith('/')) {
                  final base = Uri.parse(url);
                  imgUrl = '${base.scheme}://${base.host}$imgUrl';
                }
                imageUri = Uri.tryParse(imgUrl);
              }
          }
        }

        // Stop early once we have all three, or after 128KB
        if ((title != null && description != null && imageUri != null) ||
            bytes.length > 131072) {
          break;
        }
      }

      // Fall back to <title> tag if no og:title
      if (title == null) {
        final fullText = utf8.decode(bytes.toBytes(), allowMalformed: true);
        final titleMatch = _titleTagRegex.firstMatch(fullText);
        if (titleMatch != null) {
          title = _decodeHtmlEntities(titleMatch.group(1)!.trim());
        }
      }

      return _UrlPreviewData(
        url: url,
        title: title,
        description: description,
        imageUri: imageUri,
      );
    } catch (_) {
      return _UrlPreviewData(url: url);
    }
  }

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  @override
  Widget build(BuildContext context) {
    // Build rich media embeds immediately (no fetch needed)
    final richEmbeds = <Widget>[];
    for (final match in _urlRegex.allMatches(widget.body)) {
      final url = match.group(0)!;
      final embedInfo = MediaEmbedResolver.resolve(url);
      if (embedInfo != null) {
        richEmbeds.add(switch (embedInfo.type) {
          MediaEmbedType.directImage || MediaEmbedType.directGif =>
            ImageEmbed(info: embedInfo),
          MediaEmbedType.youtube => YouTubeEmbed(info: embedInfo),
          MediaEmbedType.directVideo => VideoEmbed(info: embedInfo),
          _ => const SizedBox.shrink(),
        });
      }
    }

    // Nothing to show yet
    if (richEmbeds.isEmpty && (_loading || _previews.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...richEmbeds,
        if (!_loading)
          for (final preview in _previews)
            _PreviewCard(preview: preview),
      ],
    );
  }
}

/// Link preview card with hero image on top, accent border on left,
/// title + description + domain footer below.
class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.preview});
  final _UrlPreviewData preview;

  static const _maxWidth = 400.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    final hasImage = preview.imageUri != null;

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
                // Left accent border
                Container(width: 4, color: colors.accentDim),

                // Content column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Hero image
                      if (hasImage)
                        _HeroImage(
                          imageUri: preview.imageUri!,
                          accessToken: ref.read(matrixServiceProvider).client?.accessToken,
                        ),

                      // Text content
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title
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

                            // Description
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

                            // Fallback: show URL when no title/description
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

                            // Domain footer
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

/// Full-width hero image displayed above the text content.
/// Respects the natural aspect ratio of the OG image.
class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.imageUri, this.accessToken});
  final Uri imageUri;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final needsAuth = imageUri.path.contains('_matrix/');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: Image.network(
        imageUri.toString(),
        width: double.infinity,
        fit: BoxFit.cover,
        headers: needsAuth && accessToken != null
            ? {'Authorization': 'Bearer $accessToken'}
            : null,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
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
          );
        },
      ),
    );
  }
}
