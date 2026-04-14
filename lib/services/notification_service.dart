import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

import 'platform_service.dart';

/// Desktop notification service — fires local notifications based on
/// app focus state, per-room push rules, and message context.
///
/// Rules:
/// - Never notify for the active room when app is in foreground
/// - Never notify for own messages (sent from another device)
/// - Never notify for muted rooms (PushRuleState.dontNotify)
/// - Foreground + other room: only DMs and mentions break through
/// - Background: all non-muted rooms with unreads notify
/// - Sound controlled by NotificationSoundPrefs (global + per-room)
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

  /// Resolves the effective sound for a room. Set by the app shell.
  String? Function(String roomId)? resolveSoundForRoom;

  NotificationService(this.client, {this.onSelectRoom});

  Future<void> initialize() async {
    const initDarwin = DarwinInitializationSettings();
    const initLinux =
        LinuxInitializationSettings(defaultActionName: 'Open');
    const initWindows = WindowsInitializationSettings(
      appName: 'Gloam',
      appUserModelId: 'chat.gloam.gloam',
      guid: 'd3b5b5e0-8c9a-4e7f-b5d1-a2c3e4f5a6b7',
    );
    const initSettings = InitializationSettings(
      iOS: initDarwin,
      macOS: initDarwin,
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
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Bring the window forward first — on Windows the click callback arrives
    // while the window is still behind or minimized; on macOS the app may be
    // backgrounded. Focus before navigating so the user actually sees the room.
    PlatformService.instance.focusWindow();

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
  /// If [soundName] is provided, plays that sound alongside the notification.
  static Future<bool> sendTestNotification({String? soundName}) async {
    if (!Platform.isMacOS &&
        !Platform.isLinux &&
        !Platform.isWindows &&
        !Platform.isIOS) {
      return false;
    }
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      const initDarwin = DarwinInitializationSettings();
      const initLinux =
          LinuxInitializationSettings(defaultActionName: 'Open');
      const initWindows = WindowsInitializationSettings(
        appName: 'Gloam',
        appUserModelId: 'chat.gloam.gloam',
        guid: 'd3b5b5e0-8c9a-4e7f-b5d1-a2c3e4f5a6b7',
      );
      const initSettings = InitializationSettings(
        iOS: initDarwin,
        macOS: initDarwin,
        linux: initLinux,
        windows: initWindows,
      );
      await plugin.initialize(settings: initSettings);

      // Play sound via audioplayers (independent of native notification)
      if (soundName != null && soundName != 'silent') {
        _playSound(soundName);
      }

      await plugin.show(
        id: 0,
        title: 'Gloam',
        body: 'Notifications are working.',
        notificationDetails: NotificationDetails(
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: false,
            presentBanner: true,
            presentList: true,
            interruptionLevel: InterruptionLevel.active,
          ),
          macOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: false,
            presentBanner: true,
            presentList: true,
            interruptionLevel: InterruptionLevel.active,
          ),
          linux: const LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(
            audio: WindowsNotificationAudio.silent(),
          ),
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
    if (!Platform.isMacOS &&
        !Platform.isLinux &&
        !Platform.isWindows &&
        !Platform.isIOS) {
      return;
    }

    final roomName = room.getLocalizedDisplayname();
    final title = room.isDirectChat ? sender : '$sender in $roomName';

    // Resolve and play sound via audioplayers
    final soundName = resolveSoundForRoom?.call(room.id);
    if (soundName != null && soundName != 'silent') {
      _playSound(soundName);
    }

    await _plugin.show(
      id: room.id.hashCode,
      title: title,
      body: body,
      payload: room.id,
      notificationDetails: NotificationDetails(
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false, // sound played via audioplayers
          presentBanner: true,
          presentList: true,
          interruptionLevel: InterruptionLevel.active,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false, // sound played via audioplayers
          presentBanner: true,
          presentList: true,
          interruptionLevel: InterruptionLevel.active,
        ),
        linux: const LinuxNotificationDetails(),
        windows: WindowsNotificationDetails(
          audio: WindowsNotificationAudio.silent(), // sound played via audioplayers
        ),
      ),
    );
  }

  /// Play a notification sound via audioplayers.
  static void _playSound(String soundName) {
    final player = AudioPlayer();
    if (soundName.contains('/') || soundName.contains('\\')) {
      // Custom sound — play from file path
      player.play(DeviceFileSource(soundName)).then((_) {
        player.onPlayerComplete.first.then((_) => player.dispose());
      }).catchError((_) => player.dispose());
    } else {
      // Built-in sound — play from assets
      player.play(AssetSource('sounds/$soundName.wav')).then((_) {
        player.onPlayerComplete.first.then((_) => player.dispose());
      }).catchError((_) => player.dispose());
    }
  }
}
