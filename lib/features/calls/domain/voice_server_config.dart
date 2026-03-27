/// Configuration for connecting to a voice server.
///
/// Each protocol subtype carries the credentials and endpoint info
/// specific to that protocol. The UI stores these in a unified
/// "saved servers" list regardless of protocol.
sealed class VoiceServerConfig {
  const VoiceServerConfig({
    required this.id,
    required this.displayName,
    required this.protocolId,
  });

  final String id;
  final String displayName;
  final String protocolId;
}

/// Matrix homeserver with MatrixRTC + LiveKit SFU.
///
/// No additional config beyond the homeserver URL — the SFU endpoint
/// is discovered via .well-known and auth uses the existing Matrix session.
class MatrixVoiceServerConfig extends VoiceServerConfig {
  const MatrixVoiceServerConfig({
    required super.id,
    required super.displayName,
    required this.homeserverUrl,
  }) : super(protocolId: 'matrixrtc');

  final String homeserverUrl;
}

/// Mumble server connection config (future use).
class MumbleServerConfig extends VoiceServerConfig {
  const MumbleServerConfig({
    required super.id,
    required super.displayName,
    required this.host,
    this.port = 64738,
    this.username,
    this.password,
  }) : super(protocolId: 'mumble');

  final String host;
  final int port;
  final String? username;
  final String? password;
}

/// Jitsi Meet server config (future use).
class JitsiServerConfig extends VoiceServerConfig {
  const JitsiServerConfig({
    required super.id,
    required super.displayName,
    required this.serverUrl,
  }) : super(protocolId: 'jitsi');

  final String serverUrl;
}
