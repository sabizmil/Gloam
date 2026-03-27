import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

import '../domain/voice_connection_quality.dart';
import '../domain/voice_connection_state.dart';
import '../domain/voice_error.dart';
import '../domain/voice_participant.dart';
import 'sfu_discovery_service.dart';

/// Manages the LiveKit room connection and audio/video tracks.
///
/// This is the media transport layer — it handles WebRTC peer connections,
/// audio publishing/subscribing, and real-time participant state.
/// Signaling (who is "in the call" according to Matrix) is handled
/// separately by [MatrixRTCSignaling].
class LivekitMediaManager {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  final _connectionState =
      StreamController<VoiceConnectionState>.broadcast();
  final _participants =
      StreamController<List<VoiceParticipant>>.broadcast();
  final _localAudioLevel = StreamController<double>.broadcast();

  bool _isMuted = false;
  bool _isDeafened = false;
  bool _hasVideo = false;
  bool _isScreenSharing = false;

  /// Connection state stream.
  Stream<VoiceConnectionState> get connectionState =>
      _connectionState.stream;

  /// Participants (local + remote) as protocol-agnostic entities.
  Stream<List<VoiceParticipant>> get participants => _participants.stream;

  /// Local microphone audio level (0.0 – 1.0).
  Stream<double> get localAudioLevel => _localAudioLevel.stream;

  bool get isMuted => _isMuted;
  bool get isDeafened => _isDeafened;
  bool get hasVideo => _hasVideo;
  bool get isScreenSharing => _isScreenSharing;

  /// Connect to a LiveKit SFU with the given credentials.
  Future<void> connect(SfuCredentials credentials) async {
    _connectionState.add(VoiceConnectionState.connecting);

    try {
      _room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(
            dtx: true, // Discontinuous transmission for silence
          ),
        ),
      );

      // Set up event listener before connecting
      _listener = _room!.createListener();
      _setupEventListeners();

      await _room!.connect(
        credentials.sfuUrl,
        credentials.jwt,
        fastConnectOptions: FastConnectOptions(
          microphone: const TrackOption(enabled: true),
          camera: const TrackOption(enabled: false),
        ),
      );

      _isMuted = false;
      _connectionState.add(VoiceConnectionState.connected);
      _emitParticipants();
    } catch (e) {
      _connectionState.add(VoiceConnectionState.error);
      throw VoiceConnectionError('Failed to connect to LiveKit: $e');
    }
  }

  void _setupEventListeners() {
    final listener = _listener;
    if (listener == null) return;

    listener
      ..on<ParticipantConnectedEvent>((_) => _emitParticipants())
      ..on<ParticipantDisconnectedEvent>((_) => _emitParticipants())
      ..on<TrackSubscribedEvent>((_) => _emitParticipants())
      ..on<TrackUnsubscribedEvent>((_) => _emitParticipants())
      ..on<TrackMutedEvent>((_) => _emitParticipants())
      ..on<TrackUnmutedEvent>((_) => _emitParticipants())
      ..on<ActiveSpeakersChangedEvent>((e) {
        _emitParticipants();
        // Update local audio level
        final local = _room?.localParticipant;
        if (local != null) {
          _localAudioLevel.add(local.audioLevel);
        }
      })
      ..on<ParticipantConnectionQualityUpdatedEvent>(
          (_) => _emitParticipants())
      ..on<RoomReconnectingEvent>((_) {
        _connectionState.add(VoiceConnectionState.reconnecting);
      })
      ..on<RoomReconnectedEvent>((_) {
        _connectionState.add(VoiceConnectionState.connected);
        _emitParticipants();
      })
      ..on<RoomDisconnectedEvent>((_) {
        _connectionState.add(VoiceConnectionState.disconnected);
      });
  }

  /// Emit the current participant list to the stream.
  void _emitParticipants() {
    if (_room == null) return;

    final all = <VoiceParticipant>[];

    // Local participant
    final local = _room!.localParticipant;
    if (local != null) {
      all.add(_mapLocalParticipant(local));
    }

    // Remote participants
    for (final remote in _room!.remoteParticipants.values) {
      all.add(_mapRemoteParticipant(remote));
    }

    _participants.add(all);
  }

  VoiceParticipant _mapLocalParticipant(LocalParticipant p) {
    return VoiceParticipant(
      id: p.identity,
      displayName: p.name.isNotEmpty ? p.name : p.identity,
      isSelf: true,
      isMuted: _isMuted,
      isDeafened: _isDeafened,
      isSpeaking: p.isSpeaking,
      audioLevel: p.audioLevel,
      hasVideo: p.isCameraEnabled(),
      isScreenSharing: p.isScreenShareEnabled(),
      connectionQuality: _mapQuality(p.connectionQuality),
    );
  }

  VoiceParticipant _mapRemoteParticipant(RemoteParticipant p) {
    return VoiceParticipant(
      id: p.identity,
      displayName: p.name.isNotEmpty ? p.name : p.identity,
      isSelf: false,
      isMuted: !p.isMicrophoneEnabled(),
      isSpeaking: p.isSpeaking,
      audioLevel: p.audioLevel,
      hasVideo: p.isCameraEnabled(),
      isScreenSharing: p.isScreenShareEnabled(),
      connectionQuality: _mapQuality(p.connectionQuality),
    );
  }

  VoiceConnectionQuality _mapQuality(ConnectionQuality q) {
    return switch (q) {
      ConnectionQuality.excellent => VoiceConnectionQuality.good,
      ConnectionQuality.good => VoiceConnectionQuality.good,
      ConnectionQuality.poor => VoiceConnectionQuality.poor,
      ConnectionQuality.lost => VoiceConnectionQuality.poor,
      _ => VoiceConnectionQuality.unknown,
    };
  }

  // ---------------------------------------------------------------------------
  // Local media controls
  // ---------------------------------------------------------------------------

  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
    _emitParticipants();
  }

  Future<void> setDeafened(bool deafened) async {
    _isDeafened = deafened;

    // Mute all remote audio tracks locally
    if (_room != null) {
      for (final remote in _room!.remoteParticipants.values) {
        for (final pub in remote.audioTrackPublications) {
          if (deafened) {
            await pub.track?.disable();
          } else {
            await pub.track?.enable();
          }
        }
      }
    }

    // Deafening also implies muting
    if (deafened && !_isMuted) {
      await setMuted(true);
    }

    _emitParticipants();
  }

  Future<void> setVideo(bool enabled) async {
    _hasVideo = enabled;
    await _room?.localParticipant?.setCameraEnabled(enabled);
    _emitParticipants();
  }

  Future<void> setScreenShare(bool enabled) async {
    _isScreenSharing = enabled;
    await _room?.localParticipant?.setScreenShareEnabled(enabled);
    _emitParticipants();
  }

  Future<void> setUserVolume(String participantId, double volume) async {
    // LiveKit doesn't have a direct per-user volume API at the SDK level.
    // We can mute/unmute individual tracks, but fine-grained volume control
    // requires WebRTC track gain manipulation. For now, support mute (0.0)
    // and normal (any > 0.0).
    final remote = _room?.remoteParticipants[participantId];
    if (remote == null) return;

    for (final pub in remote.audioTrackPublications) {
      if (volume <= 0.0) {
        await pub.track?.disable();
      } else {
        await pub.track?.enable();
      }
    }
  }

  /// Disconnect from the LiveKit room and release all resources.
  Future<void> disconnect() async {
    _listener?.dispose();
    _listener = null;

    await _room?.disconnect();
    _room?.dispose();
    _room = null;

    _isMuted = false;
    _isDeafened = false;
    _hasVideo = false;
    _isScreenSharing = false;

    _connectionState.add(VoiceConnectionState.disconnected);
  }

  /// Dispose all stream controllers.
  Future<void> dispose() async {
    await disconnect();
    await _connectionState.close();
    await _participants.close();
    await _localAudioLevel.close();
  }
}
