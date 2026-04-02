import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

/// Desktop notification service — fires local notifications based on
/// app focus state, per-room push rules, and message context.
///
/// Rules:
/// - Never notify for the active room when app is in foreground
/// - Never notify for own messages (sent from another device)
/// - Never notify for muted rooms (PushRuleState.dontNotify)
/// - Foreground + other room: only DMs and mentions break through
/// - Background: all non-muted rooms with unreads notify
/// - Mentions play sound, regular messages don't
/// - Invites always notify
class NotificationService with WidgetsBindingObserver {
  final Client client;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  StreamSubscription? _sub;
  String? _activeRoomId;
  bool _appInForeground = true;
  final _notifiedEventIds = <String>{};
  final _notifiedInviteIds = <String>{};

  /// Called when the user taps a notification. Payload is the room ID.
  final void Function(String roomId)? onSelectRoom;

  NotificationService(this.client, {this.onSelectRoom});

  Future<void> initialize() async {
    const initMacOS = DarwinInitializationSettings();
    const initLinux =
        LinuxInitializationSettings(defaultActionName: 'Open');
    const initWindows = WindowsInitializationSettings(
      appName: 'Gloam',
      appUserModelId: 'chat.gloam.gloam',
      guid: 'd3b5b5e0-8c9a-4e7f-b5d1-a2c3e4f5a6b7',
    );
    const initSettings = InitializationSettings(
      macOS: initMacOS,
      linux: initLinux,
      windows: initWindows,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    final roomId = response.payload;
    if (roomId != null && roomId.isNotEmpty) {
      onSelectRoom?.call(roomId);
    }
  }

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _sub = client.onSync.stream.listen((_) => _checkForNotifications());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
  }

  /// Set the currently viewed room — suppress notifications for this room.
  void setActiveRoom(String? roomId) {
    _activeRoomId = roomId;
  }

  void _checkForNotifications() {
    // --- Invites (always notify) ---
    for (final room in client.rooms) {
      if (room.membership != Membership.invite) continue;
      if (_notifiedInviteIds.contains(room.id)) continue;
      _notifiedInviteIds.add(room.id);

      final inviteEvent =
          room.getState(EventTypes.RoomMember, client.userID!);
      final inviterName = inviteEvent?.senderId ?? 'Someone';
      final roomName = room.getLocalizedDisplayname();

      _showNotification(
        room: room,
        sender: inviterName,
        body: 'invited you to $roomName',
        isMention: true, // invites always play sound
      );
    }

    // --- Messages ---
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      if (room.notificationCount == 0 && room.highlightCount == 0) continue;

      final lastEvent = room.lastEvent;
      if (lastEvent == null) continue;

      // Own messages — skip
      if (lastEvent.senderId == client.userID) continue;

      // Dedup — skip if already notified
      if (_notifiedEventIds.contains(lastEvent.eventId)) continue;

      // Recency gate — only recent events
      if (lastEvent.originServerTs
          .isBefore(DateTime.now().subtract(const Duration(seconds: 15)))) {
        continue;
      }

      // Per-room push rule
      final pushRule = room.pushRuleState;
      if (pushRule == PushRuleState.dontNotify) continue;

      bool shouldNotify = false;
      bool isMention = room.highlightCount > 0;

      if (_appInForeground) {
        // Active room — never notify
        if (room.id == _activeRoomId) continue;

        if (pushRule == PushRuleState.notify) {
          // "All messages" — only DMs break through in foreground
          shouldNotify = room.isDirectChat;
        } else {
          // "Mentions only" — only when mentioned
          shouldNotify = isMention;
        }
      } else {
        // Background — notify based on push rule
        if (pushRule == PushRuleState.notify) {
          shouldNotify = true;
        } else {
          // mentionsOnly — only when mentioned
          shouldNotify = isMention;
        }
      }

      if (shouldNotify) {
        _notifiedEventIds.add(lastEvent.eventId);
        _showNotification(
          room: room,
          sender: lastEvent.senderFromMemoryOrFallback.calcDisplayname(),
          body: lastEvent.body,
          isMention: isMention,
        );

        // Cap dedup set to prevent unbounded growth
        if (_notifiedEventIds.length > 500) {
          final list = _notifiedEventIds.toList();
          _notifiedEventIds.clear();
          _notifiedEventIds.addAll(list.skip(list.length - 200));
        }
      }
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
      const initWindows = WindowsInitializationSettings(
        appName: 'Gloam',
        appUserModelId: 'chat.gloam.gloam',
        guid: 'd3b5b5e0-8c9a-4e7f-b5d1-a2c3e4f5a6b7',
      );
      const initSettings = InitializationSettings(
        macOS: initMacOS,
        linux: initLinux,
        windows: initWindows,
      );
      await plugin.initialize(settings: initSettings);
      await plugin.show(
        id: 0,
        title: 'Gloam',
        body: 'Notifications are working.',
        notificationDetails: const NotificationDetails(
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBanner: true,
            presentList: true,
          ),
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
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
    bool isMention = false,
  }) async {
    if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) return;

    final roomName = room.getLocalizedDisplayname();
    final title = room.isDirectChat ? sender : '$sender in $roomName';

    await _plugin.show(
      id: room.id.hashCode,
      title: title,
      body: body,
      payload: room.id, // Passed to onDidReceiveNotificationResponse
      notificationDetails: NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: isMention,
          presentBanner: true,
          presentList: true,
        ),
        linux: const LinuxNotificationDetails(),
        windows: const WindowsNotificationDetails(),
      ),
    );
  }
}
