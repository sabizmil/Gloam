import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../features/chat/presentation/screens/chat_screen.dart';
import '../../../../services/matrix_service.dart';
import '../../../../services/voice_service.dart';
import '../../data/adapters/matrix_rtc_adapter.dart';
import '../../../../services/debug_server.dart';
import '../../domain/voice_participant.dart';
import '../widgets/participant_grid.dart';

void _log(String msg) {
  debugPrint(msg);
  DebugServer.logs.add('${DateTime.now().toIso8601String()} $msg');
}

/// Full voice channel view — participant grid + text-in-voice.
///
/// Replaces the ChatScreen in the main content area when a voice
/// channel is selected and the user is connected.
class VoiceChannelScreen extends ConsumerWidget {
  const VoiceChannelScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceState = ref.watch(voiceServiceProvider);

    final participants = voiceState is VoiceStateConnected
        ? voiceState.participants
        : <VoiceParticipant>[];
    final channelName = voiceState is VoiceStateConnected
        ? voiceState.channelName
        : '';
    final isConnected = voiceState is VoiceStateConnected &&
        voiceState.channelId == roomId;

    return Container(
      color: GloamColors.bg,
      child: Column(
        children: [
          // Header
          _VoiceChannelHeader(
            channelName: channelName,
            participantCount: participants.length,
            isConnected: isConnected,
          ),

          // Participant grid (center of screen)
          Expanded(
            flex: 3,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: isConnected
                    ? ParticipantGrid(participants: participants)
                    : _JoinPrompt(
                        roomId: roomId,
                        channelName: channelName,
                      ),
              ),
            ),
          ),

          // Text-in-voice panel
          _TextInVoicePanel(roomId: roomId),
        ],
      ),
    );
  }
}

class _VoiceChannelHeader extends StatelessWidget {
  const _VoiceChannelHeader({
    required this.channelName,
    required this.participantCount,
    required this.isConnected,
  });

  final String channelName;
  final int participantCount;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: GloamColors.border),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.volume_up_rounded,
            size: 20,
            color: isConnected ? GloamColors.accent : GloamColors.textTertiary,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                channelName,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: GloamColors.textPrimary,
                ),
              ),
              if (isConnected)
                Text(
                  '$participantCount connected',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: GloamColors.textTertiary,
                  ),
                ),
            ],
          ),
          const Spacer(),
          Icon(Icons.settings_outlined,
              size: 18, color: GloamColors.textTertiary),
        ],
      ),
    );
  }
}

/// Shown when viewing a voice channel you haven't joined yet.
class _JoinPrompt extends ConsumerWidget {
  const _JoinPrompt({required this.roomId, required this.channelName});

  final String roomId;
  final String channelName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.volume_up_rounded,
            size: 48, color: GloamColors.textTertiary),
        const SizedBox(height: 16),
        Text(
          channelName.isEmpty ? 'Voice Channel' : channelName,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: GloamColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '// click to join',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: GloamColors.textTertiary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 24),
        Material(
          color: GloamColors.accentDim,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _joinVoice(context, ref),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.volume_up_rounded,
                      size: 18, color: GloamColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Join Voice',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: GloamColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _joinVoice(BuildContext context, WidgetRef ref) async {
    _log('[voice] Join Voice tapped for room: $roomId');
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) {
      _log('[voice] ERROR: client is null');
      return;
    }

    _log('[voice] Creating MatrixRTCAdapter...');
    final adapter = MatrixRTCAdapter(client: client);
    try {
      _log('[voice] Calling voiceService.joinChannel...');
      await ref.read(voiceServiceProvider.notifier).joinChannel(
            adapter: adapter,
            channelId: roomId,
          );
      _log('[voice] joinChannel completed successfully');
    } catch (e, st) {
      _log('[voice] ERROR joining voice: $e');
      _log('[voice] Stack trace: $st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join voice: $e'),
            backgroundColor: GloamColors.danger,
          ),
        );
      }
    }
  }
}

/// Collapsible text chat panel at the bottom of the voice channel view.
///
/// Reuses the existing timeline and composer from the chat feature.
class _TextInVoicePanel extends ConsumerStatefulWidget {
  const _TextInVoicePanel({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_TextInVoicePanel> createState() =>
      _TextInVoicePanelState();
}

class _TextInVoicePanelState extends ConsumerState<_TextInVoicePanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: GloamColors.bgSurface,
        border: Border(
          top: BorderSide(color: GloamColors.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with toggle
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded,
                      size: 14, color: GloamColors.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    'text chat',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: GloamColors.textTertiary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 16,
                    color: GloamColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),

          // Chat content (collapsible)
          if (_expanded)
            SizedBox(
              height: 180,
              child: ChatScreen(roomId: widget.roomId, compact: true),
            ),
        ],
      ),
    );
  }
}
