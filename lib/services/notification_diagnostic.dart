import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

/// Runs a step-by-step diagnostic of the macOS notification pipeline.
/// Writes results to both the logger and a file for easy retrieval.
class NotificationDiagnostic {
  static final _lines = <String>[];

  static void _log(String msg) {
    _lines.add(msg);
    Logs().w(msg);
  }

  /// Get the results of the last diagnostic run.
  static String get results => _lines.join('\n');

  static Future<String> run() async {
    _lines.clear();
    _log('=== NOTIFICATION DIAGNOSTIC START ===');

    // Step 1: Platform check
    _log('Step 1: Platform = ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    if (!Platform.isMacOS) {
      _log('Step 1: SKIP — not macOS');
      return results;
    }
    _log('Step 1: PASS — running on macOS');

    // Step 2: Create plugin instance
    final plugin = FlutterLocalNotificationsPlugin();
    _log('Step 2: Plugin instance created');

    // Step 3: Initialize with macOS settings
    try {
      const macOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(macOS: macOS);
      final initResult = await plugin.initialize(settings);
      _log('Step 3: initialize() returned: $initResult');
    } catch (e) {
      _log('Step 3: FAIL — initialize() threw: $e');
      return results;
    }

    // Step 4: Request permissions explicitly
    try {
      final macImpl = plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      if (macImpl == null) {
        _log('Step 4: FAIL — could not resolve macOS implementation');
        return results;
      }
      final permResult = await macImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      _log('Step 4: requestPermissions() returned: $permResult');
      if (permResult != true) {
        _log('Step 4: WARNING — permissions not granted. User may need to enable in System Settings > Notifications > Gloam');
      }
    } catch (e) {
      _log('Step 4: FAIL — requestPermissions() threw: $e');
    }

    // Step 5: Check pending notifications (verifies plugin is connected)
    try {
      final pending = await plugin.pendingNotificationRequests();
      _log('Step 5: ${pending.length} pending notification requests');
    } catch (e) {
      _log('Step 5: FAIL — pendingNotificationRequests() threw: $e');
    }

    // Step 6: Show a notification with all presentation flags
    try {
      const details = NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
      );
      await plugin.show(
        99999,
        'Gloam Diagnostic',
        'If you see this, notifications work! Time: ${DateTime.now()}',
        details,
      );
      _log('Step 6: plugin.show() completed without error');
    } catch (e) {
      _log('Step 6: FAIL — plugin.show() threw: $e');
      return results;
    }

    // Step 7: Check if the notification was actually scheduled
    try {
      final pending = await plugin.pendingNotificationRequests();
      final found = pending.any((p) => p.id == 99999);
      _log('Step 7: Notification 99999 in pending list: $found');
      _log('Step 7: Total pending: ${pending.length}');
    } catch (e) {
      _log('Step 7: pendingNotificationRequests() threw: $e');
    }

    // Step 8: Try osascript notification (bypasses UNUserNotificationCenter entirely)
    try {
      final result = await Process.run('osascript', [
        '-e',
        'display notification "If you see this, osascript works but UNNotification does not" with title "Gloam (osascript)"',
      ]);
      _log('Step 8: osascript exit code: ${result.exitCode}');
      _log('Step 8: osascript stderr: ${result.stderr}');
      if (result.exitCode == 0) {
        _log('Step 8: If you see "Gloam (osascript)" → OS notifications work, UNNotification framework is broken');
        _log('Step 8: If nothing → sandbox is blocking osascript too');
      }
    } catch (e) {
      _log('Step 8: osascript failed: $e');
    }

    _log('=== NOTIFICATION DIAGNOSTIC END ===');
    _log('If Step 6 passed but no notification appeared:');
    _log('  - Check System Settings > Notifications > Gloam');
    _log('  - Ensure "Allow Notifications" is ON');
    _log('  - Ensure "Banners" or "Alerts" is selected (not "None")');
    _log('  - Try: Focus mode may be suppressing notifications');
    _log('  - Try: Close Gloam, re-open, and run diagnostic again');
    _log('  - The app may need to be run via `flutter run` (not `open .app`) for the first permission prompt');

    // Save to file for easy retrieval
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/notification_diagnostic.txt');
      await file.writeAsString(results);
      _log('Results saved to: ${file.path}');
    } catch (_) {}

    return results;
  }
}
