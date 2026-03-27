import 'dart:async';

import 'package:matrix/matrix.dart';

import '../../domain/domain.dart';
import '../livekit_media_manager.dart';
import '../matrix_rtc_signaling.dart';
import '../sfu_discovery_service.dart';

/// MatrixRTC + LiveKit implementation of [VoiceProtocolAdapter].
///
/// Signaling flows through Matrix room state events ([MatrixRTCSignaling]).
/// Media flows through LiveKit SFU ([LivekitMediaManager]).
/// Identity comes from the Matrix user profile.
class MatrixRTCAdapter implements VoiceProtocolAdapter {
  MatrixRTCAdapter({required Client client})
      : _client = client,
        _sfuDiscovery = SfuDiscoveryService(client: client);

  final Client _client;
  final SfuDiscoveryService _sfuDiscovery;

  MatrixRTCSignaling? _signaling;
  LivekitMediaManager? _media;
  Room? _activeRoom;

  final _connectionState =
      StreamController<VoiceConnectionState>.broadcast();
  final _participants =
      StreamController<List<VoiceParticipant>>.broadcast();
  final _permissions =
      StreamController<VoicePermissions>.broadcast();
  final _textMessages =
      StreamController<VoiceTextMessage>.broadcast();

  StreamSubscription? _mediaParticipantSub;
  StreamSubscription? _mediaConnectionSub;
  StreamSubscription? _signalingMembershipSub;

  // ---------------------------------------------------------------------------
  // VoiceProtocolAdapter identity
  // ---------------------------------------------------------------------------

  @override
  String get protocolId => 'matrixrtc';

  @override
  String get protocolName => 'Matrix';

  @override
  VoiceCapabilities get capabilities => const VoiceCapabilities(
        supportsVideo: true,
        supportsScreenShare: true,
        supportsPersistentChannels: true,
        supportsRinging: true,
        supportsChannelHierarchy: false,
        supportsChannelLinks: false,
        supportsTemporaryChannels: false,
        supportsPositionalAudio: false,
        supportsPerUserVolume: true,
        supportsPushToTalk: true,
        supportsServerMute: true,
        supportsServerDeafen: true,
        supportsMoveUsers: false,
        supportsKick: true,
        supportsBan: true,
        supportsEncryption: true,
        supportsFederation: true,
        supportsTextInVoice: true,
        maxParticipants: 500,
      );

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  @override
  Stream<VoiceConnectionState> get connectionState =>
      _connectionState.stream;

  @override
  Future<void> connect(VoiceServerConfig config) async {
    // For MatrixRTC, "connect" is a no-op at the server level —
    // we use the existing Matrix session. Actual SFU connection
    // happens in joinChannel().
    _connectionState.add(VoiceConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    await channels.leaveChannel();
    _connectionState.add(VoiceConnectionState.disconnected);
  }

  // ---------------------------------------------------------------------------
  // Channel management
  // ---------------------------------------------------------------------------

  @override
  VoiceChannelManager get channels => _channelManager;

  late final _MatrixChannelManager _channelManager =
      _MatrixChannelManager(this);

  // ---------------------------------------------------------------------------
  // Participants
  // ---------------------------------------------------------------------------

  @override
  Stream<List<VoiceParticipant>> get participants => _participants.stream;

  /// Enrich LiveKit participants with Matrix profile data (avatars, names).
  void _mergeParticipants(List<VoiceParticipant> lkParticipants) {
    final enriched = lkParticipants.map((p) {
      // Try to get Matrix profile info for this participant
      final user = _activeRoom?.unsafeGetUserFromMemoryOrFallback(p.id);
      if (user != null) {
        return p.copyWith(
          displayName: user.calcDisplayname(),
          avatarUrl: user.avatarUrl,
        );
      }
      return p;
    }).toList();

    _participants.add(enriched);
  }

  // ---------------------------------------------------------------------------
  // Local media
  // ---------------------------------------------------------------------------

  @override
  VoiceLocalMedia get localMedia => _localMedia;

  late final _MatrixLocalMedia _localMedia = _MatrixLocalMedia(this);

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  @override
  Stream<VoicePermissions> get permissions => _permissions.stream;

  void _updatePermissions() {
    if (_activeRoom == null) return;

    final myPower = _activeRoom!.ownPowerLevel;

    // Default: moderators (PL 50+) can mute/kick/ban
    const moderatorLevel = 50;

    _permissions.add(VoicePermissions(
      canSpeak: true,
      canVideo: true,
      canScreenShare: true,
      canMuteOthers: myPower >= moderatorLevel,
      canDeafenOthers: myPower >= moderatorLevel,
      canKick: _activeRoom!.canKick,
      canBan: _activeRoom!.canBan,
      canDisconnectOthers: myPower >= moderatorLevel,
      canCreateChannels: _activeRoom!.canSendEvent(EventTypes.RoomCreate),
      canModifyChannel: myPower >= moderatorLevel,
    ));
  }

  // ---------------------------------------------------------------------------
  // Text chat
  // ---------------------------------------------------------------------------

  @override
  Future<void> sendTextMessage(String text) async {
    if (_activeRoom == null) return;
    await _activeRoom!.sendTextEvent(text);
  }

  @override
  Stream<VoiceTextMessage> get textMessages => _textMessages.stream;

  // ---------------------------------------------------------------------------
  // Internal: join/leave SFU
  // ---------------------------------------------------------------------------

  Future<void> _joinRoom(String roomId) async {
    _activeRoom = _client.getRoomById(roomId);
    if (_activeRoom == null) {
      throw VoiceConnectionError('Room $roomId not found');
    }

    _connectionState.add(VoiceConnectionState.connecting);

    // Discover SFU and get credentials
    final credentials = await _sfuDiscovery.getCredentials(roomId: roomId);

    // Set up signaling (Matrix state events)
    _signaling = MatrixRTCSignaling(client: _client, room: _activeRoom!);
    _signaling!.startListening();

    // Send our membership event
    await _signaling!.join(
      callId: roomId, // Use room ID as call ID for voice channels
      livekitServiceUrl: credentials.sfuUrl,
    );

    // Connect to LiveKit SFU
    _media = LivekitMediaManager();
    _mediaParticipantSub = _media!.participants.listen(_mergeParticipants);
    _mediaConnectionSub = _media!.connectionState.listen((state) {
      _connectionState.add(state);
    });

    await _media!.connect(credentials);

    _updatePermissions();
  }

  Future<void> _leaveRoom() async {
    await _mediaParticipantSub?.cancel();
    await _mediaConnectionSub?.cancel();
    await _signalingMembershipSub?.cancel();

    await _signaling?.leave();
    await _signaling?.dispose();
    _signaling = null;

    await _media?.disconnect();
    await _media?.dispose();
    _media = null;

    _activeRoom = null;
    _participants.add([]);
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    await _leaveRoom();
    await _connectionState.close();
    await _participants.close();
    await _permissions.close();
    await _textMessages.close();
  }
}

// =============================================================================
// Channel Manager
// =============================================================================

class _MatrixChannelManager implements VoiceChannelManager {
  _MatrixChannelManager(this._adapter);

  final MatrixRTCAdapter _adapter;
  final _currentChannel = StreamController<VoiceChannel?>.broadcast();

  @override
  Stream<List<VoiceChannel>> get channels {
    // Return all rooms in the current space that are tagged as voice channels.
    // For now, return a simple stream that updates on sync.
    return _adapter._client.onSync.stream.map((_) {
      return _adapter._client.rooms
          .where((r) => isVoiceChannel(r.id))
          .map((r) => _roomToChannel(r))
          .toList();
    });
  }

  @override
  Stream<VoiceChannel?> get currentChannel => _currentChannel.stream;

  @override
  Future<void> joinChannel(String channelId) async {
    await _adapter._joinRoom(channelId);

    final room = _adapter._client.getRoomById(channelId);
    if (room != null) {
      _currentChannel.add(_roomToChannel(room));
    }
  }

  @override
  Future<void> leaveChannel() async {
    await _adapter._leaveRoom();
    _currentChannel.add(null);
  }

  @override
  bool isVoiceChannel(String roomId) {
    final room = _adapter._client.getRoomById(roomId);
    if (room == null) return false;

    // Check room create event for voice channel type
    final createEvent = room.getState(EventTypes.RoomCreate);
    if (createEvent != null) {
      final roomType = createEvent.content['type'];
      if (roomType == 'im.gloam.voice_channel') return true;
      if (roomType == 'org.matrix.msc3417.call') return true;
    }

    // Check room tags as fallback
    return room.tags.containsKey('im.gloam.voice_channel');
  }

  VoiceChannel _roomToChannel(Room room) {
    // Parse active participants from m.rtc.member state events
    final memberStates =
        room.states['org.matrix.msc3401.call.member'] ?? {};
    final participants = <VoiceChannelParticipantSummary>[];

    for (final entry in memberStates.entries) {
      final userId = entry.key;
      final event = entry.value;
      final memberships = event.content['memberships'];
      if (memberships is! List || memberships.isEmpty) continue;

      final user = room.unsafeGetUserFromMemoryOrFallback(userId);
      participants.add(VoiceChannelParticipantSummary(
        userId: userId,
        displayName: user.calcDisplayname(),
        avatarUrl: user.avatarUrl,
      ));
    }

    return VoiceChannel(
      id: room.id,
      name: room.getLocalizedDisplayname(),
      description: room.topic,
      currentParticipantCount: participants.length,
      connectedParticipants: participants,
    );
  }
}

// =============================================================================
// Local Media
// =============================================================================

class _MatrixLocalMedia implements VoiceLocalMedia {
  _MatrixLocalMedia(this._adapter);

  final MatrixRTCAdapter _adapter;

  LivekitMediaManager? get _media => _adapter._media;

  @override
  Stream<bool> get isMuted =>
      _media?.participants.map((_) => _media?.isMuted ?? false) ??
      Stream.value(false);

  @override
  Stream<bool> get isDeafened =>
      _media?.participants.map((_) => _media?.isDeafened ?? false) ??
      Stream.value(false);

  @override
  Stream<bool> get hasVideo =>
      _media?.participants.map((_) => _media?.hasVideo ?? false) ??
      Stream.value(false);

  @override
  Stream<bool> get isScreenSharing =>
      _media?.participants.map((_) => _media?.isScreenSharing ?? false) ??
      Stream.value(false);

  @override
  Stream<double> get localAudioLevel =>
      _media?.localAudioLevel ?? Stream.value(0.0);

  @override
  Future<void> setMuted(bool muted) async => _media?.setMuted(muted);

  @override
  Future<void> setDeafened(bool deafened) async =>
      _media?.setDeafened(deafened);

  @override
  Future<void> setVideo(bool enabled) async => _media?.setVideo(enabled);

  @override
  Future<void> setScreenShare(bool enabled) async =>
      _media?.setScreenShare(enabled);

  @override
  Future<void> setUserVolume(String participantId, double volume) async =>
      _media?.setUserVolume(participantId, volume);

  @override
  Future<void> setInputDevice(String deviceId) async {
    // Delegated to AudioDeviceService (shared, not per-adapter)
  }

  @override
  Future<void> setOutputDevice(String deviceId) async {
    // Delegated to AudioDeviceService (shared, not per-adapter)
  }
}
