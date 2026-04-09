import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:mocktail/mocktail.dart';

class MockClient extends Mock implements Client {}

class MockRoom extends Mock implements Room {}

/// Tests for the badge count calculation logic used in BadgeService.
///
/// The badge count follows Slack's model:
/// - DMs and mentions show a number
/// - Channel-only unreads don't contribute
/// - Muted rooms are excluded
void main() {
  group('Badge count calculation', () {
    /// Mirrors the logic in BadgeService._update()
    int calculateBadgeCount(List<Room> rooms) {
      int badgeCount = 0;
      for (final room in rooms) {
        if (room.membership != Membership.join) continue;
        if (room.pushRuleState == PushRuleState.dontNotify) continue;

        final mentions = room.highlightCount;
        final unreads = room.notificationCount;

        badgeCount += mentions;
        if (room.isDirectChat && unreads > mentions) {
          badgeCount += unreads - mentions;
        }
      }
      return badgeCount;
    }

    MockRoom createRoom({
      Membership membership = Membership.join,
      PushRuleState pushRule = PushRuleState.notify,
      bool isDirect = false,
      int notifications = 0,
      int highlights = 0,
    }) {
      final room = MockRoom();
      when(() => room.membership).thenReturn(membership);
      when(() => room.pushRuleState).thenReturn(pushRule);
      when(() => room.isDirectChat).thenReturn(isDirect);
      when(() => room.notificationCount).thenReturn(notifications);
      when(() => room.highlightCount).thenReturn(highlights);
      return room;
    }

    test('empty rooms list returns 0', () {
      expect(calculateBadgeCount([]), 0);
    });

    test('DM with unreads contributes to badge', () {
      final rooms = [
        createRoom(isDirect: true, notifications: 3),
      ];
      expect(calculateBadgeCount(rooms), 3);
    });

    test('channel unreads without mentions do NOT contribute', () {
      final rooms = [
        createRoom(isDirect: false, notifications: 5, highlights: 0),
      ];
      expect(calculateBadgeCount(rooms), 0);
    });

    test('channel with mentions contributes only mention count', () {
      final rooms = [
        createRoom(isDirect: false, notifications: 5, highlights: 2),
      ];
      expect(calculateBadgeCount(rooms), 2);
    });

    test('muted rooms are excluded', () {
      final rooms = [
        createRoom(
          isDirect: true,
          notifications: 10,
          pushRule: PushRuleState.dontNotify,
        ),
      ];
      expect(calculateBadgeCount(rooms), 0);
    });

    test('non-joined rooms are excluded', () {
      final rooms = [
        createRoom(
          membership: Membership.invite,
          isDirect: true,
          notifications: 3,
        ),
      ];
      expect(calculateBadgeCount(rooms), 0);
    });

    test('DM with mentions counts both mentions and remaining unreads', () {
      // 5 notifications, 2 are mentions → badge = 2 (mentions) + 3 (DM unreads) = 5
      final rooms = [
        createRoom(isDirect: true, notifications: 5, highlights: 2),
      ];
      expect(calculateBadgeCount(rooms), 5);
    });

    test('mixed rooms sum correctly', () {
      final rooms = [
        // DM: 3 unreads → +3
        createRoom(isDirect: true, notifications: 3),
        // Channel with 2 mentions → +2
        createRoom(isDirect: false, notifications: 10, highlights: 2),
        // Muted DM → +0
        createRoom(
          isDirect: true,
          notifications: 5,
          pushRule: PushRuleState.dontNotify,
        ),
        // Channel, no mentions → +0
        createRoom(isDirect: false, notifications: 7),
        // Invited room → +0
        createRoom(membership: Membership.invite, notifications: 1),
      ];
      expect(calculateBadgeCount(rooms), 5);
    });
  });
}
