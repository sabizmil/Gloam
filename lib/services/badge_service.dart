import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import 'platform_service.dart';

/// Updates the app icon badge (macOS dock / Windows taskbar overlay)
/// based on aggregated unread counts across all rooms.
///
/// Follows Slack's model:
/// - DMs and mentions show a number
/// - Channel-only unreads don't contribute to the badge number
/// - Muted rooms are excluded
class BadgeService with WidgetsBindingObserver {
  final Client client;
  StreamSubscription? _syncSub;
  int _lastBadge = -1;

  BadgeService(this.client);

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _syncSub = client.onSync.stream.listen((_) => _update());
    _update();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncSub?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _update();
    }
  }

  void _update() {
    int badgeCount = 0;

    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      if (room.pushRuleState == PushRuleState.dontNotify) continue;

      final mentions = room.highlightCount;
      final unreads = room.notificationCount;

      badgeCount += mentions;
      if (room.isDirectChat && unreads > mentions) {
        badgeCount += unreads - mentions;
      }
    }

    if (badgeCount == _lastBadge) return;
    _lastBadge = badgeCount;
    _applyBadge(badgeCount);
  }

  Future<void> _applyBadge(int count) async {
    if (Platform.isMacOS) {
      await _applyMacOsBadge(count);
    } else if (Platform.isWindows) {
      await _applyWindowsBadge(count);
    }
  }

  Future<void> _applyMacOsBadge(int count) async {
    // Native method channel sets `NSApp.dockTile.badgeLabel` directly —
    // phantom-notification approach was unreliable on recent macOS versions.
    final label = count <= 0
        ? null
        : count > 99
            ? '99+'
            : count.toString();
    await PlatformService.instance.setMacDockBadge(label);
  }

  Future<void> _applyWindowsBadge(int count) async {
    try {
      if (count > 0) {
        final iconName = count > 9 ? '9plus' : '$count';
        await WindowsTaskbar.setOverlayIcon(
          ThumbnailToolbarAssetIcon('assets/badges/$iconName.ico'),
          tooltip: '$count unread',
        );
      } else {
        await WindowsTaskbar.resetOverlayIcon();
      }
    } catch (_) {}
  }
}
