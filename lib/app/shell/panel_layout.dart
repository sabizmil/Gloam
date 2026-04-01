import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_preferences.dart';

/// Persisted panel widths for the desktop layout.
class PanelLayout {
  final double roomListWidth;
  final double rightPanelWidth;
  /// When true, the right panel fills the entire chat area.
  final bool rightPanelFullWidth;

  const PanelLayout({
    this.roomListWidth = defaultRoomListWidth,
    this.rightPanelWidth = defaultRightPanelWidth,
    this.rightPanelFullWidth = false,
  });

  static const double defaultRoomListWidth = 280;
  static const double defaultRightPanelWidth = 380;

  static const double minRoomListWidth = 200;
  static const double maxRoomListWidth = 400;
  static const double minChatWidth = 300;

  /// Below this, the right panel snaps closed.
  static const double snapCloseThreshold = 280;
  /// Below this chat width, the right panel snaps to full width.
  static const double snapFullThreshold = 200;

  PanelLayout copyWith({
    double? roomListWidth,
    double? rightPanelWidth,
    bool? rightPanelFullWidth,
  }) {
    return PanelLayout(
      roomListWidth: roomListWidth ?? this.roomListWidth,
      rightPanelWidth: rightPanelWidth ?? this.rightPanelWidth,
      rightPanelFullWidth: rightPanelFullWidth ?? this.rightPanelFullWidth,
    );
  }
}

class PanelLayoutNotifier extends StateNotifier<PanelLayout> {
  final SharedPreferences _prefs;

  PanelLayoutNotifier(this._prefs) : super(const PanelLayout()) {
    _load();
  }

  void _load() {
    final rlw = _prefs.getDouble('panel_room_list_width');
    final rpw = _prefs.getDouble('panel_right_width');
    final rpf = _prefs.getBool('panel_right_full') ?? false;
    state = PanelLayout(
      roomListWidth: rlw ?? PanelLayout.defaultRoomListWidth,
      rightPanelWidth: rpw ?? PanelLayout.defaultRightPanelWidth,
      rightPanelFullWidth: rpf,
    );
  }

  void setRoomListWidth(double w) {
    final clamped = w.clamp(
      PanelLayout.minRoomListWidth,
      PanelLayout.maxRoomListWidth,
    );
    state = state.copyWith(roomListWidth: clamped);
  }

  /// Set right panel width during drag (no snapping yet).
  void setRightPanelWidth(double w, {required double availableWidth}) {
    // Clamp so the chat area never goes below minChatWidth,
    // but allow going below snapCloseThreshold (snap happens on drag end).
    final maxWidth = availableWidth - PanelLayout.minChatWidth;
    final clamped = w.clamp(PanelLayout.snapCloseThreshold, maxWidth);
    state = state.copyWith(
      rightPanelWidth: clamped,
      rightPanelFullWidth: false,
    );
  }

  /// Called on drag end — apply snap logic.
  void snapRightPanel({required double availableWidth}) {
    final chatWidth = availableWidth - state.rightPanelWidth;

    if (state.rightPanelWidth < PanelLayout.snapCloseThreshold) {
      // Snap closed
      _closeRightPanel();
      return;
    }

    if (chatWidth < PanelLayout.snapFullThreshold) {
      // Snap to full width
      state = state.copyWith(rightPanelFullWidth: true);
      save();
      return;
    }

    // Normal — keep the width as-is
    save();
  }

  void _closeRightPanel() {
    // Reset to default width for next time it opens
    state = state.copyWith(
      rightPanelWidth: PanelLayout.defaultRightPanelWidth,
      rightPanelFullWidth: false,
    );
    save();
  }

  void setRightPanelFullWidth(bool full) {
    state = state.copyWith(rightPanelFullWidth: full);
    save();
  }

  void resetRoomListWidth() {
    state = state.copyWith(roomListWidth: PanelLayout.defaultRoomListWidth);
    _prefs.remove('panel_room_list_width');
  }

  void resetRightPanelWidth() {
    state = state.copyWith(
      rightPanelWidth: PanelLayout.defaultRightPanelWidth,
      rightPanelFullWidth: false,
    );
    save();
  }

  void save() {
    _prefs.setDouble('panel_room_list_width', state.roomListWidth);
    _prefs.setDouble('panel_right_width', state.rightPanelWidth);
    _prefs.setBool('panel_right_full', state.rightPanelFullWidth);
  }
}

final panelLayoutProvider =
    StateNotifierProvider<PanelLayoutNotifier, PanelLayout>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PanelLayoutNotifier(prefs);
});
