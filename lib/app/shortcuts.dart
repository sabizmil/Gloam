import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global keyboard shortcut definitions for Gloam.
/// Platform-aware: uses Cmd on macOS, Ctrl on Windows/Linux.

// =============================================================================
// Intent definitions
// =============================================================================

// Navigation
class QuickSwitcherIntent extends Intent {
  const QuickSwitcherIntent();
}

class NavigateBackIntent extends Intent {
  const NavigateBackIntent();
}

class NavigateForwardIntent extends Intent {
  const NavigateForwardIntent();
}

// Room management
class NewRoomIntent extends Intent {
  const NewRoomIntent();
}

class MarkReadIntent extends Intent {
  const MarkReadIntent();
}

// Search
class SearchIntent extends Intent {
  const SearchIntent();
}

class GlobalSearchIntent extends Intent {
  const GlobalSearchIntent();
}

// Settings
class PreferencesIntent extends Intent {
  const PreferencesIntent();
}

// Panels
class ClosePanelIntent extends Intent {
  const ClosePanelIntent();
}

// Voice
class ToggleMuteIntent extends Intent {
  const ToggleMuteIntent();
}

class ToggleDeafenIntent extends Intent {
  const ToggleDeafenIntent();
}

class DisconnectVoiceIntent extends Intent {
  const DisconnectVoiceIntent();
}

// Messaging
class EmojiPickerIntent extends Intent {
  const EmojiPickerIntent();
}

// Help
class ShortcutHelpIntent extends Intent {
  const ShortcutHelpIntent();
}

// Explore
class ExploreIntent extends Intent {
  const ExploreIntent();
}

// =============================================================================
// Shortcut map
// =============================================================================

final gloamShortcuts = <ShortcutActivator, Intent>{
  // --- Navigation ---
  const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
      const QuickSwitcherIntent(),
  const SingleActivator(LogicalKeyboardKey.keyK, control: true):
      const QuickSwitcherIntent(),

  // History navigation — Cmd+[/] on macOS, Alt+Left/Right on Win/Linux
  const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
      const NavigateBackIntent(),
  const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
      const NavigateBackIntent(),
  const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):
      const NavigateForwardIntent(),
  const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
      const NavigateForwardIntent(),

  // --- Room management ---
  const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
      const NewRoomIntent(),
  const SingleActivator(LogicalKeyboardKey.keyN, control: true):
      const NewRoomIntent(),

  // Mark room as read
  const SingleActivator(LogicalKeyboardKey.keyR, meta: true, shift: true):
      const MarkReadIntent(),
  const SingleActivator(LogicalKeyboardKey.keyR, control: true, shift: true):
      const MarkReadIntent(),

  // --- Search ---
  const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
      const SearchIntent(),
  const SingleActivator(LogicalKeyboardKey.keyF, control: true):
      const SearchIntent(),
  const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
      const GlobalSearchIntent(),
  const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
      const GlobalSearchIntent(),

  // --- Settings ---
  const SingleActivator(LogicalKeyboardKey.comma, meta: true):
      const PreferencesIntent(),
  const SingleActivator(LogicalKeyboardKey.comma, control: true):
      const PreferencesIntent(),

  // --- Panel control ---
  const SingleActivator(LogicalKeyboardKey.escape):
      const ClosePanelIntent(),
  const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
      const ClosePanelIntent(),
  const SingleActivator(LogicalKeyboardKey.keyW, control: true):
      const ClosePanelIntent(),

  // --- Voice ---
  const SingleActivator(LogicalKeyboardKey.keyM, meta: true, shift: true):
      const ToggleMuteIntent(),
  const SingleActivator(LogicalKeyboardKey.keyM, control: true, shift: true):
      const ToggleMuteIntent(),
  const SingleActivator(LogicalKeyboardKey.keyD, meta: true, shift: true):
      const ToggleDeafenIntent(),
  const SingleActivator(LogicalKeyboardKey.keyD, control: true, shift: true):
      const ToggleDeafenIntent(),
  const SingleActivator(LogicalKeyboardKey.keyE, meta: true, shift: true):
      const DisconnectVoiceIntent(),
  const SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true):
      const DisconnectVoiceIntent(),

  // --- Messaging ---
  const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
      const EmojiPickerIntent(),
  const SingleActivator(LogicalKeyboardKey.keyE, control: true):
      const EmojiPickerIntent(),

  // --- Explore ---
  const SingleActivator(LogicalKeyboardKey.keyJ, meta: true, shift: true):
      const ExploreIntent(),
  const SingleActivator(LogicalKeyboardKey.keyJ, control: true, shift: true):
      const ExploreIntent(),

  // --- Help ---
  const SingleActivator(LogicalKeyboardKey.slash, meta: true):
      const ShortcutHelpIntent(),
  const SingleActivator(LogicalKeyboardKey.slash, control: true):
      const ShortcutHelpIntent(),
};

// =============================================================================
// Platform-aware help entries
// =============================================================================

/// Whether we're on macOS (use ⌘) or other platforms (use Ctrl).
bool get _isMac => Platform.isMacOS;

String get _mod => _isMac ? '⌘' : 'Ctrl+';
String get _modShift => _isMac ? '⇧⌘' : 'Ctrl+Shift+';
String get _alt => _isMac ? '⌘' : 'Alt+';

List<(String, String, String?)> get shortcutHelpEntries => [
      // (label, keys, category — null continues previous category)
      ('Quick Switcher', '${_mod}K', 'navigation'),
      ('Navigate Back', _isMac ? '⌘[' : 'Alt+←', null),
      ('Navigate Forward', _isMac ? '⌘]' : 'Alt+→', null),
      ('Explore Rooms', '${_modShift}J', null),
      ('New Room', '${_mod}N', 'rooms'),
      ('Mark Room Read', '${_modShift}R', null),
      ('Search in Room', '${_mod}F', 'search'),
      ('Global Search', '${_modShift}F', null),
      ('Emoji Picker', '${_mod}E', 'messaging'),
      ('Toggle Mute', '${_modShift}M', 'voice'),
      ('Toggle Deafen', '${_modShift}D', null),
      ('Disconnect Voice', '${_modShift}E', null),
      ('Preferences', '${_mod},', 'app'),
      ('Close Panel', '${_mod}W / Esc', null),
      ('Show Shortcuts', '${_mod}/', null),
    ];
