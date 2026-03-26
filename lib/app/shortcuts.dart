import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global keyboard shortcut definitions for Gloam.
/// Platform-aware: uses Cmd on macOS, Ctrl on Windows/Linux.

// Intent definitions
class NewRoomIntent extends Intent {
  const NewRoomIntent();
}

class QuickSwitcherIntent extends Intent {
  const QuickSwitcherIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class GlobalSearchIntent extends Intent {
  const GlobalSearchIntent();
}

class PreferencesIntent extends Intent {
  const PreferencesIntent();
}

class NavigateBackIntent extends Intent {
  const NavigateBackIntent();
}

class NavigateForwardIntent extends Intent {
  const NavigateForwardIntent();
}

class ClosePanelIntent extends Intent {
  const ClosePanelIntent();
}

class ShortcutHelpIntent extends Intent {
  const ShortcutHelpIntent();
}

/// All keyboard shortcuts for the app. Maps intents to key combinations.
final gloamShortcuts = <ShortcutActivator, Intent>{
  // Navigation
  const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
      const QuickSwitcherIntent(),
  const SingleActivator(LogicalKeyboardKey.keyK, control: true):
      const QuickSwitcherIntent(),

  // Room management
  const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
      const NewRoomIntent(),
  const SingleActivator(LogicalKeyboardKey.keyN, control: true):
      const NewRoomIntent(),

  // Search
  const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
      const SearchIntent(),
  const SingleActivator(LogicalKeyboardKey.keyF, control: true):
      const SearchIntent(),
  const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
      const GlobalSearchIntent(),
  const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
      const GlobalSearchIntent(),

  // Settings
  const SingleActivator(LogicalKeyboardKey.comma, meta: true):
      const PreferencesIntent(),

  // Panel control
  const SingleActivator(LogicalKeyboardKey.escape):
      const ClosePanelIntent(),
  const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
      const ClosePanelIntent(),
  const SingleActivator(LogicalKeyboardKey.keyW, control: true):
      const ClosePanelIntent(),

  // History navigation
  const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
      const NavigateBackIntent(),
  const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):
      const NavigateForwardIntent(),

  // Help
  const SingleActivator(LogicalKeyboardKey.slash, meta: true):
      const ShortcutHelpIntent(),
  const SingleActivator(LogicalKeyboardKey.slash, control: true):
      const ShortcutHelpIntent(),
};

/// Shortcut help data for the overlay.
const shortcutHelpEntries = [
  ('Quick Switcher', '⌘K'),
  ('New Room', '⌘N'),
  ('Search in Room', '⌘F'),
  ('Global Search', '⇧⌘F'),
  ('Preferences', '⌘,'),
  ('Close Panel', '⌘W / Esc'),
  ('Navigate Back', '⌘['),
  ('Navigate Forward', '⌘]'),
  ('Show Shortcuts', '⌘/'),
];
