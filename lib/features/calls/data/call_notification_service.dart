import 'dart:async';

import 'package:matrix/matrix.dart';

/// Handles sending and receiving call notifications (MSC4075).
///
/// Call notifications use to-device messages to ring specific users
/// for DM calls. Unlike voice channels (ambient join), DM calls
/// have a ringing flow: initiate → ring → accept/decline.
class CallNotificationService {
  CallNotificationService({required Client client}) : _client = client;

  final Client _client;
  StreamSubscription? _toDeviceSub;

  final _incomingCalls = StreamController<IncomingCall>.broadcast();

  /// Stream of incoming call notifications.
  Stream<IncomingCall> get incomingCalls => _incomingCalls.stream;

  /// Start listening for incoming call to-device events.
  void start() {
    _toDeviceSub = _client.onToDeviceEvent.stream.listen((event) {
      if (event.type == _callNotifyEventType) {
        final content = event.content;
        final senderId = event.senderId;
        _incomingCalls.add(IncomingCall(
          callId: content['call_id'] as String? ?? '',
          roomId: content['room_id'] as String? ?? '',
          callerId: senderId,
          callerDisplayName:
              content['sender_display_name'] as String? ?? senderId,
          callerAvatarUrl: content['sender_avatar_url'] != null
              ? Uri.tryParse(content['sender_avatar_url'] as String)
              : null,
          isVideo: content['call_type'] == 'm.video',
          receivedAt: DateTime.now(),
        ));
      }
    });
  }

  /// Send a call notification to ring a user.
  Future<void> sendCallNotification({
    required String roomId,
    required String callId,
    required String recipientId,
    required bool isVideo,
  }) async {
    await _client.sendToDevice(
      _callNotifyEventType,
      _client.generateUniqueTransactionId(),
      {
        recipientId: {
          '*': {
            'call_id': callId,
            'room_id': roomId,
            'application': 'm.call',
            'call_type': isVideo ? 'm.video' : 'm.voice',
            'sender_display_name': _client.userID ?? '',
            'sender_avatar_url': null,
          },
        },
      },
    );
  }

  /// Send a decline notification (MSC4310).
  Future<void> sendDeclineNotification({
    required String roomId,
    required String callId,
    required String callerId,
  }) async {
    await _client.sendToDevice(
      _callDeclineEventType,
      _client.generateUniqueTransactionId(),
      {
        callerId: {
          '*': {
            'call_id': callId,
            'room_id': roomId,
          },
        },
      },
    );
  }

  Future<void> dispose() async {
    await _toDeviceSub?.cancel();
    await _incomingCalls.close();
  }

  static const _callNotifyEventType = 'org.matrix.msc4075.call.notify';
  static const _callDeclineEventType = 'org.matrix.msc4310.call.decline';
}

/// An incoming call notification from another user.
class IncomingCall {
  const IncomingCall({
    required this.callId,
    required this.roomId,
    required this.callerId,
    required this.callerDisplayName,
    this.callerAvatarUrl,
    required this.isVideo,
    required this.receivedAt,
  });

  final String callId;
  final String roomId;
  final String callerId;
  final String callerDisplayName;
  final Uri? callerAvatarUrl;
  final bool isVideo;
  final DateTime receivedAt;
}
