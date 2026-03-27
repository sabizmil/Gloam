import 'package:freezed_annotation/freezed_annotation.dart';

part 'voice_text_message.freezed.dart';

/// A text message sent within a voice channel.
///
/// Used by the text-in-voice feature. Protocol adapters map their native
/// text message format to this entity.
@freezed
class VoiceTextMessage with _$VoiceTextMessage {
  const factory VoiceTextMessage({
    required String id,
    required String senderId,
    required String senderName,
    required String body,
    required DateTime timestamp,
  }) = _VoiceTextMessage;
}
