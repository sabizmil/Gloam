import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/debug_server.dart';
import '../../../../services/matrix_service.dart';
import '../../data/link_preview_cache.dart';
import '../../data/link_preview_fetcher.dart';
import '../../data/link_preview_meta.dart';

final linkPreviewProvider =
    FutureProvider.family<LinkPreviewMeta, String>((ref, url) async {
  final cache = LinkPreviewCache.instance;
  final cached = await cache.get(url);
  final now = DateTime.now().millisecondsSinceEpoch;

  if (cached != null && cached.expiresAt > now) {
    DebugServer.linkPreviewStats.hits++;
    return cached;
  }

  if (cached != null) {
    // Stale-while-revalidate: serve the stale entry now, refresh in bg.
    DebugServer.linkPreviewStats.staleHits++;
    unawaited(_refreshInBackground(ref, url, cache, cached));
    return cached;
  }

  DebugServer.linkPreviewStats.misses++;
  return _fetchAndStore(ref, url, cache);
});

Future<void> _refreshInBackground(
  Ref ref,
  String url,
  LinkPreviewCache cache,
  LinkPreviewMeta previous,
) async {
  try {
    final fresh = await _fetchAndStore(ref, url, cache);
    if (fresh != previous) {
      ref.invalidateSelf();
    }
  } catch (_) {
    // Silent — keep serving the stale entry.
  }
}

Future<LinkPreviewMeta> _fetchAndStore(
  Ref ref,
  String url,
  LinkPreviewCache cache,
) async {
  final client = ref.read(matrixServiceProvider).client;
  final now = DateTime.now().millisecondsSinceEpoch;

  if (client == null) {
    // No client — return a bare entry marked expired so next attempt retries.
    return LinkPreviewMeta(
      url: url,
      fetchedAt: now,
      expiresAt: 0,
    );
  }

  try {
    final fetched = await fetchPreview(client, url);
    final ttl = fetched.serverTtl ?? LinkPreviewCache.defaultTtl;
    final stored = LinkPreviewMeta(
      url: url,
      title: fetched.raw.title,
      description: fetched.raw.description,
      imageUrl: fetched.raw.imageUrl,
      fetchedAt: now,
      expiresAt: now + ttl.inMilliseconds,
    );
    await cache.put(stored);
    DebugServer.linkPreviewStats.fetches++;
    return stored;
  } catch (_) {
    final failed = LinkPreviewMeta(
      url: url,
      fetchedAt: now,
      expiresAt: now + LinkPreviewCache.failedTtl.inMilliseconds,
      failed: true,
    );
    await cache.put(failed);
    DebugServer.linkPreviewStats.failures++;
    return failed;
  }
}
