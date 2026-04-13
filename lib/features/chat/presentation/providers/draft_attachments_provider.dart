import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/staged_attachment.dart';

/// Per-room staged attachments — survive navigation but clear on app restart.
/// Cap is enforced at [add] time: overflow items are dropped silently and
/// [add] returns the number actually accepted so callers can toast about
/// the rejection.
class DraftAttachmentsNotifier extends StateNotifier<List<StagedAttachment>> {
  DraftAttachmentsNotifier() : super(const []);

  static const maxPerDraft = 5;

  /// Add [attachments] up to the cap. Returns the count actually added
  /// (caller may surface a toast if this is less than requested).
  int add(List<StagedAttachment> attachments) {
    final remaining = maxPerDraft - state.length;
    if (remaining <= 0) return 0;
    final toAdd = attachments.take(remaining).toList();
    if (toAdd.isEmpty) return 0;
    state = [...state, ...toAdd];
    return toAdd.length;
  }

  void remove(String id) {
    state = state.where((a) => a.id != id).toList();
  }

  void clear() {
    if (state.isNotEmpty) state = const [];
  }
}

final draftAttachmentsProvider = StateNotifierProvider.family<
    DraftAttachmentsNotifier, List<StagedAttachment>, String>(
  (ref, roomId) => DraftAttachmentsNotifier(),
);
