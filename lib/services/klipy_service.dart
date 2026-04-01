import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

/// A single GIF/sticker result from Klipy.
class KlipyItem {
  final String slug;
  final String title;
  final String type; // gif, sticker
  final String previewUrl; // sm webp for grid thumbnails
  final String fullUrl; // md webp for sending
  final int previewWidth;
  final int previewHeight;
  final int fullWidth;
  final int fullHeight;
  final String? blurPreview; // base64 blur placeholder

  const KlipyItem({
    required this.slug,
    required this.title,
    required this.type,
    required this.previewUrl,
    required this.fullUrl,
    required this.previewWidth,
    required this.previewHeight,
    required this.fullWidth,
    required this.fullHeight,
    this.blurPreview,
  });

  factory KlipyItem.fromJson(Map<String, dynamic> json) {
    final file = json['file'] as Map<String, dynamic>? ?? {};

    // Preview: sm webp (grid thumbnails)
    final sm = file['sm'] as Map<String, dynamic>? ?? {};
    final smWebp = sm['webp'] as Map<String, dynamic>? ??
        sm['gif'] as Map<String, dynamic>? ??
        {};

    // Full: md webp (for sending)
    final md = file['md'] as Map<String, dynamic>? ?? {};
    final mdWebp = md['webp'] as Map<String, dynamic>? ??
        md['gif'] as Map<String, dynamic>? ??
        {};

    return KlipyItem(
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? 'gif',
      previewUrl: smWebp['url'] as String? ?? '',
      fullUrl: mdWebp['url'] as String? ?? '',
      previewWidth: (smWebp['width'] as num?)?.toInt() ?? 200,
      previewHeight: (smWebp['height'] as num?)?.toInt() ?? 200,
      fullWidth: (mdWebp['width'] as num?)?.toInt() ?? 400,
      fullHeight: (mdWebp['height'] as num?)?.toInt() ?? 400,
      blurPreview: json['blur_preview'] as String?,
    );
  }
}

/// Lightweight REST client for the Klipy GIF/sticker API.
class KlipyService {
  // Passed at compile time: --dart-define=KLIPY_API_KEY=...
  static const _apiKey = String.fromEnvironment('KLIPY_API_KEY');
  static const _baseUrl = 'https://api.klipy.com/api/v1/$_apiKey';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  String _customerId = 'anonymous';

  /// Set the customer ID (hashed Matrix user ID).
  void setCustomerId(String id) => _customerId = id;

  /// Fetch trending GIFs or stickers.
  Future<List<KlipyItem>> trending({
    String type = 'gifs',
    int page = 1,
    int perPage = 24,
    String contentFilter = 'medium',
  }) async {
    return _fetch(
      '$_baseUrl/$type/trending',
      params: {
        'customer_id': _customerId,
        'page': page,
        'per_page': perPage,
        'content_filter': contentFilter,
      },
    );
  }

  /// Search GIFs or stickers.
  Future<List<KlipyItem>> search(
    String query, {
    String type = 'gifs',
    int page = 1,
    int perPage = 24,
    String contentFilter = 'medium',
  }) async {
    return _fetch(
      '$_baseUrl/$type/search',
      params: {
        'q': query,
        'customer_id': _customerId,
        'page': page,
        'per_page': perPage,
        'content_filter': contentFilter,
      },
    );
  }

  /// Notify Klipy that a GIF was shared (helps their ranking).
  Future<void> share(String slug, {String type = 'gifs'}) async {
    try {
      await _dio.post('$_baseUrl/$type/share/$slug');
    } catch (e) {
      debugPrint('[klipy] share failed: $e');
    }
  }

  Future<List<KlipyItem>> _fetch(
    String url, {
    Map<String, dynamic>? params,
  }) async {
    try {
      final response = await _dio.get(url, queryParameters: params);
      final json = response.data as Map<String, dynamic>;
      if (json['result'] != true) return [];

      final data = json['data'] as Map<String, dynamic>? ?? {};
      final items = data['data'] as List? ?? [];

      return items
          .where((item) {
            final map = item as Map<String, dynamic>;
            // Filter out ad items
            return map['type'] != 'ad';
          })
          .map((item) => KlipyItem.fromJson(item as Map<String, dynamic>))
          .where((item) => item.previewUrl.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[klipy] fetch failed: $e');
      return [];
    }
  }
}

final klipyServiceProvider = Provider<KlipyService>((ref) {
  return KlipyService();
});
