/// Connection state for a voice protocol adapter.
///
/// Mirrors the lifecycle of connecting to a voice server/SFU.
enum VoiceConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}
