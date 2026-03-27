/// Voice system errors.
///
/// Thrown by adapter implementations, caught by [VoiceService].
/// Using a sealed hierarchy lets the service layer handle each
/// error type with pattern matching.
sealed class VoiceError implements Exception {
  const VoiceError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Server configuration missing or invalid.
///
/// Thrown when the homeserver lacks .well-known rtc_foci (MatrixRTC),
/// or the Mumble server address is unreachable, etc.
class VoiceConfigError extends VoiceError {
  const VoiceConfigError(super.message);
}

/// Connection to the voice server or SFU failed.
class VoiceConnectionError extends VoiceError {
  const VoiceConnectionError(super.message);
}

/// Microphone or camera permission denied by the OS.
class VoicePermissionError extends VoiceError {
  const VoicePermissionError(super.message);
}

/// Voice channel is at capacity.
class VoiceChannelFullError extends VoiceError {
  const VoiceChannelFullError(this.channelId, this.maxParticipants)
      : super('Channel is full ($maxParticipants/$maxParticipants)');

  final String channelId;
  final int maxParticipants;
}
