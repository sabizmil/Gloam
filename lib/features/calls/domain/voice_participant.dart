import 'package:freezed_annotation/freezed_annotation.dart';

import 'voice_connection_quality.dart';

part 'voice_participant.freezed.dart';

/// A participant in a voice channel or call.
///
/// Protocol adapters produce a [Stream<List<VoiceParticipant>>] that
/// the UI consumes directly. The UI never subscribes to LiveKit, Mumble,
/// or any protocol SDK's participant model — only this.
@freezed
class VoiceParticipant with _$VoiceParticipant {
  const factory VoiceParticipant({
    required String id,
    required String displayName,
    Uri? avatarUrl,
    @Default(false) bool isSelf,

    // Audio state
    @Default(false) bool isMuted,
    @Default(false) bool isDeafened,
    @Default(false) bool isServerMuted,
    @Default(false) bool isServerDeafened,
    @Default(false) bool isSpeaking,
    @Default(0.0) double audioLevel,

    // Video state
    @Default(false) bool hasVideo,
    @Default(false) bool isScreenSharing,

    // Connection
    @Default(VoiceConnectionQuality.good) VoiceConnectionQuality connectionQuality,

    // Protocol-specific data the UI can ignore but adapters may need
    @Default({}) Map<String, dynamic> protocolMetadata,
  }) = _VoiceParticipant;
}
