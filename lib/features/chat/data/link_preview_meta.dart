class LinkPreviewMeta {
  const LinkPreviewMeta({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    required this.fetchedAt,
    required this.expiresAt,
    this.failed = false,
  });

  final String url;
  final String? title;
  final String? description;

  /// Already-resolved HTTP(S) URL — MXC has been translated via the SDK's
  /// thumbnail endpoint at fetch time. May still require an Authorization
  /// header at render time if the URL contains `_matrix/`.
  final String? imageUrl;

  final int fetchedAt;
  final int expiresAt;
  final bool failed;

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAt;

  bool get hasMetadata => title != null || description != null;

  String get domain {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  Map<String, Object?> toRow() => {
        'url': url,
        'title': title,
        'description': description,
        'image_url': imageUrl,
        'fetched_at': fetchedAt,
        'expires_at': expiresAt,
        'failed': failed ? 1 : 0,
      };

  factory LinkPreviewMeta.fromRow(Map<String, Object?> row) => LinkPreviewMeta(
        url: row['url'] as String,
        title: row['title'] as String?,
        description: row['description'] as String?,
        imageUrl: row['image_url'] as String?,
        fetchedAt: row['fetched_at'] as int,
        expiresAt: row['expires_at'] as int,
        failed: (row['failed'] as int? ?? 0) == 1,
      );

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewMeta &&
      other.url == url &&
      other.title == title &&
      other.description == description &&
      other.imageUrl == imageUrl &&
      other.expiresAt == expiresAt &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(url, title, description, imageUrl, expiresAt, failed);
}
