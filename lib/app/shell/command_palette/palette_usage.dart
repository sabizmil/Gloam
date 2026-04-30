import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_preferences.dart';
import '../../../features/chat/presentation/providers/timeline_provider.dart';

/// Tracks per-room visit timestamps and per-action invocation counts so the
/// command palette can surface "most-recent rooms" and "most-used actions"
/// at zero-state (⌘K with no query).
class PaletteUsageState {
  const PaletteUsageState({
    this.roomVisits = const {},
    this.actionCounts = const {},
  });

  final Map<String, int> roomVisits; // roomId → epoch millis of last visit
  final Map<String, int> actionCounts; // actionId → invocation count

  PaletteUsageState copyWith({
    Map<String, int>? roomVisits,
    Map<String, int>? actionCounts,
  }) {
    return PaletteUsageState(
      roomVisits: roomVisits ?? this.roomVisits,
      actionCounts: actionCounts ?? this.actionCounts,
    );
  }

  /// Room IDs ordered by most-recent visit first.
  List<String> recentRoomIds({int limit = 3}) {
    final entries = roomVisits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }

  /// Action IDs ordered by invocation count descending.
  List<String> topActionIds({int limit = 3}) {
    final entries = actionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }
}

class PaletteUsageNotifier extends StateNotifier<PaletteUsageState> {
  PaletteUsageNotifier(this._prefs) : super(const PaletteUsageState()) {
    _load();
  }

  final SharedPreferences _prefs;

  static const _kRoomVisits = 'palette_room_visits';
  static const _kActionCounts = 'palette_action_counts';

  void _load() {
    final visits = _decodeIntMap(_prefs.getString(_kRoomVisits));
    final counts = _decodeIntMap(_prefs.getString(_kActionCounts));
    state = PaletteUsageState(roomVisits: visits, actionCounts: counts);
  }

  Map<String, int> _decodeIntMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  void recordRoomVisit(String roomId) {
    final next = Map<String, int>.from(state.roomVisits);
    next[roomId] = DateTime.now().millisecondsSinceEpoch;
    // Cap at 50 entries — keep the most recent.
    if (next.length > 50) {
      final entries = next.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      next
        ..clear()
        ..addEntries(entries.take(50));
    }
    state = state.copyWith(roomVisits: next);
    // Fire-and-forget; SharedPreferences writes are inexpensive but async.
    // ignore: unawaited_futures
    _prefs.setString(_kRoomVisits, jsonEncode(next));
  }

  void recordActionInvocation(String actionId) {
    final next = Map<String, int>.from(state.actionCounts);
    next[actionId] = (next[actionId] ?? 0) + 1;
    state = state.copyWith(actionCounts: next);
    // ignore: unawaited_futures
    _prefs.setString(_kActionCounts, jsonEncode(next));
  }
}

/// Always-alive — visits are auto-recorded by listening to selectedRoomProvider.
/// Eagerly read from app shell so tracking persists across palette opens.
final paletteUsageProvider =
    StateNotifierProvider<PaletteUsageNotifier, PaletteUsageState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final notifier = PaletteUsageNotifier(prefs);
  ref.listen<String?>(selectedRoomProvider, (_, next) {
    if (next != null && next.isNotEmpty) {
      notifier.recordRoomVisit(next);
    }
  });
  return notifier;
});
