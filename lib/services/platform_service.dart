import 'dart:io';

import 'package:flutter/services.dart';

/// Thin wrapper over the `chat.gloam/platform` method channel for native-only
/// capabilities: macOS dock badge label + window focus on click.
class PlatformService {
  PlatformService._();
  static final PlatformService instance = PlatformService._();

  static const _channel = MethodChannel('chat.gloam/platform');

  /// Bring the app window to the foreground. Safe to call on any platform;
  /// no-op on platforms where the channel isn't implemented.
  Future<void> focusWindow() async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('focusWindow');
    } catch (_) {
      // Channel not registered (e.g. tests) — silently ignore.
    }
  }

  /// Set the macOS dock badge label. Pass null (or empty) to clear.
  /// No-op on non-macOS platforms — Windows badging uses WindowsTaskbar
  /// overlay icons which live in [BadgeService].
  Future<void> setMacDockBadge(String? label) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('setBadge', {'label': label});
    } catch (_) {}
  }
}
