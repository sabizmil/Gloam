import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

/// Desktop notification service — fires local notifications for new messages
/// when the app is in the background or a different room is focused.
class NotificationService {
  final Client client;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  StreamSubscription? _sub;
  String? _activeRoomId;

  NotificationService(this.client);

  Future<void> initialize() async {
    const initMacOS = DarwinInitializationSettings();
    const initLinux =
        LinuxInitializationSettings(defaultActionName: 'Open');
    const initSettings = InitializationSettings(
      macOS: initMacOS,
      linux: initLinux,
    );

    await _plugin.initialize(initSettings);

    if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  void start() {
    _sub = client.onSync.stream.listen((_) => _checkForNotifications());
  }

  void dispose() {
    _sub?.cancel();
  }

  /// Set the currently viewed room — suppress notifications for this room.
  void setActiveRoom(String? roomId) {
    _activeRoomId = roomId;
  }

  void _checkForNotifications() {
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      if (room.id == _activeRoomId) continue;
      if (room.notificationCount == 0) continue;

      final lastEvent = room.lastEvent;
      if (lastEvent == null) continue;
      if (lastEvent.originServerTs
          .isBefore(DateTime.now().subtract(const Duration(seconds: 10)))) {
        continue; // Only notify for recent messages
      }

      // Don't re-notify for events we've already shown
      // (Simple dedup: only notify if the event is newer than 10 seconds)
      _showNotification(
        room: room,
        sender: lastEvent.senderFromMemoryOrFallback.calcDisplayname(),
        body: lastEvent.body,
      );
    }
  }

  /// Fire a single test notification to verify system configuration.
  static Future<bool> sendTestNotification() async {
    if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) {
      return false;
    }
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      const initMacOS = DarwinInitializationSettings();
      const initLinux =
          LinuxInitializationSettings(defaultActionName: 'Open');
      const initSettings = InitializationSettings(
        macOS: initMacOS,
        linux: initLinux,
      );
      await plugin.initialize(initSettings);
      await plugin.show(
        0,
        'Gloam',
        'Notifications are working.',
        const NotificationDetails(
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBanner: true,
            presentList: true,
          ),
          linux: LinuxNotificationDetails(),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showNotification({
    required Room room,
    required String sender,
    required String body,
  }) async {
    // Only show on desktop platforms
    if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) return;

    final roomName = room.getLocalizedDisplayname();
    final title = room.isDirectChat ? sender : '$sender in $roomName';

    await _plugin.show(
      room.id.hashCode,
      title,
      body,
      const NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
        linux: LinuxNotificationDetails(),
      ),
    );
  }
}
