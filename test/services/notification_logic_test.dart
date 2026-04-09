import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:mocktail/mocktail.dart';

class MockRoom extends Mock implements Room {}

class MockEvent extends Mock implements Event {}

/// Tests for the notification decision logic used in NotificationService.
///
/// Rules:
/// - Never notify for active room when foreground
/// - Never notify for own messages
/// - Never notify for muted rooms
/// - Foreground + other room: only DMs and mentions break through
/// - Background: all non-muted rooms with unreads notify
/// - Invites always notify
void main() {
  group('Notification decision logic', () {
    /// Mirrors the decision logic in NotificationService._checkForNotifications()
    /// Returns true if a notification should be shown.
    bool shouldNotify({
      required bool appInForeground,
      required String? activeRoomId,
      required String roomId,
      required PushRuleState pushRule,
      required bool isDirect,
      required int highlightCount,
      required String senderId,
      required String myUserId,
    }) {
      // Own messages — skip
      if (senderId == myUserId) return false;

      // Muted — skip
      if (pushRule == PushRuleState.dontNotify) return false;

      bool isMention = highlightCount > 0;

      if (appInForeground) {
        // Active room — never notify
        if (roomId == activeRoomId) return false;

        if (pushRule == PushRuleState.notify) {
          // "All messages" — only DMs break through in foreground
          return isDirect;
        } else {
          // "Mentions only" — only when mentioned
          return isMention;
        }
      } else {
        // Background
        if (pushRule == PushRuleState.notify) {
          return true;
        } else {
          return isMention;
        }
      }
    }

    test('own messages never notify', () {
      expect(
        shouldNotify(
          appInForeground: false,
          activeRoomId: null,
          roomId: '!room:example.com',
          pushRule: PushRuleState.notify,
          isDirect: true,
          highlightCount: 0,
          senderId: '@me:example.com',
          myUserId: '@me:example.com',
        ),
        false,
      );
    });

    test('muted rooms never notify', () {
      expect(
        shouldNotify(
          appInForeground: false,
          activeRoomId: null,
          roomId: '!room:example.com',
          pushRule: PushRuleState.dontNotify,
          isDirect: true,
          highlightCount: 5,
          senderId: '@other:example.com',
          myUserId: '@me:example.com',
        ),
        false,
      );
    });

    test('foreground + active room never notifies', () {
      expect(
        shouldNotify(
          appInForeground: true,
          activeRoomId: '!room:example.com',
          roomId: '!room:example.com',
          pushRule: PushRuleState.notify,
          isDirect: true,
          highlightCount: 0,
          senderId: '@other:example.com',
          myUserId: '@me:example.com',
        ),
        false,
      );
    });

    test('foreground + DM in other room notifies', () {
      expect(
        shouldNotify(
          appInForeground: true,
          activeRoomId: '!other:example.com',
          roomId: '!dm:example.com',
          pushRule: PushRuleState.notify,
          isDirect: true,
          highlightCount: 0,
          senderId: '@friend:example.com',
          myUserId: '@me:example.com',
        ),
        true,
      );
    });

    test('foreground + channel message does NOT notify', () {
      expect(
        shouldNotify(
          appInForeground: true,
          activeRoomId: '!other:example.com',
          roomId: '!channel:example.com',
          pushRule: PushRuleState.notify,
          isDirect: false,
          highlightCount: 0,
          senderId: '@coworker:example.com',
          myUserId: '@me:example.com',
        ),
        false,
      );
    });

    test('foreground + channel mention notifies', () {
      expect(
        shouldNotify(
          appInForeground: true,
          activeRoomId: '!other:example.com',
          roomId: '!channel:example.com',
          pushRule: PushRuleState.mentionsOnly,
          isDirect: false,
          highlightCount: 1,
          senderId: '@coworker:example.com',
          myUserId: '@me:example.com',
        ),
        true,
      );
    });

    test('background + channel message with notify rule notifies', () {
      expect(
        shouldNotify(
          appInForeground: false,
          activeRoomId: null,
          roomId: '!channel:example.com',
          pushRule: PushRuleState.notify,
          isDirect: false,
          highlightCount: 0,
          senderId: '@coworker:example.com',
          myUserId: '@me:example.com',
        ),
        true,
      );
    });

    test('background + mentionsOnly without mention does NOT notify', () {
      expect(
        shouldNotify(
          appInForeground: false,
          activeRoomId: null,
          roomId: '!channel:example.com',
          pushRule: PushRuleState.mentionsOnly,
          isDirect: false,
          highlightCount: 0,
          senderId: '@coworker:example.com',
          myUserId: '@me:example.com',
        ),
        false,
      );
    });

    test('background + mentionsOnly with mention notifies', () {
      expect(
        shouldNotify(
          appInForeground: false,
          activeRoomId: null,
          roomId: '!channel:example.com',
          pushRule: PushRuleState.mentionsOnly,
          isDirect: false,
          highlightCount: 2,
          senderId: '@coworker:example.com',
          myUserId: '@me:example.com',
        ),
        true,
      );
    });
  });
}
