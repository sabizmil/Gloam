import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'debug_server.dart';

import '../features/calls/domain/domain.dart';

part 'voice_service.freezed.dart';

/// Global voice state — the single source of truth for voice across the app.
///
/// Every voice-related widget watches this provider: the persistent voice bar,
/// room list sidebar, participant grid, and call screens. The provider is
/// `keepAlive` so the voice connection survives navigation.
///
/// This service depends only on [VoiceProtocolAdapter] — never on LiveKit,
/// matrix SDK, or any protocol-specific type.
class VoiceService extends StateNotifier<VoiceState> {
  VoiceService() : super(const VoiceState.disconnected());

  VoiceProtocolAdapter? _adapter;
  StreamSubscription? _connectionSub;
  StreamSubscription? _participantSub;
  StreamSubscription? _permissionSub;

  /// The currently active adapter (null if disconnected).
  VoiceProtocolAdapter? get adapter => _adapter;

  /// Convenience: is the user currently in a voice channel or call?
  bool get isConnected => state is VoiceStateConnected;

  /// Convenience: the current local media controls (null if disconnected).
  VoiceLocalMedia? get localMedia => _adapter?.localMedia;

  bool _joining = false;

  /// Join a voice channel.
  ///
  /// If already connected to a different channel, disconnects first.
  /// Ignores duplicate calls while a join is in progress.
  Future<void> joinChannel({
    required VoiceProtocolAdapter adapter,
    required String channelId,
  }) async {
    // Prevent duplicate join attempts (e.g., double-clicking Join)
    if (_joining) return;
    _joining = true;

    // Disconnect from current channel if any
    if (_adapter != null) {
      await disconnect();
    }

    _adapter = adapter;
    state = VoiceState.connecting(channelId: channelId);

    try {
      _log('[VoiceService] Starting join for channel: $channelId');

      // Subscribe to connection state changes
      _connectionSub = adapter.connectionState.listen((connState) {
        _log('[VoiceService] Connection state changed: $connState');
        if (connState == VoiceConnectionState.connected &&
            state is! VoiceStateConnected) {
          // LiveKit connected (possibly after retry) — update UI
          state = VoiceState.connected(
            channelId: channelId,
            channelName: channelId, // will be updated by channel stream
            protocolName: adapter.protocolName,
            participants: [],
            permissions: const VoicePermissions(),
            connectedAt: DateTime.now(),
          );
        } else if (connState == VoiceConnectionState.reconnecting) {
          state = VoiceState.reconnecting(channelId: channelId);
        } else if (connState == VoiceConnectionState.error) {
          state = VoiceState.error(
            message: 'Connection lost',
            channelId: channelId,
          );
        }
      });

      // Subscribe to participant updates
      _participantSub = adapter.participants.listen((participants) {
        final current = state;
        if (current is VoiceStateConnected) {
          state = current.copyWith(participants: participants);
        }
      });

      // Subscribe to permission updates
      _permissionSub = adapter.permissions.listen((perms) {
        final current = state;
        if (current is VoiceStateConnected) {
          state = current.copyWith(permissions: perms);
        }
      });

      // Join the channel
      await adapter.channels.joinChannel(channelId);

      // Get channel info
      final channel = await adapter.channels.currentChannel.first;

      state = VoiceState.connected(
        channelId: channelId,
        channelName: channel?.name ?? '',
        protocolName: adapter.protocolName,
        participants: [],
        permissions: const VoicePermissions(),
        connectedAt: DateTime.now(),
      );
      _log('[VoiceService] Connected to $channelId');
    } on VoiceError catch (e) {
      _log('[VoiceService] VoiceError: ${e.message}');
      state = VoiceState.error(message: e.message, channelId: channelId);
      await _cleanup();
    } catch (e, st) {
      _log('[VoiceService] Error: $e');
      _log('[VoiceService] Stack: $st');
      state = VoiceState.error(message: '$e', channelId: channelId);
      await _cleanup();
    } finally {
      _joining = false;
    }
  }

  /// Disconnect from the current voice channel.
  Future<void> disconnect() async {
    try {
      await _adapter?.channels.leaveChannel();
      await _adapter?.disconnect();
    } catch (_) {
      // Best-effort cleanup
    }
    await _cleanup();
    state = const VoiceState.disconnected();
  }

  /// Toggle mute state.
  Future<void> toggleMute() async {
    final media = _adapter?.localMedia;
    if (media == null) return;

    final muted = await media.isMuted.first;
    await media.setMuted(!muted);
  }

  /// Toggle deafen state.
  Future<void> toggleDeafen() async {
    final media = _adapter?.localMedia;
    if (media == null) return;

    final deafened = await media.isDeafened.first;
    await media.setDeafened(!deafened);
  }

  Future<void> _cleanup() async {
    await _connectionSub?.cancel();
    await _participantSub?.cancel();
    await _permissionSub?.cancel();
    _connectionSub = null;
    _participantSub = null;
    _permissionSub = null;
    _adapter = null;
  }

  void _log(String msg) {
    debugPrint(msg);
    DebugServer.logs.add('${DateTime.now().toIso8601String()} $msg');
    if (DebugServer.logs.length > 200) DebugServer.logs.removeAt(0);
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

/// Voice state union type.
@freezed
class VoiceState with _$VoiceState {
  const factory VoiceState.disconnected() = VoiceStateDisconnected;

  const factory VoiceState.connecting({
    required String channelId,
  }) = VoiceStateConnecting;

  const factory VoiceState.connected({
    required String channelId,
    required String channelName,
    required String protocolName,
    required List<VoiceParticipant> participants,
    required VoicePermissions permissions,
    required DateTime connectedAt,
  }) = VoiceStateConnected;

  const factory VoiceState.reconnecting({
    required String channelId,
  }) = VoiceStateReconnecting;

  const factory VoiceState.error({
    required String message,
    String? channelId,
  }) = VoiceStateError;
}

/// Global VoiceService provider — persists across navigation.
final voiceServiceProvider =
    StateNotifierProvider<VoiceService, VoiceState>((ref) {
  return VoiceService();
});
