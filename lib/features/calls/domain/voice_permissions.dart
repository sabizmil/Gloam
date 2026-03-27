import 'package:freezed_annotation/freezed_annotation.dart';

part 'voice_permissions.freezed.dart';

/// Normalized permission flags for the current user in the current channel.
///
/// Hides protocol-specific permission models (Matrix power levels,
/// Mumble ACLs, TeamSpeak numeric powers) behind a flat capability set.
@freezed
class VoicePermissions with _$VoicePermissions {
  const factory VoicePermissions({
    @Default(true) bool canSpeak,
    @Default(false) bool canVideo,
    @Default(false) bool canScreenShare,
    @Default(false) bool canMuteOthers,
    @Default(false) bool canDeafenOthers,
    @Default(false) bool canMoveOthers,
    @Default(false) bool canKick,
    @Default(false) bool canBan,
    @Default(false) bool canCreateChannels,
    @Default(false) bool canModifyChannel,
    @Default(false) bool canDisconnectOthers,
  }) = _VoicePermissions;
}
