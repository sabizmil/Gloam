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

      // Delay the first check to let the app finish loading
      await Future.delayed(const Duration(seconds: 10));

      // Check silently — swallow any errors (first launch, no network, etc.)
      try {
        await autoUpdater.checkForUpdates(inBackground: true);
      } catch (_) {
        // Update check is best-effort — never crash the app for this
      }
    } catch (e) {
      debugPrint('[UpdateService] Failed to init auto-updater: $e');
    }
  }

  /// Manually trigger an update check (e.g., from Settings).
  /// Works in both debug and release mode.
  static Future<void> checkNow() async {
    if (!Platform.isMacOS && !Platform.isWindows) return;

    try {
      final autoUpdater = AutoUpdater.instance;
      final feedUrl = Platform.isMacOS ? _macFeedUrl : _winFeedUrl;
      await autoUpdater.setFeedURL(feedUrl);
      await autoUpdater.checkForUpdates(inBackground: false);
    } catch (e) {
      debugPrint('[UpdateService] Manual check failed: $e');
    }
  }
}
