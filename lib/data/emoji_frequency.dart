import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tracks and persists frequently used emoji across sessions.
class EmojiFrequency {
  static const _key = 'emoji_frequent';
  static const _maxTracked = 50;

  static final _counts = <String, int>{};
  static bool _loaded = false;

  /// Default frequently used emoji (before any user history).
  static const defaults = [
    '\ud83d\udc4d', // 👍
    '\u2764\ufe0f', // ❤️
    '\ud83d\ude02', // 😂
    '\ud83d\udd25', // 🔥
    '\ud83c\udf89', // 🎉
    '\ud83d\udc40', // 👀
    '\ud83d\ude4f', // 🙏
    '\u2705',       // ✅
    '\ud83d\udcaf', // 💯
    '\ud83d\ude80', // 🚀
    '\ud83e\udd14', // 🤔
    '\ud83d\ude0d', // 😍
    '\ud83d\udc4f', // 👏
    '\ud83c\udf1f', // 🌟
    '\ud83d\udcaa', // 💪
    '\ud83d\ude4c', // 🙌
  ];

  /// Load frequency data from disk. Call once at app start.
  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        for (final entry in list) {
          final map = entry as Map<String, dynamic>;
          _counts[map['e'] as String] = map['c'] as int;
        }
      } catch (_) {
        // Corrupt data — start fresh
      }
    }
    _loaded = true;
  }

  /// Record an emoji usage. Call on every selection.
  static Future<void> record(String emoji) async {
    _counts[emoji] = (_counts[emoji] ?? 0) + 1;
    await _save();
  }

  /// Get the top N frequently used emoji, sorted by usage count.
  /// Falls back to defaults if no history exists.
  static List<String> topN(int n) {
    if (_counts.isEmpty) return defaults.take(n).toList();

    final sorted = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final result = sorted.take(n).map((e) => e.key).toList();

    // Pad with defaults if not enough history
    if (result.length < n) {
      for (final d in defaults) {
        if (result.length >= n) break;
        if (!result.contains(d)) result.add(d);
      }
    }

    return result;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    // Only keep top N to prevent unbounded growth
    final sorted = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final trimmed = sorted.take(_maxTracked);
    final list = trimmed
        .map((e) => {'e': e.key, 'c': e.value})
        .toList();
    await prefs.setString(_key, jsonEncode(list));
  }
}
