/// Classifies URLs into media embed types and extracts thumbnail/media URLs.
class MediaEmbedResolver {
  static final _cache = <String, MediaEmbedInfo>{};

  /// Resolve a URL to its embed info. Returns null for plain URLs with no
  /// special media treatment.
  static MediaEmbedInfo? resolve(String url) {
    if (_cache.containsKey(url)) return _cache[url];

    final info = _classify(url);
    if (info != null) _cache[url] = info;
    return info;
  }

  static MediaEmbedInfo? _classify(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final lower = url.toLowerCase();

    // Direct GIF
    if (lower.endsWith('.gif') || lower.contains('.gif?')) {
      return MediaEmbedInfo(
        type: MediaEmbedType.directGif,
        originalUrl: url,
        mediaUrl: url,
        providerName: uri.host,
      );
    }

    // Direct image
    if (_isImageExtension(lower)) {
      return MediaEmbedInfo(
        type: MediaEmbedType.directImage,
        originalUrl: url,
        mediaUrl: url,
        providerName: uri.host,
      );
    }

    // Direct video
    if (_isVideoExtension(lower)) {
      return MediaEmbedInfo(
        type: MediaEmbedType.directVideo,
        originalUrl: url,
        mediaUrl: url,
        providerName: uri.host,
      );
    }

    // YouTube
    final youtubeId = _extractYouTubeId(uri);
    if (youtubeId != null) {
      return MediaEmbedInfo(
        type: MediaEmbedType.youtube,
        originalUrl: url,
        mediaUrl: 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg',
        providerName: 'YouTube',
        title: null, // Could fetch via oEmbed later
      );
    }

    // Giphy
    if (uri.host.contains('giphy.com') || uri.host.contains('media.giphy.com')) {
      // media.giphy.com URLs are direct GIFs
      if (uri.host.contains('media')) {
        return MediaEmbedInfo(
          type: MediaEmbedType.directGif,
          originalUrl: url,
          mediaUrl: url,
          providerName: 'Giphy',
        );
      }
      // giphy.com/gifs/ URLs — try to extract the direct media URL
      final giphyId = _extractGiphyId(uri);
      if (giphyId != null) {
        return MediaEmbedInfo(
          type: MediaEmbedType.directGif,
          originalUrl: url,
          mediaUrl: 'https://media.giphy.com/media/$giphyId/giphy.gif',
          providerName: 'Giphy',
        );
      }
    }

    // Tenor
    if (uri.host.contains('tenor.com')) {
      return MediaEmbedInfo(
        type: MediaEmbedType.tenor,
        originalUrl: url,
        mediaUrl: url, // Would need API call for direct media
        providerName: 'Tenor',
      );
    }

    // Imgur
    if (uri.host.contains('imgur.com') || uri.host.contains('i.imgur.com')) {
      if (uri.host == 'i.imgur.com') {
        return MediaEmbedInfo(
          type: lower.endsWith('.gif') || lower.endsWith('.gifv')
              ? MediaEmbedType.directGif
              : MediaEmbedType.directImage,
          originalUrl: url,
          mediaUrl: url.replaceAll('.gifv', '.gif'),
          providerName: 'Imgur',
        );
      }
    }

    return null; // No special treatment — use default link preview
  }

  static bool _isImageExtension(String url) {
    return url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.png') ||
        url.endsWith('.webp') ||
        url.endsWith('.svg') ||
        url.contains('.jpg?') ||
        url.contains('.jpeg?') ||
        url.contains('.png?') ||
        url.contains('.webp?');
  }

  static bool _isVideoExtension(String url) {
    return url.endsWith('.mp4') ||
        url.endsWith('.webm') ||
        url.endsWith('.mov') ||
        url.contains('.mp4?') ||
        url.contains('.webm?');
  }

  static String? _extractYouTubeId(Uri uri) {
    if (uri.host.contains('youtube.com') || uri.host.contains('youtu.be')) {
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }
      if (uri.path.contains('/watch')) {
        return uri.queryParameters['v'];
      }
      if (uri.path.contains('/shorts/')) {
        final segments = uri.pathSegments;
        final idx = segments.indexOf('shorts');
        return idx >= 0 && idx + 1 < segments.length
            ? segments[idx + 1]
            : null;
      }
    }
    return null;
  }

  static String? _extractGiphyId(Uri uri) {
    // giphy.com/gifs/title-id or giphy.com/gifs/id
    if (uri.pathSegments.contains('gifs') || uri.pathSegments.contains('media')) {
      final last = uri.pathSegments.last;
      // The ID is after the last dash, or is the whole segment
      final dashIdx = last.lastIndexOf('-');
      return dashIdx >= 0 ? last.substring(dashIdx + 1) : last;
    }
    return null;
  }
}

enum MediaEmbedType {
  directImage,
  directGif,
  directVideo,
  youtube,
  vimeo,
  giphy,
  tenor,
  imgur,
  ogRich,
  plain,
}

class MediaEmbedInfo {
  final MediaEmbedType type;
  final String originalUrl;
  final String mediaUrl;
  final String providerName;
  final String? title;
  final String? description;

  const MediaEmbedInfo({
    required this.type,
    required this.originalUrl,
    required this.mediaUrl,
    required this.providerName,
    this.title,
    this.description,
  });
}
