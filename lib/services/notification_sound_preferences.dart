import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme/theme_preferences.dart';

/// Notification sound preferences.
class NotificationSoundPrefs {
  final bool enabled;
  final String globalSound;
  final Map<String, String?> perRoom; // roomId → soundId (null = use global)

  const NotificationSoundPrefs({
    this.enabled = true,
    this.globalSound = 'soft_tap',
    this.perRoom = const {},
  });

  NotificationSoundPrefs copyWith({
    bool? enabled,
    String? globalSound,
    Map<String, String?>? perRoom,
  }) {
    return NotificationSoundPrefs(
      enabled: enabled ?? this.enabled,
      globalSound: globalSound ?? this.globalSound,
      perRoom: perRoom ?? this.perRoom,
    );
  }

  /// Resolve the effective sound for a room.
  /// Returns null if sounds are disabled, 'silent' if explicitly silenced.
  String? getEffectiveSound(String roomId) {
    if (!enabled) return null;
    final override = perRoom[roomId];
    if (override != null) return override == 'silent' ? null : override;
    return globalSound;
  }
}

class NotificationSoundPrefsNotifier
    extends StateNotifier<NotificationSoundPrefs> {
  final SharedPreferences _prefs;

  NotificationSoundPrefsNotifier(this._prefs)
      : super(const NotificationSoundPrefs()) {
    _load();
  }

  void _load() {
    final enabled = _prefs.getBool('notification_sound_enabled') ?? true;
    final globalSound =
        _prefs.getString('notification_sound_global') ?? 'soft_tap';
    final perRoomJson = _prefs.getString('notification_sound_rooms');
    Map<String, String?> perRoom = {};
    if (perRoomJson != null) {
      final decoded = jsonDecode(perRoomJson) as Map<String, dynamic>;
      perRoom = decoded.map((k, v) => MapEntry(k, v as String?));
    }
    state = NotificationSoundPrefs(
      enabled: enabled,
      globalSound: globalSound,
      perRoom: perRoom,
    );
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
    _prefs.setBool('notification_sound_enabled', enabled);
  }

  void setGlobalSound(String sound) {
    state = state.copyWith(globalSound: sound);
    _prefs.setString('notification_sound_global', sound);
  }

  void setRoomSound(String roomId, String? sound) {
    final newMap = Map<String, String?>.from(state.perRoom);
    if (sound == null) {
      newMap.remove(roomId);
    } else {
      newMap[roomId] = sound;
    }
    state = state.copyWith(perRoom: newMap);
    _prefs.setString('notification_sound_rooms', jsonEncode(newMap));
  }
}

final notificationSoundPrefsProvider = StateNotifierProvider<
    NotificationSoundPrefsNotifier, NotificationSoundPrefs>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return NotificationSoundPrefsNotifier(prefs);
});
