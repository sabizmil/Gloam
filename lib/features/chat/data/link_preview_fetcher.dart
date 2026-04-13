import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:matrix/matrix.dart';

class RawPreview {
  RawPreview({this.title, this.description, this.imageUrl});
  String? title;
  String? description;
  String? imageUrl;
}

class FetchedPreview {
  FetchedPreview(this.raw, this.serverTtl);
  final RawPreview raw;
  final Duration? serverTtl;
}

final _dio = Dio(BaseOptions(validateStatus: (_) => true));

Future<FetchedPreview> fetchPreview(Client client, String url) async {
  final fromServer = await _fetchFromHomeserver(client, url);
  if (fromServer != null) return fromServer;

  // Fallback: client-side OG scrape (no TTL hint)
  return FetchedPreview(await _fetchOgClientSide(url), null);
}

Future<FetchedPreview?> _fetchFromHomeserver(Client client, String url) async {
  final homeserver = client.homeserver;
  final accessToken = client.accessToken;
  if (homeserver == null || accessToken == null) return null;

  const paths = [
    '_matrix/client/v1/media/preview_url',
    '_matrix/media/v3/preview_url',
  ];

  for (final path in paths) {
    try {
      final requestUri = homeserver.resolveUri(Uri(
        path: path,
        queryParameters: {'url': url},
      ));
      final response = await _dio.getUri<Map<String, dynamic>>(
        requestUri,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        final raw = await _rawFromJson(client, response.data!);
        return FetchedPreview(raw, _parseCacheControlMaxAge(response.headers));
      }
    } catch (_) {
      continue;
    }
  }
  return null;
}

Future<RawPreview> _rawFromJson(Client client, Map<String, dynamic> json) async {
  String? imageUrl;
  final ogImage = json['og:image'] as String?;
  if (ogImage != null && ogImage.isNotEmpty) {
    if (ogImage.startsWith('mxc://')) {
      try {
        final resolved = await Uri.parse(ogImage).getThumbnailUri(
          client,
          width: 160,
          height: 160,
          method: ThumbnailMethod.crop,
        );
        imageUrl = resolved.toString();
      } catch (_) {}
    } else {
      imageUrl = ogImage;
    }
  }
  return RawPreview(
    title: json['og:title'] as String?,
    description: json['og:description'] as String?,
    imageUrl: imageUrl,
  );
}

Duration? _parseCacheControlMaxAge(Headers headers) {
  final raw = headers.value('cache-control');
  if (raw == null) return null;
  for (final token in raw.split(',')) {
    final kv = token.trim().split('=');
    if (kv.length == 2 && kv[0].trim().toLowerCase() == 'max-age') {
      final secs = int.tryParse(kv[1].trim());
      if (secs != null && secs > 0) return Duration(seconds: secs);
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Client-side OG scraper fallback
// ---------------------------------------------------------------------------

final _ogMetaRegex = RegExp(
  r'<meta\s[^>]*?property\s*=\s*"og:[^>]*?>',
  caseSensitive: false,
);
final _ogPropertyRegex = RegExp(
  r'property\s*=\s*"og:(\w+)"',
  caseSensitive: false,
);
final _contentRegex = RegExp(
  r'content\s*=\s*"([^"]*)"',
  caseSensitive: false,
);
final _titleTagRegex = RegExp(
  r'<title[^>]*>([^<]+)</title>',
  caseSensitive: false,
);

Future<RawPreview> _fetchOgClientSide(String url) async {
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
    if (stream == null) return RawPreview();

    final bytes = BytesBuilder(copy: false);
    String? title;
    String? description;
    String? imageUrl;

    await for (final chunk in stream) {
      bytes.add(chunk);
      final text = utf8.decode(bytes.toBytes(), allowMalformed: true);

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
            if (imageUrl == null) {
              var imgUrl = content;
              if (imgUrl.startsWith('/')) {
                final base = Uri.parse(url);
                imgUrl = '${base.scheme}://${base.host}$imgUrl';
              }
              imageUrl = imgUrl;
            }
        }
      }

      if ((title != null && description != null && imageUrl != null) ||
          bytes.length > 131072) {
        break;
      }
    }

    if (title == null) {
      final fullText = utf8.decode(bytes.toBytes(), allowMalformed: true);
      final titleMatch = _titleTagRegex.firstMatch(fullText);
      if (titleMatch != null) {
        title = _decodeHtmlEntities(titleMatch.group(1)!.trim());
      }
    }

    return RawPreview(
      title: title,
      description: description,
      imageUrl: imageUrl,
    );
  } catch (_) {
    return RawPreview();
  }
}

String _decodeHtmlEntities(String text) {
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&nbsp;', ' ');
}
