import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoSession {
  VideoSession({
    required this.eventId,
    required this.player,
    required this.controller,
  });
  final String eventId;
  final Player player;
  final VideoController controller;
}

class VideoSessionState {
  const VideoSessionState({
    this.active,
    this.loadingEventId,
    this.errorEventId,
    this.isPlaying = false,
  });
  final VideoSession? active;
  final String? loadingEventId;
  final String? errorEventId;
  final bool isPlaying;

  bool isActiveFor(String id) => active?.eventId == id;
  bool isLoadingFor(String id) => loadingEventId == id;
  bool isErrorFor(String id) => errorEventId == id;

  VideoSessionState copyWith({
    VideoSession? active,
    String? loadingEventId,
    String? errorEventId,
    bool? isPlaying,
    bool clearActive = false,
    bool clearLoading = false,
    bool clearError = false,
  }) {
    return VideoSessionState(
      active: clearActive ? null : (active ?? this.active),
      loadingEventId:
          clearLoading ? null : (loadingEventId ?? this.loadingEventId),
      errorEventId: clearError ? null : (errorEventId ?? this.errorEventId),
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

/// Keeps a single [Player] alive at a time — the currently playing video.
/// When the user taps a different video, the previous one is disposed.
/// Timeline rebuilds do NOT touch the active player; playback survives.
class VideoSessionNotifier extends StateNotifier<VideoSessionState> {
  VideoSessionNotifier() : super(const VideoSessionState());

  StreamSubscription<bool>? _playingSub;

  Future<void> playOrToggle({
    required String eventId,
    required Future<String> Function() resolveSource,
  }) async {
    final current = state.active;
    if (current != null && current.eventId == eventId) {
      final p = current.player;
      if (p.state.playing) {
        p.pause();
      } else {
        p.play();
      }
      return;
    }

    final prev = current;
    await _playingSub?.cancel();
    _playingSub = null;
    state = state.copyWith(
      clearActive: true,
      loadingEventId: eventId,
      clearError: true,
      isPlaying: false,
    );
    await prev?.player.dispose();

    try {
      final src = await resolveSource();
      final player = Player();
      final controller = VideoController(player);
      await player.open(Media(src), play: true);

      if (state.loadingEventId != eventId) {
        await player.dispose();
        return;
      }

      _playingSub = player.stream.playing.listen((playing) {
        if (!mounted) return;
        if (state.active?.eventId == eventId) {
          state = state.copyWith(isPlaying: playing);
        }
      });

      state = VideoSessionState(
        active: VideoSession(
          eventId: eventId,
          player: player,
          controller: controller,
        ),
        isPlaying: player.state.playing,
      );
    } catch (_) {
      if (state.loadingEventId == eventId) {
        state = state.copyWith(clearLoading: true, errorEventId: eventId);
      }
    }
  }

  Future<void> stop() async {
    await _playingSub?.cancel();
    _playingSub = null;
    await state.active?.player.dispose();
    state = const VideoSessionState();
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    state.active?.player.dispose();
    super.dispose();
  }
}

final videoSessionProvider =
    StateNotifierProvider<VideoSessionNotifier, VideoSessionState>(
  (ref) => VideoSessionNotifier(),
);
