/// The type of voice channel.
enum VoiceChannelType {
  /// Standard voice channel — anyone with permission can join and speak.
  voice,

  /// Stage channel — structured speaker/audience model.
  stage,

  /// Visual spacer in the channel list (not joinable).
  categorySpacer,
}
