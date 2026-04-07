import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Checks for app updates via Sparkle (macOS) / WinSparkle (Windows).
///
/// Supports two channels:
/// - **Stable**: production releases only
/// - **Beta**: pre-release builds for testing (also receives stable promotions)
class UpdateService {
  static const _macStable =
      'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast.xml';
  static const _macBeta =
      'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast_beta.xml';
  static const _winStable =
      'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast_windows.xml';
  static const _winBeta =
      'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast_windows_beta.xml';

  static const _prefKey = 'update_channel_beta';

  /// Whether the user has opted into the beta channel.
  static Future<bool> isBetaChannel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Set the update channel. Returns immediately; the next update check
  /// will use the new feed.
  static Future<void> setBetaChannel(bool beta) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, beta);
    // Re-point the updater at the new feed
    await _setFeed(beta);
  }

  static Future<void> _setFeed(bool beta) async {
    final autoUpdater = AutoUpdater.instance;
    String feedUrl;
    if (Platform.isMacOS) {
      feedUrl = beta ? _macBeta : _macStable;
    } else {
      feedUrl = beta ? _winBeta : _winStable;
    }
    await autoUpdater.setFeedURL(feedUrl);
  }

  /// Initialize and check for updates in the background.
  static Future<void> init() async {
    if (kDebugMode) return;
    if (!Platform.isMacOS && !Platform.isWindows) return;

    try {
      final beta = await isBetaChannel();
      await _setFeed(beta);

      await Future.delayed(const Duration(seconds: 10));

      try {
        await AutoUpdater.instance.checkForUpdates(inBackground: true);
      } catch (_) {}
    } catch (e) {
      debugPrint('[UpdateService] Failed to init auto-updater: $e');
    }
  }

  /// Manually trigger an update check (e.g., from Settings).
  static Future<void> checkNow() async {
    if (!Platform.isMacOS && !Platform.isWindows) return;

    try {
      final beta = await isBetaChannel();
      await _setFeed(beta);
      await AutoUpdater.instance.checkForUpdates(inBackground: false);
    } catch (e) {
      debugPrint('[UpdateService] Manual check failed: $e');
    }
  }
}
