/// Declares what a voice protocol adapter supports.
///
/// The UI checks these flags to show/hide features rather than checking
/// which protocol is active. This keeps the presentation layer
/// protocol-agnostic.
class VoiceCapabilities {
  const VoiceCapabilities({
    this.supportsVideo = false,
    this.supportsScreenShare = false,
    this.supportsPersistentChannels = false,
    this.supportsRinging = false,
    this.supportsChannelHierarchy = false,
    this.supportsChannelLinks = false,
    this.supportsTemporaryChannels = false,
    this.supportsPositionalAudio = false,
    this.supportsPerUserVolume = false,
    this.supportsPushToTalk = false,
    this.supportsServerMute = false,
    this.supportsServerDeafen = false,
    this.supportsMoveUsers = false,
    this.supportsKick = false,
    this.supportsBan = false,
    this.supportsEncryption = false,
    this.supportsFederation = false,
    this.supportsTextInVoice = false,
    this.maxParticipants = 0,
  });

  // Core
  final bool supportsVideo;
  final bool supportsScreenShare;
  final bool supportsPersistentChannels;
  final bool supportsRinging;

  // Channel model
  final bool supportsChannelHierarchy;
  final bool supportsChannelLinks;
  final bool supportsTemporaryChannels;

  // Audio
  final bool supportsPositionalAudio;
  final bool supportsPerUserVolume;
  final bool supportsPushToTalk;

  // Moderation
  final bool supportsServerMute;
  final bool supportsServerDeafen;
  final bool supportsMoveUsers;
  final bool supportsKick;
  final bool supportsBan;

  // Other
  final bool supportsEncryption;
  final bool supportsFederation;
  final bool supportsTextInVoice;

  /// Maximum participants per channel. 0 means unlimited.
  final int maxParticipants;
}
