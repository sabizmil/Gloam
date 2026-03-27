import 'package:freezed_annotation/freezed_annotation.dart';

import 'voice_channel_type.dart';

part 'voice_channel.freezed.dart';

/// A voice channel within a voice server.
///
/// Supports both flat (Matrix, Jitsi) and hierarchical (Mumble, TeamSpeak)
/// channel models via [parentId] and [childIds]. For flat protocols,
/// [parentId] is null and [childIds] is empty.
@freezed
class VoiceChannel with _$VoiceChannel {
  const factory VoiceChannel({
    required String id,
    required String name,
    String? description,
    String? parentId,
    @Default([]) List<String> childIds,
    int? maxParticipants,
    @Default(0) int currentParticipantCount,
    @Default(false) bool isTemporary,
    @Default(false) bool isLinked,
    @Default(VoiceChannelType.voice) VoiceChannelType type,
    @Default([]) List<VoiceChannelParticipantSummary> connectedParticipants,
    @Default({}) Map<String, dynamic> protocolMetadata,
  }) = _VoiceChannel;
}

/// Lightweight participant info for sidebar display.
///
/// Intentionally separate from [VoiceParticipant] — the sidebar only
/// needs name/avatar/speaking/muted, and for non-joined channels this
/// is derived from state events, not LiveKit.
@freezed
class VoiceChannelParticipantSummary with _$VoiceChannelParticipantSummary {
  const factory VoiceChannelParticipantSummary({
    required String userId,
    required String displayName,
    Uri? avatarUrl,
    @Default(false) bool isSpeaking,
    @Default(false) bool isMuted,
  }) = _VoiceChannelParticipantSummary;
}
