import 'dart:io';

import 'package:flutter/services.dart';

/// Thin wrapper over the `chat.gloam/platform` method channel for native-only
/// capabilities: badge count (macOS dock / iOS icon) + window focus on click.
class PlatformService {
  PlatformService._();
  static final PlatformService instance = PlatformService._();

  static const _channel = MethodChannel('chat.gloam/platform');

  /// Bring the app window to the foreground. No-op on iOS (the OS handles
  /// notification-tap routing automatically) and on platforms without a
  /// handler registered.
  Future<void> focusWindow() async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('focusWindow');
    } catch (_) {}
  }

  /// iOS-only: fire a notification via `UNUserNotificationCenter` directly,
  /// bypassing flutter_local_notifications. Isolates plugin failures from
  /// iOS-level configuration issues. Returns `null` on success or an error
  /// string.
  Future<String?> fireNativeNotification({
    required String title,
    required String body,
  }) async {
    if (!Platform.isIOS) return 'unsupported on ${Platform.operatingSystem}';
    try {
      await _channel.invokeMethod<void>('fireNativeNotification', {
        'title': title,
        'body': body,
      });
      return null;
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }

  /// iOS-only: reads raw `UNUserNotificationCenter.getNotificationSettings`.
  /// Distinguishes `notDetermined` (prompt never fired) from `denied`.
  Future<Map<String, dynamic>?> notificationAuthStatus() async {
    if (!Platform.isIOS) return null;
    try {
      return await _channel
          .invokeMapMethod<String, dynamic>('notificationAuthStatus');
    } catch (_) {
      return null;
    }
  }

  /// Set the app badge count.
  ///   - macOS: shows `count`/`99+` as the dock tile label (clears at 0)
  ///   - iOS: sets the home-screen icon badge to the numeric count
  ///   - Windows: BadgeService uses WindowsTaskbar overlay icons instead
  ///     (this method's Windows handler is a no-op)
  Future<void> setBadge(int count) async {
    if (!Platform.isMacOS && !Platform.isIOS) return;
    final label = count <= 0
        ? null
        : count > 99
            ? '99+'
            : count.toString();
    try {
      await _channel.invokeMethod<void>('setBadge', {
        'count': count,
        'label': label,
      });
    } catch (_) {}
  }
}
