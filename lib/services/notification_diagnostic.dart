import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

/// Runs a step-by-step diagnostic of the notification pipeline (macOS + iOS).
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
    if (!Platform.isMacOS && !Platform.isIOS) {
      _log('Step 1: SKIP — diagnostic supports macOS and iOS only');
      return results;
    }
    _log('Step 1: PASS — running on ${Platform.isIOS ? "iOS" : "macOS"}');

    // Step 2: Create plugin instance
    final plugin = FlutterLocalNotificationsPlugin();
    _log('Step 2: Plugin instance created');

    // Step 3: Initialize with Darwin settings
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(iOS: darwin, macOS: darwin);
      final initResult = await plugin.initialize(settings: settings);
      _log('Step 3: initialize() returned: $initResult');
    } catch (e) {
      _log('Step 3: FAIL — initialize() threw: $e');
      return results;
    }

    // Step 4: Request permissions explicitly
    try {
      bool? permResult;
      if (Platform.isIOS) {
        final iosImpl = plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        if (iosImpl == null) {
          _log('Step 4: FAIL — could not resolve iOS implementation');
          return results;
        }
        permResult = await iosImpl.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      } else {
        final macImpl = plugin.resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
        if (macImpl == null) {
          _log('Step 4: FAIL — could not resolve macOS implementation');
          return results;
        }
        permResult = await macImpl.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      _log('Step 4: requestPermissions() returned: $permResult');
      if (permResult != true) {
        final settingsPath = Platform.isIOS
            ? 'Settings > Notifications > Gloam'
            : 'System Settings > Notifications > Gloam';
        _log('Step 4: WARNING — permissions not granted. Enable in $settingsPath');
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
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
      );
      await plugin.show(
        id: 99999,
        title: 'Gloam Diagnostic',
        body: 'If you see this, notifications work! Time: ${DateTime.now()}',
        notificationDetails: details,
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

    // Step 8: macOS-only osascript fallback (bypasses UNUserNotificationCenter)
    if (Platform.isMacOS) {
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
    } else {
      _log('Step 8: SKIP — osascript fallback is macOS-only');
    }

    _log('=== NOTIFICATION DIAGNOSTIC END ===');
    if (Platform.isIOS) {
      _log('If Step 6 passed but no notification appeared:');
      _log('  - Check Settings > Notifications > Gloam');
      _log('  - Ensure "Allow Notifications" is ON');
      _log('  - Foreground notifications appear as banners only when defaultPresentBanner is true');
      _log('  - Focus mode may be suppressing notifications');
      _log('  - Re-installing the app resets the permission grant — iOS only prompts on first request');
    } else {
      _log('If Step 6 passed but no notification appeared:');
      _log('  - Check System Settings > Notifications > Gloam');
      _log('  - Ensure "Allow Notifications" is ON');
      _log('  - Ensure "Banners" or "Alerts" is selected (not "None")');
      _log('  - Try: Focus mode may be suppressing notifications');
      _log('  - Try: Close Gloam, re-open, and run diagnostic again');
      _log('  - The app may need to be run via `flutter run` (not `open .app`) for the first permission prompt');
    }

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
