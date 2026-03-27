import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';

/// Checks for app updates via Sparkle (macOS) / WinSparkle (Windows).
///
/// Reads an appcast XML feed from GitHub to detect new versions.
/// Only runs on desktop platforms in release mode.
class UpdateService {
  static const _macFeedUrl =
      'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast.xml';
  static const _winFeedUrl =
      'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast_windows.xml';

  /// Initialize and check for updates in the background.
  static Future<void> init() async {
    // Only check for updates on desktop in release mode
    if (kDebugMode) return;
    if (!Platform.isMacOS && !Platform.isWindows) return;

    try {
      final autoUpdater = AutoUpdater.instance;

      final feedUrl = Platform.isMacOS ? _macFeedUrl : _winFeedUrl;
      await autoUpdater.setFeedURL(feedUrl);

      // Check for updates silently on launch
      await autoUpdater.checkForUpdates(inBackground: true);
    } catch (e) {
      debugPrint('[UpdateService] Failed to check for updates: $e');
    }
  }

  /// Manually trigger an update check (e.g., from Settings).
  static Future<void> checkNow() async {
    if (!Platform.isMacOS && !Platform.isWindows) return;

    try {
      await AutoUpdater.instance.checkForUpdates(inBackground: false);
    } catch (e) {
      debugPrint('[UpdateService] Manual check failed: $e');
    }
  }
}
