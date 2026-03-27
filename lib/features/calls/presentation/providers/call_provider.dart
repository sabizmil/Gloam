import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:matrix/matrix.dart';

import '../../../../services/matrix_service.dart';
import '../../../../services/voice_service.dart';
import '../../data/adapters/matrix_rtc_adapter.dart';
import '../../data/call_notification_service.dart';

part 'call_provider.freezed.dart';

/// Manages the DM call lifecycle — ringing, connecting, active, ended.
///
/// Separate from [VoiceService] because DM calls use a ringing model
/// (ring → accept/decline) while voice channels use ambient join.
/// Both share the same underlying [VoiceProtocolAdapter].
class CallService extends StateNotifier<CallState> {
  CallService({
    required this.ref,
    required Client client,
  })  : _client = client,
        _notificationService = CallNotificationService(client: client),
        super(const CallState.idle()) {
    _notificationService.start();
    _incomingCallSub = _notificationService.incomingCalls.listen(_onIncomingCall);
  }

  final Ref ref;
  final Client _client;
  final CallNotificationService _notificationService;
  StreamSubscription? _incomingCallSub;
  Timer? _ringTimeout;
  DateTime? _callStartTime;

  /// Start an outgoing call to a DM.
  Future<void> startCall({
    required String roomId,
    required bool isVideo,
  }) async {
    if (state is! CallStateIdle) return;

    final callId = '${_client.deviceID}_${DateTime.now().millisecondsSinceEpoch}';
    final room = _client.getRoomById(roomId);
    if (room == null) return;

    // Find the other user in the DM
    final recipientId = room.directChatMatrixID;
    if (recipientId == null) return;

    final recipient = room.unsafeGetUserFromMemoryOrFallback(recipientId);

    state = CallState.ringingOutgoing(
      callId: callId,
      roomId: roomId,
      isVideo: isVideo,
      peer: CallPeerInfo(
        userId: recipientId,
        displayName: recipient.calcDisplayname(),
        avatarUrl: recipient.avatarUrl,
      ),
    );

    // Send notification to ring the recipient
    await _notificationService.sendCallNotification(
      roomId: roomId,
      callId: callId,
      recipientId: recipientId,
      isVideo: isVideo,
    );

    // Join the MatrixRTC session so media is ready when they answer
    final adapter = MatrixRTCAdapter(client: _client);
    await ref.read(voiceServiceProvider.notifier).joinChannel(
          adapter: adapter,
          channelId: roomId,
        );

    // Ring timeout: 45 seconds
    _ringTimeout = Timer(const Duration(seconds: 45), () {
      if (state is CallStateRingingOutgoing) {
        endCall(reason: CallEndReason.noAnswer);
      }
    });
  }

  /// Handle an incoming call notification.
  void _onIncomingCall(IncomingCall call) {
    if (state is! CallStateIdle) return; // Already in a call

    state = CallState.ringingIncoming(
      callId: call.callId,
      roomId: call.roomId,
      isVideo: call.isVideo,
      caller: CallPeerInfo(
        userId: call.callerId,
        displayName: call.callerDisplayName,
        avatarUrl: call.callerAvatarUrl,
      ),
    );
  }

  /// Accept an incoming call.
  Future<void> acceptCall() async {
    final incoming = state;
    if (incoming is! CallStateRingingIncoming) return;

    state = CallState.connecting(
      callId: incoming.callId,
      roomId: incoming.roomId,
    );

    // Join the MatrixRTC session
    final adapter = MatrixRTCAdapter(client: _client);
    await ref.read(voiceServiceProvider.notifier).joinChannel(
          adapter: adapter,
          channelId: incoming.roomId,
        );

    _callStartTime = DateTime.now();
    state = CallState.active(
      callId: incoming.callId,
      roomId: incoming.roomId,
      isVideo: incoming.isVideo,
      peer: incoming.caller,
      startedAt: _callStartTime!,
    );
  }

  /// Decline an incoming call.
  Future<void> declineCall() async {
    final incoming = state;
    if (incoming is! CallStateRingingIncoming) return;

    await _notificationService.sendDeclineNotification(
      roomId: incoming.roomId,
      callId: incoming.callId,
      callerId: incoming.caller.userId,
    );

    state = const CallState.idle();
  }

  /// End the active or ringing call.
  Future<void> endCall({CallEndReason reason = CallEndReason.hangup}) async {
    _ringTimeout?.cancel();
    final previous = state;

    // Disconnect voice
    await ref.read(voiceServiceProvider.notifier).disconnect();

    // Post system message to DM timeline
    if (previous is CallStateActive) {
      final duration = DateTime.now().difference(previous.startedAt);
      await _postCallSummary(previous.roomId, duration);
    } else if (previous is CallStateRingingOutgoing &&
        reason == CallEndReason.noAnswer) {
      await _postMissedCall(previous.roomId);
    }

    state = const CallState.idle();
  }

  Future<void> _postCallSummary(String roomId, Duration duration) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;

    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final formatted = h > 0 ? '$h:$m:$s' : '$m:$s';

    try {
      await room.sendEvent({
        'msgtype': 'm.text',
        'body': 'Voice call \u00b7 $formatted',
        'im.gloam.call_summary': {
          'duration_ms': duration.inMilliseconds,
          'type': 'voice',
        },
      });
    } catch (_) {
      // Best-effort
    }
  }

  Future<void> _postMissedCall(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;

    try {
      await room.sendEvent({
        'msgtype': 'm.text',
        'body': 'Missed voice call',
        'im.gloam.call_summary': {
          'type': 'missed',
        },
      });
    } catch (_) {
      // Best-effort
    }
  }

  @override
  void dispose() {
    _ringTimeout?.cancel();
    _incomingCallSub?.cancel();
    _notificationService.dispose();
    super.dispose();
  }
}

/// Call state union type.
@freezed
class CallState with _$CallState {
  const factory CallState.idle() = CallStateIdle;

  const factory CallState.ringingOutgoing({
    required String callId,
    required String roomId,
    required bool isVideo,
    required CallPeerInfo peer,
  }) = CallStateRingingOutgoing;

  const factory CallState.ringingIncoming({
    required String callId,
    required String roomId,
    required bool isVideo,
    required CallPeerInfo caller,
  }) = CallStateRingingIncoming;

  const factory CallState.connecting({
    required String callId,
    required String roomId,
  }) = CallStateConnecting;

  const factory CallState.active({
    required String callId,
    required String roomId,
    required bool isVideo,
    required CallPeerInfo peer,
    required DateTime startedAt,
  }) = CallStateActive;
}

/// Info about the other party in a call.
@freezed
class CallPeerInfo with _$CallPeerInfo {
  const factory CallPeerInfo({
    required String userId,
    required String displayName,
    Uri? avatarUrl,
  }) = _CallPeerInfo;
}

enum CallEndReason { hangup, noAnswer, declined }

/// Global call service provider.
final callServiceProvider =
    StateNotifierProvider<CallService, CallState>((ref) {
  final client = ref.watch(matrixServiceProvider).client;
  if (client == null) {
    // Return a dummy that stays idle
    return CallService(ref: ref, client: Client('dummy'));
  }
  return CallService(ref: ref, client: client);
});
