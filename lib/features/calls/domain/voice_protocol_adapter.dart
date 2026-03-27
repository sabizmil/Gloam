import 'voice_capabilities.dart';
import 'voice_channel.dart';
import 'voice_connection_state.dart';
import 'voice_participant.dart';
import 'voice_permissions.dart';
import 'voice_server_config.dart';
import 'voice_text_message.dart';

/// The top-level interface every voice protocol must implement.
///
/// MatrixRTC, Mumble, and Jitsi each provide a concrete adapter.
/// The [VoiceService] and all voice UI depend only on this interface —
/// never on LiveKit, dumble, or any protocol SDK directly.
abstract class VoiceProtocolAdapter {
  /// Unique machine identifier for this protocol (e.g., "matrixrtc", "mumble").
  String get protocolId;

  /// Human-readable name (e.g., "Matrix", "Mumble").
  String get protocolName;

  /// Static capability flags — what this protocol supports.
  VoiceCapabilities get capabilities;

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  /// Reactive connection state.
  Stream<VoiceConnectionState> get connectionState;

  /// Connect to the voice server. For MatrixRTC this is a no-op at the server
  /// level (uses existing Matrix session); actual SFU connection happens in
  /// [VoiceChannelManager.joinChannel].
  Future<void> connect(VoiceServerConfig config);

  /// Disconnect from the voice server and leave any active channel.
  Future<void> disconnect();

  // ---------------------------------------------------------------------------
  // Channel management
  // ---------------------------------------------------------------------------

  /// Channel management sub-interface.
  VoiceChannelManager get channels;

  // ---------------------------------------------------------------------------
  // Participants
  // ---------------------------------------------------------------------------

  /// Reactive list of participants in the current channel.
  /// Empty when not connected to any channel.
  Stream<List<VoiceParticipant>> get participants;

  // ---------------------------------------------------------------------------
  // Local media
  // ---------------------------------------------------------------------------

  /// Local audio/video control sub-interface.
  VoiceLocalMedia get localMedia;

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Reactive permissions for the current user in the current channel.
  Stream<VoicePermissions> get permissions;

  // ---------------------------------------------------------------------------
  // Text chat
  // ---------------------------------------------------------------------------

  /// Send a text message in the current voice channel.
  Future<void> sendTextMessage(String text);

  /// Reactive stream of text messages in the current voice channel.
  Stream<VoiceTextMessage> get textMessages;

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Release all resources. Called when the adapter is no longer needed.
  Future<void> dispose();
}

/// Manages voice channels within a server.
///
/// For MatrixRTC, channels are Matrix rooms tagged as voice channels.
/// For Mumble, channels are the server's channel tree.
abstract class VoiceChannelManager {
  /// All voice channels visible to the user.
  Stream<List<VoiceChannel>> get channels;

  /// The channel the user is currently in. Null if not in any channel.
  Stream<VoiceChannel?> get currentChannel;

  /// Join a voice channel by ID. Connects to the SFU and starts
  /// publishing/subscribing to audio tracks.
  Future<void> joinChannel(String channelId);

  /// Leave the current channel. Stops audio and removes membership.
  Future<void> leaveChannel();

  /// Whether a given room/channel ID is a voice channel.
  /// Used by the room list to decide rendering (speaker icon vs hash).
  bool isVoiceChannel(String roomId);
}

/// Controls local audio and video tracks.
///
/// Protocol-agnostic — the same mute/deafen/volume calls work for
/// MatrixRTC (LiveKit tracks), Mumble (Opus stream), or any future protocol.
abstract class VoiceLocalMedia {
  Stream<bool> get isMuted;
  Stream<bool> get isDeafened;
  Stream<bool> get hasVideo;
  Stream<bool> get isScreenSharing;

  /// Local microphone audio level (0.0 – 1.0). Updated frequently
  /// for the "speaking" indicator on the local user's tile.
  Stream<double> get localAudioLevel;

  Future<void> setMuted(bool muted);
  Future<void> setDeafened(bool deafened);
  Future<void> setVideo(bool enabled);
  Future<void> setScreenShare(bool enabled);

  /// Adjust the volume of a specific remote participant.
  /// [volume] range: 0.0 (silent) to 2.0 (200%). Default is 1.0.
  Future<void> setUserVolume(String participantId, double volume);

  /// Switch the audio input device (microphone).
  Future<void> setInputDevice(String deviceId);

  /// Switch the audio output device (speaker/headphones).
  Future<void> setOutputDevice(String deviceId);
}
